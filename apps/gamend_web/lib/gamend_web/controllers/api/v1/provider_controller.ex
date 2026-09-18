defmodule GamendWeb.Api.V1.ProviderController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.OkResponse

  operation(:link_device,
    operation_id: "link_device",
    summary: "Link device ID",
    description: "Links a device_id to the current authenticated user's account.",
    tags: ["Authentication"],
    security: [%{"authorization" => []}],
    request_body:
      {"Device ID", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           device_id: %OpenApiSpex.Schema{type: :string}
         },
         required: [:device_id]
       }},
    responses: [
      ok: {"Success", "application/json", OkResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized")
    ]
  )

  def link_device(conn, %{"device_id" => device_id}) when is_binary(device_id) do
    user = Scope.user(conn.assigns.current_scope)

    case Accounts.link_device_id(user, device_id) do
      {:ok, _user} ->
        reply_ok(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)
    end
  end

  def link_device(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "device_id is required")
  end

  operation(:unlink_device,
    operation_id: "unlink_device",
    summary: "Unlink device ID",
    description:
      "Unlinks the device_id from the current authenticated user. Requires at least one OAuth provider or password to remain.",
    tags: ["Authentication"],
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized")
    ]
  )

  def unlink_device(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)

    case Accounts.unlink_device_id(user) do
      {:ok, _user} ->
        reply_ok(conn)

      {:error, :last_auth_method} ->
        reply_error(
          conn,
          :bad_request,
          "last_auth_method",
          "Cannot unlink the last way to sign in"
        )

      {:error, _} ->
        reply_error(conn, :bad_request, "unlink_failed")
    end
  end

  operation(:unlink,
    operation_id: "unlink_provider",
    summary: "Unlink OAuth provider",
    description: "Unlinks a provider from the current authenticated user.",
    tags: ["Authentication"],
    security: [%{"authorization" => []}],
    parameters: [
      provider: [
        in: :path,
        name: "provider",
        schema: %OpenApiSpex.Schema{
          type: :string,
          enum: ["discord", "apple", "google", "facebook", "steam"]
        },
        required: true
      ]
    ],
    responses: [
      ok: {"Success", "application/json", OkResponse},
      bad_request: Schemas.error("Bad request"),
      unauthorized: Schemas.error("Unauthorized")
    ]
  )

  def unlink(conn, %{"provider" => provider}) do
    user = Scope.user(conn.assigns.current_scope)

    provider_atom =
      case provider do
        "discord" -> :discord
        "apple" -> :apple
        "google" -> :google
        "facebook" -> :facebook
        "steam" -> :steam
        _ -> :unknown_provider
      end

    if provider_atom == :unknown_provider do
      reply_error(conn, :bad_request, "unknown_provider")
    else
      case Accounts.unlink_provider(user, provider_atom) do
        {:ok, _user} ->
          reply_ok(conn)

        {:error, :last_provider} ->
          reply_error(
            conn,
            :bad_request,
            "last_auth_method",
            "Cannot unlink the last way to sign in"
          )

        {:error, _} ->
          reply_error(conn, :bad_request, "unlink_failed")
      end
    end
  end
end
