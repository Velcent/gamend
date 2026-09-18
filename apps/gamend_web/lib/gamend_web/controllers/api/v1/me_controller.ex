defmodule GamendWeb.Api.V1.MeController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AvatarUpdate, CurrentUser, ProfileUpdate, UploadTicket}
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Users"])

  operation(:show,
    operation_id: "get_current_user",
    summary: "Return current user info",
    description: "Returns the current authenticated user's basic information.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"User info", "application/json", CurrentUser},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def show(conn, _params) do
    # Guardian pipeline has already authenticated and loaded the user
    # into current_scope via AssignCurrentScope plug
    case Scope.user(conn.assigns.current_scope) do
      %User{} = user ->
        json(conn, %{
          id: user.id,
          email: user.email || "",
          profile_url: user.profile_url || "",
          metadata: user.metadata || %{},
          username: user.username || "",
          display_name: user.display_name || "",
          lobby_id: user.lobby_id || "",
          party_id: user.party_id || "",
          is_online: user.is_online || false,
          last_seen_at: User.last_seen_at_or_fallback(user),
          linked_providers: Gamend.Accounts.get_linked_providers(user),
          has_password: Gamend.Accounts.has_password?(user)
        })

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})
    end
  end

  operation(:update_password,
    operation_id: "update_current_user_password",
    summary: "Update current user password",
    request_body: {
      "New password payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          password: %Schema{type: :string},
          current_password: %Schema{
            type: :string,
            description: "Required when the account already has a password."
          }
        },
        required: [:password]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Password updated", "application/json", ProfileUpdate},
      bad_request: Schemas.error("Invalid data"),
      unauthorized: Schemas.error("Not authenticated, or wrong current password")
    ]
  )

  def update_password(conn, %{"password" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    if password_change_authorized?(user, params) do
      case Gamend.Accounts.update_user_password(user, params) do
        {:ok, {user, _tokens}} ->
          json(conn, %{ok: true, id: user.id})

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{
            error: "invalid_data",
            errors: GamendWeb.ChangesetErrors.errors(changeset)
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        error: "invalid_current_password",
        message: "current_password is required and must match your existing password"
      })
    end
  end

  # Accounts with an existing password must prove it to change it (a stolen
  # access token must not be escalatable into a permanent password reset).
  # OAuth/device accounts with no password yet may set one without re-auth.
  defp password_change_authorized?(user, params) do
    if is_nil(user.hashed_password) do
      true
    else
      Gamend.Accounts.valid_password?(user, params["current_password"])
    end
  end

  operation(:update_display_name,
    operation_id: "update_current_user_display_name",
    summary: "Update current user's display name",
    request_body: {
      "Display name payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          display_name: %Schema{type: :string}
        },
        required: [:display_name]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Display name updated", "application/json", ProfileUpdate},
      bad_request: Schemas.error("Invalid data"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def update_display_name(conn, %{"display_name" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case Gamend.Accounts.update_user_display_name(user, params) do
      {:ok, user} ->
        json(conn, %{ok: true, id: user.id, display_name: user.display_name || ""})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_data",
          errors: GamendWeb.ChangesetErrors.errors(changeset)
        })
    end
  end

  operation(:update_username,
    operation_id: "update_current_user_username",
    summary: "Update current user's username",
    description:
      "Sets the unique username handle. Lowercased on save; 3-32 chars of a-z, 0-9 and " <>
        "non-consecutive . _ - separators, starting and ending alphanumeric. " <>
        "Returns invalid_data when the username is malformed or already taken.",
    request_body: {
      "Username payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          username: %Schema{type: :string}
        },
        required: [:username]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Username updated", "application/json", ProfileUpdate},
      bad_request: Schemas.error("Invalid data"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def update_username(conn, %{"username" => _} = params) do
    user = Scope.user(conn.assigns.current_scope)

    case Gamend.Accounts.update_username(user, params) do
      {:ok, user} ->
        json(conn, %{ok: true, id: user.id, username: user.username || ""})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_data",
          errors: GamendWeb.ChangesetErrors.errors(changeset)
        })

      {:error, reason} when is_atom(reason) or is_binary(reason) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_data", errors: %{username: [to_string(reason)]}})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_data"})
    end
  end

  operation(:avatar_upload_url,
    operation_id: "create_current_user_avatar_upload_url",
    summary: "Request an avatar upload ticket",
    description:
      "Returns an upload ticket. Upload the image bytes to `url` with `method`/`headers`, " <>
        "then confirm with `POST /me/avatar` using the returned `key`.",
    request_body: {
      "Upload metadata",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          content_type: %Schema{type: :string, example: "image/png"},
          filename: %Schema{type: :string, example: "avatar.png"}
        },
        required: [:content_type]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Upload ticket", "application/json", UploadTicket},
      bad_request: Schemas.error("Invalid content type or size"),
      forbidden: Schemas.error("Avatars are disabled for anonymous accounts"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def avatar_upload_url(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.can_upload_avatar?(user) do
      Uploads.ticket(conn, "avatars", user.id, "avatar", Uploads.content_type(params))
    else
      avatar_forbidden(conn)
    end
  end

  # Refused at both ends: the ticket is where a well-behaved client stops, and
  # confirm is where an old ticket or a direct-to-S3 upload would otherwise slip
  # a stored object onto the account.
  defp avatar_forbidden(conn) do
    conn |> put_status(:forbidden) |> json(%{error: "anonymous_avatar_disabled"})
  end

  operation(:set_avatar,
    operation_id: "set_current_user_avatar",
    summary: "Confirm an uploaded avatar",
    description: "Records a previously uploaded object (`key`) as the user's avatar.",
    request_body: {
      "Uploaded object key",
      "application/json",
      %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Avatar updated", "application/json", AvatarUpdate},
      bad_request: Schemas.error("Object not found, or missing key"),
      forbidden: Schemas.error("Key not owned by user, or avatars disabled"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def set_avatar(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.can_upload_avatar?(user),
      do: do_set_avatar(conn, user, params),
      else: avatar_forbidden(conn)
  end

  defp do_set_avatar(conn, user, params) do
    Uploads.confirm(conn, "avatars", user.id, params["key"], fn url ->
      case Gamend.Accounts.update_user_avatar(user, url) do
        {:ok, updated} -> json(conn, %{ok: true, profile_url: updated.profile_url})
        {:error, _} -> conn |> put_status(:bad_request) |> json(%{error: "invalid_data"})
      end
    end)
  end

  operation(:delete,
    operation_id: "delete_current_user",
    summary: "Delete current user",
    description: "Deletes the authenticated user's account",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Account deleted", "application/json", %Schema{type: :object}},
      bad_request: Schemas.error("Failed to delete account"),
      unauthorized: Schemas.error("Not authenticated, or wrong current password")
    ]
  )

  def delete(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    # Deleting the account requires the password, when there is one.
    #
    # Changing a password already demands `current_password` on the reasoning
    # that a stolen access token must not become a permanent takeover — and
    # permanently destroying the account, its stored objects, KV entries and
    # wallet is the larger of the two actions. Accounts with no password (device
    # and OAuth-only) have nothing to prove, exactly as for setting one.
    if password_change_authorized?(user, params) do
      case Gamend.Accounts.delete_user(user) do
        {:ok, _} ->
          json(conn, %{})

        {:error, _} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Failed to delete account"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "invalid_current_password"})
    end
  end
end
