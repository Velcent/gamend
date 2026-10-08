defmodule Gamend.Payments.StripeSetupTest do
  @moduledoc """
  The Stripe account setup against a fake Stripe that keeps its state in the
  test process: what a check reports, what `apply: true` changes, and that a
  second run finds nothing left to do.
  """
  use ExUnit.Case, async: false

  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.Settings
  alias Gamend.Payments.StripeSetup
  alias Gamend.SettingsHelpers

  @url "https://example.test/api/v1/payments/webhooks/stripe"

  defmodule FakeStripe do
    # Stripe's state in the process dictionary; every write is also sent to
    # the test as `{:stripe, call, args}`.
    def state(key), do: Process.get({__MODULE__, key}, [])
    def put(key, value), do: Process.put({__MODULE__, key}, value)

    def list_webhook_endpoints(_params, opts),
      do: seen(:list, opts, {:ok, %{data: state(:endpoints)}})

    def create_webhook_endpoint(params, opts) do
      id = "we_#{length(state(:endpoints)) + 1}"

      endpoint = %{
        id: id,
        url: params.url,
        api_version: params.api_version,
        enabled_events: params.enabled_events,
        status: "enabled",
        secret: "whsec_new_#{id}"
      }

      put(:endpoints, [Map.delete(endpoint, :secret) | state(:endpoints)])
      send(self(), {:stripe, :create_webhook_endpoint, params})
      seen(:create, opts, {:ok, endpoint})
    end

    def update_webhook_endpoint(id, params, _opts) do
      send(self(), {:stripe, :update_webhook_endpoint, id, params})

      put(
        :endpoints,
        Enum.map(state(:endpoints), fn
          %{id: ^id} = endpoint ->
            endpoint
            |> Map.merge(Map.take(params, [:enabled_events]))
            |> then(fn e ->
              case params do
                %{disabled: true} -> %{e | status: "disabled"}
                %{disabled: false} -> %{e | status: "enabled"}
                _ -> e
              end
            end)

          other ->
            other
        end)
      )

      {:ok, %{id: id}}
    end

    def list_portal_configurations(_params, _opts), do: {:ok, %{data: state(:portal)}}

    def update_portal_configuration(id, params, _opts) do
      send(self(), {:stripe, :update_portal_configuration, id, params})
      put(:portal, [%{id: id, features: params.features}])
      {:ok, %{id: id}}
    end

    def retrieve_product(id, _opts) do
      case Enum.find(state(:products), &(&1.id == id)) do
        nil ->
          {:error,
           %Stripe.Error{
             source: :stripe,
             code: :invalid_request_error,
             message: "No such product",
             extra: %{http_status: 404}
           }}

        product ->
          {:ok, product}
      end
    end

    def create_product(params, _opts) do
      send(self(), {:stripe, :create_product, params})
      product = Map.put(params, :active, true)
      put(:products, [product | state(:products)])
      {:ok, product}
    end

    def update_product(id, params, _opts) do
      send(self(), {:stripe, :update_product, id, params})

      put(
        :products,
        Enum.map(state(:products), &if(&1.id == id, do: Map.merge(&1, params), else: &1))
      )

      {:ok, %{id: id}}
    end

    def list_prices(%{lookup_keys: [key]}, _opts),
      do: {:ok, %{data: Enum.filter(state(:prices), &(&1[:lookup_key] == key))}}

    def create_price(params, _opts) do
      send(self(), {:stripe, :create_price, params})
      id = "price_#{length(state(:prices)) + 1}"

      prices =
        if params.transfer_lookup_key,
          do:
            Enum.map(
              state(:prices),
              &if(&1[:lookup_key] == params.lookup_key, do: Map.delete(&1, :lookup_key), else: &1)
            ),
          else: state(:prices)

      price =
        params
        |> Map.drop([:transfer_lookup_key])
        |> Map.merge(%{id: id, active: true, currency: String.downcase(params.currency)})

      put(:prices, [price | prices])
      {:ok, price}
    end

    def update_price(id, params, _opts) do
      send(self(), {:stripe, :update_price, id, params})

      put(
        :prices,
        Enum.map(state(:prices), &if(&1.id == id, do: Map.merge(&1, params), else: &1))
      )

      {:ok, %{id: id}}
    end

    defp seen(_what, opts, answer) do
      send(self(), {:stripe_opts, opts})
      answer
    end
  end

  setup do
    previous_client = Application.get_env(:gamend_core, :stripe_setup_client)
    keys = [:environment, :stripe_sandbox_secret_key]
    previous = Map.new(keys, &{&1, SettingsHelpers.get(:gamend_core, Settings, &1)})

    Application.put_env(:gamend_core, :stripe_setup_client, FakeStripe)
    SettingsHelpers.put(:gamend_core, Settings, :environment, :sandbox)
    SettingsHelpers.put(:gamend_core, Settings, :stripe_sandbox_secret_key, "sk_test_setup")

    on_exit(fn ->
      if previous_client,
        do: Application.put_env(:gamend_core, :stripe_setup_client, previous_client),
        else: Application.delete_env(:gamend_core, :stripe_setup_client)

      for {key, value} <- previous do
        if is_nil(value),
          do: SettingsHelpers.delete(:gamend_core, Settings, key),
          else: SettingsHelpers.put(:gamend_core, Settings, key, value)
      end
    end)

    :ok
  end

  describe "the webhook endpoint" do
    test "a check changes nothing; apply creates it once, on the pinned version" do
      assert [%{status: :pending}] = StripeSetup.ensure_webhook(@url)
      refute_received {:stripe, :create_webhook_endpoint, _}

      assert [%{status: :changed, message: message}] =
               StripeSetup.ensure_webhook(@url, apply: true)

      assert message =~ "whsec_new_we_1"
      assert_received {:stripe, :create_webhook_endpoint, params}
      assert params.api_version == ProviderConfig.stripe_api_version()
      assert params.enabled_events == StripeSetup.webhook_events()
      assert_received {:stripe_opts, opts}
      assert opts[:api_key] == "sk_test_setup"
      assert opts[:response_as] == :map

      findings = StripeSetup.ensure_webhook(@url, apply: true)
      refute StripeSetup.drift?(findings)
      refute_received {:stripe, :create_webhook_endpoint, _}
    end

    test "the events it sends are set to exactly the ones handled" do
      FakeStripe.put(:endpoints, [
        %{
          id: "we_old",
          url: @url,
          api_version: ProviderConfig.stripe_api_version(),
          enabled_events: ["checkout.session.completed", "invoice.paid"],
          status: "enabled"
        }
      ])

      findings = StripeSetup.ensure_webhook(@url)
      assert StripeSetup.drift?(findings)
      assert Enum.any?(findings, &(&1.status == :pending and &1.message =~ "extra invoice.paid"))

      StripeSetup.ensure_webhook(@url, apply: true)
      assert_received {:stripe, :update_webhook_endpoint, "we_old", %{enabled_events: events}}
      assert events == StripeSetup.webhook_events()
      refute StripeSetup.drift?(StripeSetup.ensure_webhook(@url))
    end

    test "another API release is replaced only when asked, with a new endpoint" do
      FakeStripe.put(:endpoints, [
        %{
          id: "we_old",
          url: @url,
          api_version: "2022-11-15",
          enabled_events: StripeSetup.webhook_events(),
          status: "enabled"
        }
      ])

      assert Enum.any?(StripeSetup.ensure_webhook(@url, apply: true), &(&1.status == :manual))
      refute_received {:stripe, :create_webhook_endpoint, _}

      findings = StripeSetup.ensure_webhook(@url, apply: true, recreate: true)
      assert Enum.any?(findings, &(&1.status == :changed and &1.message =~ "Signing secret"))
      assert_received {:stripe, :update_webhook_endpoint, "we_old", %{disabled: true}}
    end
  end

  describe "the customer portal" do
    test "not activated is a Dashboard step" do
      assert [%{status: :manual}] = StripeSetup.ensure_portal(apply: true)
    end

    test "cancels at period end, updates cards, lists invoices, never switches plans" do
      FakeStripe.put(:portal, [
        %{
          id: "bpc_1",
          features: %{
            "subscription_cancel" => %{"enabled" => true, "mode" => "immediately"},
            "subscription_update" => %{"enabled" => true}
          }
        }
      ])

      assert [%{status: :pending, message: message}] = StripeSetup.ensure_portal()
      assert message =~ "subscription_update.enabled"

      StripeSetup.ensure_portal(apply: true)
      assert_received {:stripe, :update_portal_configuration, "bpc_1", %{features: features}}
      assert features == StripeSetup.portal_features()
      assert [%{status: :ok}] = StripeSetup.ensure_portal()
    end
  end

  describe "a product and its prices" do
    @product %{id: "test_pro", name: "Test Pro", tax_code: "txcd_10103000"}
    @price %{
      lookup_key: "test:pro_yearly:standard",
      product: "test_pro",
      unit_amount: 3_900,
      currency: "eur",
      recurring: %{interval: "year"},
      tax_behavior: "inclusive"
    }

    test "the product is created, then its tax code kept" do
      assert [%{status: :pending}] = StripeSetup.ensure_product(@product)
      assert [%{status: :changed}] = StripeSetup.ensure_product(@product, apply: true)
      assert [%{status: :ok}] = StripeSetup.ensure_product(@product)

      FakeStripe.put(:products, [
        %{id: "test_pro", name: "Test Pro", tax_code: "txcd_00000000", active: true}
      ])

      assert [%{status: :pending}] = StripeSetup.ensure_product(@product)
      StripeSetup.ensure_product(@product, apply: true)
      assert_received {:stripe, :update_product, "test_pro", %{tax_code: "txcd_10103000"}}
    end

    test "a price is found by its lookup key; a changed amount is a new price" do
      assert {nil, [%{status: :pending}]} = StripeSetup.ensure_price(@price)
      assert {"price_1", [%{status: :changed}]} = StripeSetup.ensure_price(@price, apply: true)
      assert {"price_1", [%{status: :ok}]} = StripeSetup.ensure_price(@price)

      dearer = %{@price | unit_amount: 4_900}

      assert {"price_1", [%{status: :pending, message: message}]} =
               StripeSetup.ensure_price(dearer)

      assert message =~ "amount 3900 not 4900"

      assert {"price_2", findings} = StripeSetup.ensure_price(dearer, apply: true)
      assert Enum.all?(findings, &(&1.status == :changed))
      assert_received {:stripe, :create_price, %{transfer_lookup_key: true, unit_amount: 4_900}}
      assert_received {:stripe, :update_price, "price_1", %{active: false}}
      assert {"price_2", [%{status: :ok}]} = StripeSetup.ensure_price(dearer)
    end
  end

  test "with no secret key every step is an error, and nothing is called" do
    SettingsHelpers.delete(:gamend_core, Settings, :stripe_sandbox_secret_key)

    assert [%{status: :error, message: message}] = StripeSetup.ensure_webhook(@url)
    assert message =~ "no Stripe secret key"
    assert StripeSetup.drift?([%{status: :error}])
    refute StripeSetup.drift?([%{status: :ok}, %{status: :changed}])
  end
end
