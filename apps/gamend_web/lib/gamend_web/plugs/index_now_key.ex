defmodule GamendWeb.Plugs.IndexNowKey do
  @moduledoc """
  Serves the IndexNow key file that proves we own this host.

  IndexNow verifies a submission by fetching `https://host/<key>.txt` and
  checking it contains the same key that was submitted. The file is derived
  from the `GAMEND_INDEX_NOW_KEY` setting rather than written to disk, so
  rotating the key is a config change and nothing can go stale.

  A no-op when IndexNow is unconfigured, and it only ever answers the one exact
  path — every other request falls through untouched.
  """

  import Plug.Conn

  alias GamendWeb.IndexNow

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    case IndexNow.key_path() do
      ^path ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, IndexNow.key())
        |> halt()

      _ ->
        conn
    end
  end
end
