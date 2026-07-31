defmodule GamendWeb.Plugs.CaptchaCsp do
  @moduledoc """
  Widens the browser Content-Security-Policy for the captcha widget, and only
  while the captcha is enabled.

  The widget loads a script from Cloudflare and then draws itself in an iframe
  served from the same host, so `script-src` and `frame-src` both have to name
  that origin — under the policy in `GamendWeb.Router.Shared` the widget is
  otherwise blocked outright.

  This is a plug rather than an extra term in the policy because
  `plug :put_secure_browser_headers, RouterShared.browser_headers()` evaluates
  its options when the *router* compiles. A settings lookup there would run
  before `runtime.exs` has read the environment, baking in whatever the compiled
  default happened to be. Deciding per request is what makes
  `GAMEND_CAPTCHA_ENABLED` mean anything, and it keeps deployments that never
  enable the captcha on exactly the policy they have today.
  """

  @behaviour Plug

  alias Gamend.Captcha

  @header "content-security-policy"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Captcha.enabled?() do
      widen(conn, Captcha.script_origin())
    else
      conn
    end
  end

  defp widen(conn, origin) do
    case Plug.Conn.get_resp_header(conn, @header) do
      [policy | _] ->
        Plug.Conn.put_resp_header(conn, @header, add_origin(policy, origin))

      [] ->
        conn
    end
  end

  # Appends to the two directives by name, leaving the rest of the policy — and
  # anything a host added to it — untouched. A directive that is somehow absent
  # is left absent rather than invented: `default-src` already covers it, and
  # fabricating one here would silently loosen a policy someone tightened.
  defp add_origin(policy, origin) do
    policy
    |> String.split(";")
    |> Enum.map_join(";", fn directive ->
      trimmed = String.trim(directive)

      cond do
        String.contains?(trimmed, origin) -> directive
        directive?(trimmed, "script-src") -> directive <> " " <> origin
        directive?(trimmed, "frame-src") -> directive <> " " <> origin
        true -> directive
      end
    end)
  end

  defp directive?(trimmed, name), do: String.starts_with?(trimmed, name <> " ")
end
