defmodule Mix.Tasks.Gamend.Stripe.Setup do
  @shortdoc "Checks (or sets) the Stripe webhook endpoint and customer portal"

  @moduledoc """
  The Stripe account's webhook endpoint and customer portal, as
  `Gamend.Payments.StripeSetup` wants them, on the account the configured
  secret key belongs to (`GAMEND_PAYMENTS_ENVIRONMENT` picks the sandbox or
  the production key, read from `.env` like the server reads it).

      mix gamend.stripe.setup --url https://example.com/api/v1/payments/webhooks/stripe
      mix gamend.stripe.setup --url … --check            # exit 1 when anything differs
      mix gamend.stripe.setup --url … --apply            # make the changes
      mix gamend.stripe.setup --url … --apply --recreate # also replace an endpoint on another API version
      mix gamend.stripe.setup --url … --apply --live     # required to change a live (sk_live_) account

  Without `--apply` nothing changes: every line says what is right, what
  would change, and what only the Dashboard can do. A new endpoint's signing
  secret is printed once; put it in `.env`. A host with prices of its own
  runs its own task, which calls `run_steps/2` with them.
  """

  use Mix.Task

  alias Gamend.Payments.ProviderConfig
  alias Gamend.Payments.StripeSetup

  @switches [url: :string, apply: :boolean, check: :boolean, recreate: :boolean, live: :boolean]

  # What the API cannot set, printed after every run.
  @dashboard_only [
    "Settings -> Billing -> Subscriptions and emails -> Manage failed payments: cancel the subscription when all retries fail",
    "Settings -> Managed Payments: accept the terms (when GAMEND_PAYMENTS_STRIPE_MANAGED_PAYMENTS is on)",
    "Settings -> Checkout and Payment Links: terms of service and privacy policy links"
  ]

  @impl true
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)

    url =
      opts[:url] ||
        Mix.raise("--url is required: the public URL of /api/v1/payments/webhooks/stripe")

    run_steps(opts, fn step_opts ->
      StripeSetup.ensure_webhook(url, step_opts) ++ StripeSetup.ensure_portal(step_opts)
    end)
  end

  @doc """
  Loads the config, prints which account and mode, refuses `--apply` on a
  live key without `--live`, runs `steps` with `[apply:, recreate:]`, prints
  every finding and the Dashboard-only steps, and with `--check` raises when
  anything differs. For a host task that adds steps of its own.
  """
  @spec run_steps(keyword(), (keyword() -> [StripeSetup.finding()])) :: [StripeSetup.finding()]
  def run_steps(opts, steps) when is_function(steps, 1) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:stripity_stripe)

    apply? = opts[:apply] == true
    live? = live_key?()

    Mix.shell().info(
      "Stripe #{ProviderConfig.environment()} (#{if live?, do: "LIVE key", else: "test key"}), " <>
        "API #{ProviderConfig.stripe_api_version()}, #{if apply?, do: "APPLYING changes", else: "checking only"}"
    )

    if apply? and live? and opts[:live] != true,
      do: Mix.raise("This is a live Stripe key. Add --live to change the live account.")

    findings = steps.(apply: apply?, recreate: opts[:recreate] == true)
    print(findings)

    Mix.shell().info("\nDashboard only (the API cannot set these):")
    Enum.each(@dashboard_only, &Mix.shell().info("  - " <> &1))

    if opts[:check] && StripeSetup.drift?(findings),
      do: Mix.raise("Stripe differs from what this server expects (see above).")

    findings
  end

  @doc "Prints findings, one line each, marked by status."
  @spec print([StripeSetup.finding()]) :: :ok
  def print(findings) do
    Enum.each(findings, fn %{area: area, status: status, message: message} ->
      Mix.shell().info("#{mark(status)} #{area}: #{message}")
    end)
  end

  defp mark(:ok), do: "  ok     "
  defp mark(:changed), do: "  CHANGED"
  defp mark(:pending), do: "  TODO   "
  defp mark(:manual), do: "  MANUAL "
  defp mark(:error), do: "  ERROR  "

  defp live_key?,
    do: String.starts_with?(ProviderConfig.stripe_secret_key() || "", ["sk_live_", "rk_live_"])
end
