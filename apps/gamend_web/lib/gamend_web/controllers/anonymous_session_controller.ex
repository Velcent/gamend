defmodule GamendWeb.AnonymousSessionController do
  @moduledoc """
  `POST /users/anonymous_session`: writes into the browser's session the
  anonymous account a LiveView made for it (`GamendWeb.UserAuth.ensure_user/1`).
  `app.js` sends the encrypted token the page pushed, then reconnects the
  socket. 204 on success, 422 for a token that is missing, stale or not an
  anonymous account's.
  """
  use GamendWeb, :controller

  alias GamendWeb.UserAuth

  def create(conn, %{"token" => token}) when is_binary(token) do
    case UserAuth.put_anonymous_session(conn, token) do
      {:ok, conn} -> send_resp(conn, 204, "")
      :error -> send_resp(conn, 422, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, 422, "")
end
