defmodule GamendWeb.Plugs.VisitorId do
  @moduledoc """
  A stable id for one browser session, whether or not anyone is signed in.

  `Gamend.Accounts.Scope` deliberately only exists for an authenticated caller —
  `Scope.for_user(nil)` is `nil` — so a signed-out visitor has no id anywhere in
  the system. That is the right shape for authorization, and the wrong shape for
  the handful of things that must count *something* about a visitor who has not
  told you who they are: a free-tier daily allowance, an A/B bucket, a
  first-visit tour.

  This mints one into the session and assigns it, so both a controller
  (`conn.assigns.visitor_id`) and a LiveView (`session["visitor_id"]` at
  `mount/3`) can read the same value.

  ## It is not an identity, and must never be used as one

  It is a bearer value in a cookie the visitor holds. Anyone can clear it and
  get a new one, and two people sharing a browser share it. So it may key a
  *nudge* — how many free tests are left today — and must never key a
  permission, a purchase, a quota that costs real money, or anything that
  survives being wrong. Authorization reads `current_scope` and nothing else.

  It is also not a tracking id: it lives in the session cookie that is already
  set for interactive pages, is never written to the database, never leaves the
  server, and dies with the session.

  ## Not in the `:browser` pipeline

  Deliberately: minting on every browser request would attach a `Set-Cookie` to
  every crawlable page, and a content site's crawlable pages are the ones that
  most want to stay cacheable and cookie-free. Pipe it through only on the
  routes that need to count something — see `gamend_current_user_routes/2`'s
  `:extra_pipelines`.
  """

  @behaviour Plug

  @session_key "visitor_id"

  # 16 bytes is a collision space no site reaches, and short enough that the
  # session cookie does not grow meaningfully.
  @bytes 16

  @doc "The session key the id is stored under."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Plug.Conn.get_session(conn, @session_key) do
      id when is_binary(id) and byte_size(id) > 0 ->
        Plug.Conn.assign(conn, :visitor_id, id)

      _ ->
        id = generate()

        conn
        |> Plug.Conn.put_session(@session_key, id)
        |> Plug.Conn.assign(:visitor_id, id)
    end
  end

  @doc "A fresh id. URL-safe so it is readable in a log line without escaping."
  @spec generate() :: String.t()
  def generate, do: @bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
