defmodule GameServerWeb.Api.V1.ReadyCheckController do
  @moduledoc """
  The one client-facing surface for ready checks.

  A player is in at most one check at a time, so answering needs no id:
  `GET /me/ready_check` is the current one and `POST /me/ready_check` answers
  it, whether it came from a lobby or from matchmaking.
  """
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Accounts.Scope
  alias GameServer.Accounts.User
  alias GameServer.Lobbies
  alias GameServer.ReadyChecks
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  @check_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: ["ready", "accept"]},
      status: %Schema{type: :string, enum: ["pending", "passed", "failed", "cancelled"]},
      lobby_id: %Schema{type: :string},
      deadline: %Schema{type: :string, format: :"date-time", nullable: true},
      opened_by: %Schema{type: :string},
      reason: %Schema{type: :string},
      total: %Schema{type: :integer},
      ready_count: %Schema{type: :integer},
      your_state: %Schema{type: :string},
      participants: %Schema{
        type: :array,
        description: "Only on kind=ready; an accept check returns counts alone",
        items: %Schema{type: :object}
      }
    }
  }

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  tags(["Ready checks"])

  operation(:show,
    operation_id: "get_my_ready_check",
    summary: "Get the caller's open ready check",
    description:
      "Returns the check the caller is currently expected to answer, or null. " <>
        "A kind=ready check lists every participant; a kind=accept check returns " <>
        "counts and the caller's own state only.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Open ready check or null", "application/json", @check_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def show(conn, _params) do
    with_user(conn, fn user ->
      json(conn, %{
        data: Serializers.serialize_ready_check(ReadyChecks.for_user(user.id), viewer_id: user.id)
      })
    end)
  end

  operation(:respond,
    operation_id: "respond_ready_check",
    summary: "Answer the caller's open ready check",
    description:
      "`ready: true` is ready/accept, `false` is not-ready/decline. In a kind=ready " <>
        "check the answer can be flipped freely; in a kind=accept check it is final, " <>
        "and a decline fails the check for everyone.",
    security: [%{"authorization" => []}],
    request_body: {
      "The answer",
      "application/json",
      %Schema{
        type: :object,
        properties: %{ready: %Schema{type: :boolean}},
        required: [:ready]
      }
    },
    responses: [
      ok: {"The check after the answer", "application/json", @check_schema},
      bad_request: {"Missing or invalid ready flag", "application/json", @error_schema},
      conflict: {"No open check, or the answer is final", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def respond(conn, %{"ready" => ready}) when is_boolean(ready) do
    with_user(conn, fn user ->
      case ReadyChecks.respond(user, ready) do
        {:ok, check} ->
          json(conn, Serializers.serialize_ready_check(check, viewer_id: user.id))

        {:error, :no_open_check} ->
          conn |> put_status(:conflict) |> json(%{error: "no_open_check"})

        {:error, :not_revocable} ->
          conn |> put_status(:conflict) |> json(%{error: "not_revocable"})

        {:error, :already_resolved} ->
          conn |> put_status(:conflict) |> json(%{error: "already_resolved"})

        _other ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
      end
    end)
  end

  def respond(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_ready"})

  operation(:open,
    operation_id: "open_lobby_ready_check",
    summary: "Open a ready check in the caller's lobby (host only)",
    description:
      "Allowed only for the host of a host-managed lobby: hostless (matchmaking) " <>
        "lobbies belong to the server, so no player may open one there. Every current " <>
        "member becomes a participant and the host is pre-marked ready — clicking the " <>
        "button is their answer. Core never kicks or starts anything on the result.",
    security: [%{"authorization" => []}],
    request_body: {
      "Options",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          timeout_ms: %Schema{
            type: :integer,
            description: "Answering window; omit for the configured default"
          },
          metadata: %Schema{type: :object, description: "Echoed to clients"}
        }
      }
    },
    responses: [
      created: {"The open check", "application/json", @check_schema},
      bad_request: {"Not in a lobby", "application/json", @error_schema},
      forbidden: {"Not the host, or the lobby is hostless", "application/json", @error_schema},
      conflict: {"A check is already open", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def open(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if host_of?(user, lobby) do
        member_ids = lobby |> Lobbies.get_lobby_members() |> Enum.map(& &1.id)

        opts =
          [opened_by: user.id, metadata: Map.get(params, "metadata", %{})]
          |> maybe_timeout(Map.get(params, "timeout_ms"))

        case ReadyChecks.open(lobby, member_ids, opts) do
          {:ok, check} ->
            conn
            |> put_status(:created)
            |> json(Serializers.serialize_ready_check(check, viewer_id: user.id))

          {:error, :already_pending} ->
            conn |> put_status(:conflict) |> json(%{error: "already_pending"})

          {:error, {:hook_rejected, reason}} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "rejected", reason: inspect(reason)})

          {:error, reason} when is_atom(reason) ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})

          _other ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
        end
      else
        conn |> put_status(:forbidden) |> json(%{error: "not_host"})
      end
    end)
  end

  operation(:cancel,
    operation_id: "cancel_lobby_ready_check",
    summary: "Call off the ready check in the caller's lobby (host only)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Cancelled", "application/json", %Schema{type: :object}},
      bad_request: {"Not in a lobby", "application/json", @error_schema},
      forbidden: {"Not the host, or the lobby is hostless", "application/json", @error_schema},
      not_found: {"No open check", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def cancel(conn, _params) do
    with_lobby(conn, fn user, lobby ->
      cond do
        not host_of?(user, lobby) ->
          conn |> put_status(:forbidden) |> json(%{error: "not_host"})

        is_nil(ReadyChecks.pending_for_lobby(lobby.id)) ->
          conn |> put_status(:not_found) |> json(%{error: "no_open_check"})

        true ->
          :ok = ReadyChecks.cancel_for_lobby(lobby.id)
          json(conn, %{})
      end
    end)
  end

  # The same rule as POST /lobbies/state: nobody owns a hostless lobby, so no
  # player may act on it.
  defp host_of?(%User{id: user_id}, lobby), do: not lobby.hostless and lobby.host_id == user_id

  defp maybe_timeout(opts, ms) when is_integer(ms) and ms > 0,
    do: Keyword.put(opts, :timeout_ms, ms)

  defp maybe_timeout(opts, _ms), do: opts

  defp with_user(conn, fun) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user -> fun.(user)
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp with_lobby(conn, fun) do
    with_user(conn, fn user ->
      if is_nil(user.lobby_id) do
        conn |> put_status(:bad_request) |> json(%{error: "not_in_lobby"})
      else
        fun.(user, Lobbies.get_lobby!(user.lobby_id))
      end
    end)
  end
end
