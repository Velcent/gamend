defmodule GamendWeb.Api.V1.SessionController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{OkResponse, SessionResponse}
  alias OpenApiSpex.Schema

  tags(["Authentication"])

  operation(:create,
    operation_id: "login",
    summary: "Login",
    description: "Authenticate user with email and password",
    request_body: {
      "Login credentials",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "User email"},
          password: %Schema{type: :string, format: :password, description: "User password"}
        },
        required: [:email, :password],
        example: %{
          email: "user@example.com",
          password: "securepassword123"
        }
      }
    },
    responses: [
      ok: {"Login successful", "application/json", SessionResponse},
      unauthorized: Schemas.error("Invalid credentials"),
      forbidden: Schemas.error("Account awaiting activation")
    ]
  )

  def create(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      if Accounts.user_activated?(user) do
        maybe_attach_device(conn, user)
        issue_tokens(conn, user)
      else
        reply_error(
          conn,
          :forbidden,
          "account_not_activated",
          "Your account is pending activation by an administrator."
        )
      end
    else
      reply_error(conn, :unauthorized, "invalid_credentials", "Invalid email or password")
    end
  end

  operation(:create_device,
    operation_id: "device_login",
    summary: "Device login",
    description: "Authenticate or create a device-backed user using a device_id (no password).",
    request_body: {
      "Device login",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          device_id: %Schema{type: :string, description: "Device identifier string"}
        },
        required: [:device_id],
        example: %{device_id: "device:uuid-or-some-string"}
      }
    },
    responses: [
      ok: {"Login successful", "application/json", SessionResponse},
      bad_request: Schemas.error("Unable to create device user"),
      forbidden: Schemas.error("Device auth disabled, or account awaiting activation")
    ]
  )

  # Device-based login: create or find a user for a given device_id and
  # return JWTs. This enables SDKs to authenticate with a simple device_id.
  # Device-specific login endpoint. This route accepts only a device_id
  # and returns JWT tokens for the device's user.
  def create_device(conn, %{"device_id" => device_id}) when is_binary(device_id) do
    if Accounts.device_auth_enabled?() do
      case Accounts.find_or_create_from_device(device_id) do
        {:ok, user} ->
          if Accounts.user_activated?(user) do
            issue_tokens(conn, user)
          else
            reply_error(
              conn,
              :forbidden,
              "account_not_activated",
              "Your account is pending activation by an administrator."
            )
          end

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      reply_error(conn, :forbidden, "device_auth_disabled", "Device login is disabled")
    end
  end

  operation(:delete,
    operation_id: "logout",
    summary: "Logout",
    description:
      "Revoke the caller's tokens. Send the access or refresh token in the " <>
        "Authorization header. This signs the account out on every device, because " <>
        "revocation works by bumping the account's token version. Always returns 200, " <>
        "so a client with an already-expired token can still complete sign-out.",
    parameters: [],
    responses: [
      ok: {"Logout successful", "application/json", OkResponse}
    ]
  )

  # Previously this returned `%{}` and did nothing at all, while its own
  # description claimed to invalidate the session — so a client that had
  # "logged out" kept a working access token, and its refresh token stayed
  # valid for 30 days.
  #
  # There is no per-token denylist to revoke against, so revocation is
  # `token_version`, which is account-wide. Callers are told that plainly above.
  # The route is unauthenticated, so the token is read here rather than by a
  # pipeline: sign-out must not fail merely because the token already expired.
  def delete(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      _ = Accounts.revoke_all_tokens(user)
    end

    reply_ok(conn)
  end

  operation(:refresh,
    operation_id: "refresh_token",
    summary: "Refresh access token",
    security: [],
    description: "Exchange a valid refresh token for a new access token",
    request_body: {
      "Refresh token",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          refresh_token: %Schema{type: :string, description: "Valid refresh token"}
        },
        required: [:refresh_token],
        example: %{
          refresh_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
      }
    },
    responses: [
      ok: {"Token refreshed successfully", "application/json", SessionResponse},
      unauthorized: Schemas.error("Invalid or expired refresh token"),
      bad_request: Schemas.error("Bad request")
    ]
  )

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    # Verify the refresh token and check it's actually a refresh token type
    case Guardian.decode_and_verify(refresh_token, %{"typ" => "refresh"}) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            # Issue a new access token
            {:ok, new_access_token, _claims} =
              Guardian.encode_and_sign(user, %{}, token_type: "access")

            reply_data(conn, %{
              access_token: new_access_token,
              refresh_token: refresh_token,
              user_id: user.id,
              username: user.username || "",
              display_name: user.display_name || "",
              expires_in: 900
            })

          {:error, _reason} ->
            reply_error(conn, :unauthorized, "invalid_refresh_token")
        end

      {:error, _reason} ->
        reply_error(
          conn,
          :unauthorized,
          "invalid_refresh_token",
          "Invalid or expired refresh token"
        )
    end
  end

  def refresh(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "refresh_token is required")
  end

  # Best-effort device attachment when device_id is provided during email login
  defp maybe_attach_device(conn, user) do
    with %{"device_id" => device_id} when is_binary(device_id) <- conn.body_params,
         true <- is_nil(user.device_id),
         true <- Accounts.device_auth_enabled?() do
      _ = Accounts.attach_device_to_user(user, device_id)
    end

    :ok
  end

  # Generate access + refresh JWTs and return the token response
  defp issue_tokens(conn, user) do
    # Only real logins reach here (password and device create); `refresh/2`
    # builds its own token. Same login side-effects as the web session path.
    #
    # `touch_last_seen/1` joins them rather than running inline: it is two more
    # writes (the `last_seen_at` update, and the activity-day insert behind it)
    # on a path that already wrote the user row, and both are fire-and-forget by
    # construction — nothing in the response depends on either. On SQLite's
    # single writer those writes were the difference between a login returning
    # and a login waiting, and signup throughput fell as concurrency rose
    # because of them. The work still happens, and still costs the same; the
    # caller no longer holds a connection while it does.
    #
    # Tests run `Gamend.Async` inline, so anything asserting on `last_seen_at`
    # straight after a login still sees it.
    Gamend.Async.run(fn ->
      Accounts.touch_last_seen(user)
      Gamend.Hooks.internal_call(:after_user_logged_in, [user])
      Gamend.Quests.report_event(user.id, "login")
    end)

    {:ok, access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")

    {:ok, refresh_token, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {30, :days})

    reply_data(conn, %{
      access_token: access_token,
      refresh_token: refresh_token,
      expires_in: 900,
      user_id: user.id,
      username: user.username || "",
      display_name: user.display_name || ""
    })
  end
end
