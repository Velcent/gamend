defmodule GamendWeb.IndexNow do
  @moduledoc """
  Tells search engines a page changed, instead of waiting to be crawled.

  [IndexNow](https://www.indexnow.org) is a push protocol: one POST names the
  URLs that changed, and the receiving engine shares it with the others that
  participate. Submitting to any endpoint reaches all of them, so there is one
  endpoint setting and no per-engine fan-out.

  **Google does not participate.** Bing, Yandex and Seznam do. This is worth
  being clear about before wiring it up: it will not move anything in Google
  Search Console, and it is not a substitute for a sitemap.

  ## Setup

  Generate a key — any 8–128 hex characters — and set:

      GAMEND_INDEX_NOW_ENABLED=true
      GAMEND_INDEX_NOW_KEY=2f7c1a...

  Ownership is proven by serving the key back at `https://host/<key>.txt`,
  which `GamendWeb.Plugs.IndexNowKey` does automatically from the same setting.
  There is nothing to upload and no account.

  ## What to submit

  Only genuine changes. The protocol exists to save crawlers from polling, and
  an engine that finds resubmitted-but-unchanged URLs will discount the source
  — the same trust problem as an untruthful `<lastmod>`. `mix
  gamend.sitemap.lastmod` reports exactly which pages moved; that list is the
  intended input:

      changed |> Enum.map(&url_for/1) |> GamendWeb.IndexNow.submit()

  Submission is best-effort. A failure is logged and returned, never raised:
  search engines finding out late is not worth failing a deploy over.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :index_now,
    label: "IndexNow"

  require Logger

  setting(:enabled, :boolean,
    default: false,
    doc: "Notify IndexNow search engines (Bing, Yandex, Seznam — not Google) when pages change."
  )

  setting(:key, :string,
    required: :warn,
    when: {[:index_now, :enabled], true},
    doc:
      "IndexNow key, 8-128 hex characters. Public by design — it is served at /<key>.txt to " <>
        "prove domain ownership."
  )

  setting(:endpoint, :string,
    default: "https://api.indexnow.org/indexnow",
    doc: "IndexNow submission endpoint. Any participating engine's endpoint reaches all of them."
  )

  setting(:timeout_ms, :integer,
    default: 10_000,
    doc: "How long to wait for the IndexNow endpoint before giving up."
  )

  # The protocol caps a single submission at 10,000 URLs.
  @max_urls 10_000

  @typedoc "Why a submission did not happen, or did not succeed."
  @type error ::
          :disabled | :no_key | :invalid_key | {:status, pos_integer()} | {:request, term()}

  @doc "Whether change notifications are configured and on."
  @spec enabled?() :: boolean()
  def enabled?, do: Gamend.Settings.get(__MODULE__, :enabled) == true and key() != nil

  @doc "The configured key, or nil when unset or malformed."
  @spec key() :: String.t() | nil
  def key do
    case Gamend.Settings.get(__MODULE__, :key) do
      key when is_binary(key) -> if valid_key?(key), do: key, else: nil
      _ -> nil
    end
  end

  @doc """
  Whether a key meets the protocol's requirements: 8–128 hexadecimal
  characters. Rejecting a malformed key here turns a silent 403 from the
  endpoint into a log line at startup.
  """
  @spec valid_key?(String.t()) :: boolean()
  def valid_key?(key) when is_binary(key), do: key =~ ~r/\A[a-fA-F0-9]{8,128}\z/
  def valid_key?(_), do: false

  @doc "The path the key file is served at, e.g. `/2f7c1a.txt`."
  @spec key_path() :: String.t() | nil
  def key_path do
    case key() do
      nil -> nil
      key -> "/" <> key <> ".txt"
    end
  end

  @doc """
  Submits changed URLs.

  URLs must be absolute and all on the same host — the protocol rejects a
  submission that mixes hosts, since the key only proves ownership of one.
  Returns `:ok`, or `{:error, reason}` when disabled, misconfigured, or the
  endpoint refused. Over #{@max_urls} URLs are sent in batches.
  """
  @spec submit([String.t()]) :: :ok | {:error, error()}
  def submit([]), do: :ok

  def submit(urls) when is_list(urls) do
    cond do
      Gamend.Settings.get(__MODULE__, :enabled) != true -> {:error, :disabled}
      is_nil(Gamend.Settings.get(__MODULE__, :key)) -> {:error, :no_key}
      is_nil(key()) -> {:error, :invalid_key}
      true -> submit_batches(urls)
    end
  end

  defp submit_batches(urls) do
    urls
    |> Enum.chunk_every(@max_urls)
    |> Enum.reduce_while(:ok, fn batch, :ok ->
      case post(batch) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp post(urls) do
    host = host_of(hd(urls))

    body = %{
      host: host,
      key: key(),
      keyLocation: "https://" <> host <> key_path(),
      urlList: urls
    }

    request =
      Req.post(Gamend.Settings.get(__MODULE__, :endpoint),
        json: body,
        receive_timeout: Gamend.Settings.get(__MODULE__, :timeout_ms),
        retry: false
      )

    case request do
      # 200 accepted; 202 accepted but the key is still being validated.
      {:ok, %Req.Response{status: status}} when status in [200, 202] ->
        Logger.info("IndexNow: submitted #{length(urls)} URLs for #{host}")
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("IndexNow: #{host} rejected with #{status}")
        {:error, {:status, status}}

      {:error, reason} ->
        Logger.warning("IndexNow: submission failed: #{inspect(reason)}")
        {:error, {:request, reason}}
    end
  end

  defp host_of(url), do: URI.parse(url).host
end
