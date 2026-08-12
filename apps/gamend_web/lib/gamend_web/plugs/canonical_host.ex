defmodule GamendWeb.Plugs.CanonicalHost do
  @moduledoc """
  Redirects every other hostname to the one canonical host.

  `www.example.com` and `example.com` are different URLs to a crawler. Serving
  both with a 200 splits the ranking signals of every page across two
  addresses; a `rel=canonical` tag asks search engines to merge them, but only
  after they have fetched both, and it is only a hint.

  Off unless `:canonical_host` is set, because the right answer is a host
  decision — some sites are canonically `www`. A host opts in with:

      config :gamend_web, :canonical_host, "example.com"

  ## What is deliberately not redirected

    * **Anything but GET/HEAD.** A 301 on a POST loses the body: browsers
      re-issue it as a GET, so a form submitted to the wrong host would
      silently do nothing.
    * **The health endpoint**, which container and uptime checks hit by IP or
      by an internal service name that will never be the canonical host.
    * **ACME challenges**, so a certificate for a redirected alias can still be
      issued — the challenge has to be answered on the alias itself.
    * **Requests with no host**, which is what an HTTP/1.0 client sends.

  This runs at the endpoint rather than in the CDN so it holds however the site
  is fronted. A CDN rule is fine too; both together are harmless, since the
  second request already carries the canonical host and falls straight through.
  """

  @behaviour Plug

  import Plug.Conn

  @exempt_paths [["api", "v1", "health"], [".well-known", "acme-challenge"]]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case canonical_host() do
      host when is_binary(host) and host != "" ->
        maybe_redirect(conn, host)

      _ ->
        conn
    end
  end

  defp maybe_redirect(conn, canonical) do
    if redirect?(conn, canonical) do
      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(external: target_url(conn, canonical))
      |> halt()
    else
      conn
    end
  end

  defp redirect?(%Plug.Conn{host: host} = conn, canonical) do
    is_binary(host) and host != "" and String.downcase(host) != String.downcase(canonical) and
      conn.method in ["GET", "HEAD"] and not exempt_path?(conn.path_info)
  end

  defp exempt_path?(path_info) do
    Enum.any?(@exempt_paths, &List.starts_with?(path_info, &1))
  end

  defp target_url(conn, canonical) do
    query = if conn.query_string in [nil, ""], do: "", else: "?" <> conn.query_string

    "#{conn.scheme}://#{canonical}#{port_suffix(conn)}#{conn.request_path}#{query}"
  end

  # Keep a non-default port so a redirect is still followable in development,
  # where the canonical host is reached at :4000 rather than :443.
  defp port_suffix(%Plug.Conn{scheme: :https, port: 443}), do: ""
  defp port_suffix(%Plug.Conn{scheme: :http, port: 80}), do: ""
  defp port_suffix(%Plug.Conn{port: port}) when is_integer(port), do: ":#{port}"
  defp port_suffix(_conn), do: ""

  defp canonical_host, do: Application.get_env(:gamend_web, :canonical_host)
end
