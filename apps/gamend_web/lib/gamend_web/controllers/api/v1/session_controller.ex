defmodule GamendWeb.Api.V1.SessionController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Auth.Tokens
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

  operation(:register,
    operation_id: "register",
    summary: "Register",
    description:
      "Create an account with an email and a password, send its confirmation email " <>
        "as browser sign-up does, and sign it in: the tokens come back as from login. " <>
        "The first account becomes the admin and is confirmed without an email; account " <>
        "activation applies as for every sign-up.",
    request_body: {
      "Registration",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "User email"},
          password: %Schema{type: :string, format: :password, description: "User password"},
          username: %Schema{
            type: :string,
            description: "Optional; one is generated when it is left out"
          }
        },
        required: [:email, :password],
        example: %{
          email: "user@example.com",
          password: "securepassword123"
        }
      }
    },
    responses: [
      created: {"Account created and signed in", "application/json", SessionResponse},
      bad_request: Schemas.error("Email or password missing (missing_param)"),
      forbidden: Schemas.error("The account awaits activation by an admin"),
      conflict: Schemas.error("Email or username already taken"),
      unprocessable_entity: Schemas.error("Invalid email, username or password"),
      service_unavailable: Schemas.error("The confirmation email could not be sent")
    ]
  )

  def register(conn, %{"email" => email, "password" => password} = params)
      when is_binary(email) and is_binary(password) do
    # The notifier the browser sign-up reads, so both paths send one email.
    notifier = Application.get_env(:gamend_web, :user_notifier, Gamend.Accounts.UserNotifier)

    params
    |> Map.take(["email", "password", "username"])
    |> Accounts.register_user_with_password_and_deliver(
      fn token -> url(~p"/users/confirm/#{token}") end,
      notifier
    )
    |> registered(conn)
  end

  def register(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "email and password are required")
  end

  defp registered({:ok, user}, conn) do
    if Accounts.user_activated?(user) do
      conn |> put_status(:created) |> issue_tokens(user)
    else
      reply_error(
        conn,
        :forbidden,
        "account_not_activated",
        "Your account is pending activation by an administrator."
      )
    end
  end

  defp registered({:error, %Ecto.Changeset{} = changeset}, conn) do
    if taken?(changeset),
      do: uniqueness_conflict(conn, changeset),
      else: unprocessable(conn, changeset)
  end

  # The mail did not go, and the account was rolled back with it.
  defp registered({:error, _reason}, conn) do
    reply_error(
      conn,
      :service_unavailable,
      "email_delivery_failed",
      "The confirmation email could not be sent"
    )
  end

  # An email or a username someone already has: 409, the input was fine.
  defp taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      opts[:constraint] == :unique or opts[:validation] == :unsafe_unique
    end)
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

            reply_data(conn, Tokens.session(user, new_access_token, refresh_token))

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

  # Only real logins reach here (password, device and registration); `refresh/2`
  # keeps its refresh token. Provider sign-ins go through the same
  # `Tokens.sign_in/1`.
  defp issue_tokens(conn, user), do: reply_data(conn, Tokens.sign_in(user))
end
