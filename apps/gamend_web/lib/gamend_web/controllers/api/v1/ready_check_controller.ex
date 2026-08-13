defmodule GamendWeb.Api.V1.ReadyCheckController do
  @moduledoc """
  The one client-facing surface for ready checks.

  A player holds at most one open check per lane — the match lane (lobby
  ready-up or matchmaking accept) and the party lane (the party's standing
  board) — so answering needs no id, just a `scope`. `GET /me/ready_check`
  returns both lanes; `POST /me/ready_check` answers one of them.

  `POST /lobbies/ready_check` and `POST /parties/ready_check` are **reset**
  semantics: they quietly replace any open board with a fresh one over the
  current members, so the same endpoint serves "open", "force ready" (pass a
  `timeout_ms`) and "start over".
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias Gamend.ReadyChecks
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  @check_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: ["ready", "accept"]},
      status: %Schema{type: :string, enum: ["pending", "passed", "failed", "cancelled"]},
      lobby_id: %Schema{type: :string},
      party_id: %Schema{type: :string},
      deadline_at: %Schema{type: :string, format: :"date-time", nullable: true},
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

  @checks_schema %Schema{
    type: :object,
    properties: %{
      lobby: %Schema{
        allOf: [@check_schema],
        nullable: true,
        description: "The match lane: the lobby ready-up or a matchmaking accept"
      },
      party: %Schema{
        allOf: [@check_schema],
        nullable: true,
        description: "The party's standing ready board"
      }
    }
  }

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  tags(["Ready checks"])

  operation(:show,
    operation_id: "get_my_ready_check",
    summary: "Get the caller's open ready checks",
    description:
      "Returns the caller's open check per lane — `lobby` (the match lane: " <>
        "lobby ready-up or matchmaking accept) and `party` (the party board) — " <>
        "each null when there is none. A kind=ready check lists every " <>
        "participant; a kind=accept check returns counts and the caller's own " <>
        "state only.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Open ready checks per lane", "application/json", @checks_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def show(conn, _params) do
    with_user(conn, fn user ->
      json(conn, %{
        data: %{
          lobby: serialize(ReadyChecks.for_user(user.id, :match), user),
          party: serialize(ReadyChecks.for_user(user.id, :party), user)
        }
      })
    end)
  end

  operation(:respond,
    operation_id: "respond_ready_check",
    summary: "Answer one of the caller's open ready checks",
    description:
      "`ready: true` is ready/accept, `false` is not-ready/decline. `scope` " <>
        "picks the lane: \"lobby\" (default — also answers a matchmaking " <>
        "accept) or \"party\". In a kind=ready check the answer can be flipped " <>
        "freely; in a kind=accept check it is final, and a decline fails the " <>
        "check for everyone.",
    security: [%{"authorization" => []}],
    request_body: {
      "The answer",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          ready: %Schema{type: :boolean},
          scope: %Schema{type: :string, enum: ["lobby", "party"], default: "lobby"}
        },
        required: [:ready]
      }
    },
    responses: [
      ok: {"The check after the answer", "application/json", @check_schema},
      bad_request: {"Missing or invalid ready flag or scope", "application/json", @error_schema},
      conflict: {"No open check, or the answer is final", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def respond(conn, %{"ready" => ready} = params) when is_boolean(ready) do
    with_user(conn, fn user ->
      case parse_scope(Map.get(params, "scope", "lobby")) do
        {:ok, scope} -> do_respond(conn, user, ready, scope)
        :error -> conn |> put_status(:bad_request) |> json(%{error: "invalid_scope"})
      end
    end)
  end

  def respond(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_ready"})

  defp do_respond(conn, user, ready, scope) do
    case ReadyChecks.respond(user, ready, scope) do
      {:ok, check} ->
        json(conn, serialize(check, user))

      {:error, :no_open_check} ->
        conn |> put_status(:conflict) |> json(%{error: "no_open_check"})

      {:error, :not_revocable} ->
        conn |> put_status(:conflict) |> json(%{error: "not_revocable"})

      {:error, :already_resolved} ->
        conn |> put_status(:conflict) |> json(%{error: "already_resolved"})

      _other ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
    end
  end

  operation(:open,
    operation_id: "open_lobby_ready_check",
    summary: "Open (or reset) the ready board in the caller's lobby (host only)",
    description:
      "Allowed only for the host of a host-managed lobby: hostless (matchmaking) " <>
        "lobbies belong to the server, so no player may open one there. Every current " <>
        "member becomes a participant and the host is pre-marked ready — clicking the " <>
        "button is their answer. An already-open board is quietly replaced (reset), " <>
        "so the same call serves 'ready check!', 'force ready' (with timeout_ms) " <>
        "and 'start over'. Core never kicks or starts anything on the result.",
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
      conflict: {"A member is locked in another check", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def open(conn, params) do
    with_lobby(conn, fn user, lobby ->
      if Lobbies.can_manage_lobby?(user, lobby) do
        member_ids = lobby |> Lobbies.get_lobby_members() |> Enum.map(& &1.id)
        do_reset(conn, user, lobby, member_ids, params)
      else
        conn |> put_status(:forbidden) |> json(%{error: "not_host"})
      end
    end)
  end

  operation(:open_party,
    operation_id: "open_party_ready_check",
    summary: "Open (or reset) the ready board in the caller's party (leader only)",
    description:
      "Every current member becomes a participant and the leader is pre-marked " <>
        "ready. An already-open board is quietly replaced (reset), so the same " <>
        "call serves 'ready up!', 'force ready' (with timeout_ms) and " <>
        "'start over'. The party board is independent of any lobby check.",
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
      bad_request: {"Not in a party", "application/json", @error_schema},
      forbidden: {"Not the party leader", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def open_party(conn, params) do
    with_party(conn, fn user, party ->
      if Parties.can_manage_party?(user, party) do
        member_ids = party.id |> Parties.get_party_members() |> Enum.map(& &1.id)
        # A party board STANDS: it is the crew's answer to "are you coming",
        # asked once and left up, not a countdown gating a match start the way a
        # lobby board is. Without this it inherited the lobby default (20s), and
        # a crew member who looked away lost the board out from under both of
        # them — an expired check reports no participants, so the crew's button
        # went to a disabled "Waiting for the captain" and the leader's to a
        # disabled "Waiting for crew", with nothing left to reopen it. A caller
        # that genuinely wants a fuse still gets one by sending timeout_ms.
        do_reset(conn, user, party, member_ids, params, nil)
      else
        conn |> put_status(:forbidden) |> json(%{error: "not_leader"})
      end
    end)
  end

  defp do_reset(conn, user, subject, member_ids, params, default_timeout_ms \\ :subject_default) do
    opts =
      [opened_by: user.id, metadata: Map.get(params, "metadata", %{})]
      |> maybe_timeout(Map.get(params, "timeout_ms"), default_timeout_ms)

    case ReadyChecks.reset(subject, member_ids, opts) do
      {:ok, check} ->
        conn
        |> put_status(:created)
        |> json(serialize(check, user))

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
        not Lobbies.can_manage_lobby?(user, lobby) ->
          conn |> put_status(:forbidden) |> json(%{error: "not_host"})

        is_nil(ReadyChecks.pending_for_lobby(lobby.id)) ->
          conn |> put_status(:not_found) |> json(%{error: "no_open_check"})

        true ->
          :ok = ReadyChecks.cancel_for_lobby(lobby.id)
          json(conn, %{})
      end
    end)
  end

  operation(:cancel_party,
    operation_id: "cancel_party_ready_check",
    summary: "Call off the ready check in the caller's party (leader only)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Cancelled", "application/json", %Schema{type: :object}},
      bad_request: {"Not in a party", "application/json", @error_schema},
      forbidden: {"Not the party leader", "application/json", @error_schema},
      not_found: {"No open check", "application/json", @error_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def cancel_party(conn, _params) do
    with_party(conn, fn user, party ->
      cond do
        party.leader_id != user.id ->
          conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

        is_nil(ReadyChecks.pending_for_party(party.id)) ->
          conn |> put_status(:not_found) |> json(%{error: "no_open_check"})

        true ->
          :ok = ReadyChecks.cancel_for_party(party.id)
          json(conn, %{})
      end
    end)
  end

  defp parse_scope("lobby"), do: {:ok, :match}
  defp parse_scope("party"), do: {:ok, :party}
  defp parse_scope(_scope), do: :error

  defp serialize(check, user), do: Serializers.serialize_ready_check(check, viewer_id: user.id)

  # What the caller asked for always wins. Otherwise the subject decides:
  # `:subject_default` leaves the option off entirely, so ReadyChecks applies
  # its own `ready_check_timeout_ms`; an explicit `nil` opens a board with no
  # deadline at all (see open_party).
  defp maybe_timeout(opts, ms, _default) when is_integer(ms) and ms > 0,
    do: Keyword.put(opts, :timeout_ms, ms)

  defp maybe_timeout(opts, _ms, :subject_default), do: opts

  defp maybe_timeout(opts, _ms, default), do: Keyword.put(opts, :timeout_ms, default)

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

  defp with_party(conn, fun) do
    with_user(conn, fn user ->
      case user.party_id && Parties.get_party(user.party_id) do
        %Parties.Party{} = party -> fun.(user, party)
        _ -> conn |> put_status(:bad_request) |> json(%{error: "not_in_party"})
      end
    end)
  end
end
