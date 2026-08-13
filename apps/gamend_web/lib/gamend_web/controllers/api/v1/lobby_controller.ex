defmodule GamendWeb.Api.V1.LobbyController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Lobbies.SpectatorTracker
  alias Gamend.Parties
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Lobbies"])

  # Shared schema for lobby response
  @lobby_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Lobby ID"},
      title: %Schema{type: :string, description: "Display title"},
      host_id: %Schema{
        type: :string,
        format: :uuid,
        description: "User ID of the host",
        nullable: true
      },
      host_name: %Schema{type: :string, description: "Display name of the host"},
      hostless: %Schema{type: :boolean, description: "Whether this is a server-managed lobby"},
      max_users: %Schema{type: :integer, description: "Maximum number of users allowed"},
      is_hidden: %Schema{type: :boolean, description: "Hidden from public listings"},
      is_locked: %Schema{type: :boolean, description: "Locked - no new joins allowed"},
      is_passworded: %Schema{
        type: :boolean,
        description: "Whether this lobby requires a password to join"
      },
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = disabled)"}
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      # 'name' (slug) intentionally omitted from API responses - use 'id' and 'title'
      title: "My Game Lobby",
      host_id: "0198c0de-0002-7000-8000-000000000002",
      host_name: "PlayerOne",
      hostless: false,
      max_users: 8,
      is_hidden: false,
      is_locked: false,
      is_passworded: false,
      metadata: %{},
      slowdown: 0
    }
  }

  operation(:index,
    operation_id: "list_lobbies",
    summary: "List lobbies",
    description:
      "Return all non-hidden lobbies. Supports optional text search via 'title', metadata filters, password/lock filters, and numeric min/max for max_users.",
    parameters: [
      title: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Search term for title"
      ],
      is_passworded: [
        in: :query,
        schema: %Schema{type: :boolean},
        description: "Filter by passworded lobbies (omit for any)"
      ],
      is_locked: [
        in: :query,
        schema: %Schema{type: :boolean},
        description: "Filter by locked status (omit for any)"
      ],
      min_users: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Minimum max_users to include"
      ],
      max_users: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Maximum max_users to include"
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page number (1-based)",
        required: false
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer},
        description: "Page size (max results per page)",
        required: false
      ],
      metadata_key: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Optional metadata key to filter by"
      ],
      metadata_value: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Optional metadata value to match (used with metadata_key)"
      ]
    ],
    responses: [
      ok:
        {"List of lobbies (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @lobby_schema},
             meta: %Schema{
               type: :object,
               properties: %{
                 page: %Schema{type: :integer},
                 page_size: %Schema{type: :integer},
                 count: %Schema{type: :integer},
                 total_count: %Schema{type: :integer},
                 total_pages: %Schema{type: :integer},
                 has_more: %Schema{type: :boolean}
               }
             }
           }
         }}
    ]
  )

  operation(:create,
    operation_id: "create_lobby",
    summary: "Create a lobby",
    description:
      "Create a new lobby. The authenticated user becomes the host and is automatically joined.",
    security: [%{"authorization" => []}],
    request_body: {
      "Lobby creation parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Display title for the lobby"},
          max_users: %Schema{
            type: :integer,
            description: "Maximum users allowed (default: 8)",
            default: 8
          },
          is_hidden: %Schema{
            type: :boolean,
            description: "Hide from public listings",
            default: false
          },
          is_locked: %Schema{type: :boolean, description: "Lock the lobby", default: false},
          password: %Schema{
            type: :string,
            description: "Optional password to protect the lobby"
          },
          metadata: %Schema{type: :object, description: "Arbitrary metadata"},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        },
        example: %{
          title: "My Game Lobby",
          max_users: 4,
          is_hidden: false
        }
      }
    },
    responses: [
      created: {"Lobby created", "application/json", @lobby_schema},
      conflict:
        {"User already in a lobby", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:set_state,
    operation_id: "set_lobby_state",
    summary: "Set lobby state (host or pinned WebRTC host)",
    description:
      "Move a lobby to another lifecycle state. Allowed for the host of a " <>
        "host-managed lobby and for the lobby's pinned WebRTC host; a hostless " <>
        "(matchmaking) lobby with no pinned host belongs to the server, so no " <>
        "player may move it. Targets the caller's own lobby unless lobby_id " <>
        "names another - which is how a pinned WebRTC host, seated in no lobby, " <>
        "moves the room it runs. The vocabulary is the game's (core documents " <>
        "created, starting, playing, ended); the game's before_lobby_state_change " <>
        "hook enforces its own words and ordering.",
    security: [%{"authorization" => []}],
    request_body: {
      "Target state",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          state: %Schema{type: :string, description: "Target lifecycle state"},
          lobby_id: %Schema{
            type: :string,
            description: "Lobby to move. Defaults to the caller's own lobby."
          }
        },
        required: [:state]
      }
    },
    responses: %{
      200 => {"Updated lobby", "application/json", %Schema{type: :object}},
      400 =>
        {"Not in a lobby / missing state / malformed id", "application/json",
         %Schema{type: :object}},
      403 => {"No authority over the lobby", "application/json", %Schema{type: :object}},
      404 => {"Not found", "application/json", %Schema{type: :object}},
      422 => {"Unknown state or hook rejection", "application/json", %Schema{type: :object}}
    }
  )

  def set_state(conn, %{"state" => state} = params) when is_binary(state) do
    with_target_lobby(conn, params, fn user, lobby ->
      case Lobbies.transition_state_by_host(user, lobby, state) do
        {:ok, updated} ->
          json(conn, serialize_lobby(updated))

        {:error, :not_host} ->
          conn |> put_status(:forbidden) |> json(%{error: "not_host"})

        {:error, :invalid_state} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_state"})

        {:error, {:hook_rejected, reason}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "rejected", reason: inspect(reason)})

        _other ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
      end
    end)
  end

  def set_state(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "state_required"})
  end

  operation(:update,
    operation_id: "update_lobby",
    summary: "Update lobby (host or pinned WebRTC host)",
    description:
      "Update a lobby's settings. Allowed for the host of a host-managed lobby and for " <>
        "the lobby's pinned WebRTC host; a hostless (matchmaking) lobby with no pinned " <>
        "host belongs to the server, so no player may edit it (both cases return 403). " <>
        "Targets the caller's own lobby unless lobby_id names another - which is how a " <>
        "pinned WebRTC host, seated in no lobby, edits the room it runs. Admins can still " <>
        "modify any lobby from the admin console or the admin API - those changes are " <>
        "broadcast to viewers.",
    security: [%{"authorization" => []}],
    request_body: {
      "Lobby update parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          lobby_id: %Schema{
            type: :string,
            description: "Lobby to update. Defaults to the caller's own lobby."
          },
          title: %Schema{type: :string, description: "New display title"},
          max_users: %Schema{type: :integer, description: "New maximum users"},
          is_hidden: %Schema{type: :boolean, description: "Hide from public listings"},
          is_locked: %Schema{type: :boolean, description: "Lock the lobby"},
          password: %Schema{type: :string, description: "New password (empty string to clear)"},
          metadata: %Schema{type: :object, description: "New metadata"},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        },
        example: %{
          title: "Updated Lobby Name",
          max_users: 6,
          is_locked: true
        }
      }
    },
    responses: [
      ok: {"Lobby updated", "application/json", @lobby_schema},
      bad_request:
        {"Not in a lobby, or malformed id", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      forbidden:
        {"No authority over the lobby", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:join,
    operation_id: "join_lobby",
    summary: "Join a lobby",
    description:
      "Join an existing lobby. If the lobby requires a password, include it in the request body.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Lobby ID",
        required: true
      ]
    ],
    request_body: {
      "Join parameters (optional)",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          password: %Schema{type: :string, description: "Lobby password if required"}
        },
        example: %{password: "secret123"}
      }
    },
    responses: [
      ok: {"Successfully joined", "application/json", %Schema{type: :object}},
      forbidden:
        {"Cannot join (locked, full, wrong password, etc)", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:leave,
    operation_id: "leave_lobby",
    summary: "Leave the current lobby",
    description: "Leave the lobby you are currently in.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", %Schema{type: :object}},
      bad_request:
        {"Not in a lobby", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:disband,
    operation_id: "disband_lobby",
    summary: "Disband the current lobby (host only)",
    description:
      "Delete the lobby for everyone. Distinct from leaving: leaving hands the lobby to the next " <>
        "member, so ending it outright is its own act and only the host may do it. A hostless " <>
        "(matchmaking) lobby has no host to authorise it and is refused.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Success", "application/json", %Schema{type: :object}},
      bad_request:
        {"Not in a lobby", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      forbidden:
        {"Not the lobby host", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:kick,
    operation_id: "kick_user",
    summary: "Kick a user from the lobby (host only)",
    description:
      "Remove a user from the lobby. Only the host can kick users via the API (returns 403 if not host).",
    security: [%{"authorization" => []}],
    request_body: {
      "Kick parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          target_user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "ID of the user to kick"
          }
        },
        required: [:target_user_id],
        example: %{target_user_id: "0198c0de-0002-7000-8000-000000000002"}
      }
    },
    responses: [
      ok: {"User kicked", "application/json", %Schema{type: :object}},
      forbidden:
        {"Not the host or cannot kick this user", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:quick_join,
    operation_id: "quick_join",
    summary: "Quick-join or create a lobby",
    description:
      "Attempt to find an open, non-passworded lobby that matches the provided criteria and join it; if none found, create a new lobby. The authenticated user will become the host when a lobby is created.",
    security: [%{"authorization" => []}],
    request_body: {
      "Quick join parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string, description: "Optional title for a newly created lobby"},
          max_users: %Schema{
            type: :integer,
            description: "Optional maximum users to match/create"
          },
          metadata: %Schema{
            type: :object,
            description: "Optional metadata to match (substring match)"
          }
        }
      }
    },
    responses: [
      ok: {"Lobby joined or created", "application/json", @lobby_schema},
      conflict:
        {"User already in a lobby", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      unauthorized:
        {"Not authenticated", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  operation(:stats,
    operation_id: "lobby_stats",
    summary: "Lobby counts",
    description:
      "Aggregate lobby counts, including spectators. Public, and cached — treat the numbers as up to a minute old.",
    responses: [
      ok:
        GamendWeb.ApiStatsSchema.response("Lobby stats", [
          :lobbies_total,
          :spectators,
          {:by_state,
           %OpenApiSpex.Schema{
             type: :object,
             description: "Lobby count per game-defined lifecycle state.",
             additionalProperties: %OpenApiSpex.Schema{type: :integer}
           }}
        ])
    ]
  )

  def stats(conn, _params), do: json(conn, %{data: Lobbies.stats()})

  def index(conn, params) do
    params = params || %{}

    filters =
      %{}
      |> maybe_put_string_filter(:title, param_value(params, "title", :title))
      |> maybe_put_bool_filter(
        :is_passworded,
        param_value(params, "is_passworded", :is_passworded)
      )
      |> maybe_put_bool_filter(:is_locked, param_value(params, "is_locked", :is_locked))
      |> maybe_put_int_filter(:min_users, param_value(params, "min_users", :min_users))
      |> maybe_put_int_filter(:max_users, param_value(params, "max_users", :max_users))
      |> maybe_put_string_filter(
        :metadata_key,
        param_value(params, "metadata_key", :metadata_key)
      )
      |> maybe_put_string_filter(
        :metadata_value,
        param_value(params, "metadata_value", :metadata_value)
      )

    {page, page_size} = GamendWeb.Pagination.params(params)

    lobbies = Lobbies.list_lobbies(filters, page: page, page_size: page_size)
    serialized = Enum.map(lobbies, &serialize_lobby/1)
    count = length(serialized)

    total_count = Lobbies.count_list_lobbies(filters)

    json(conn, %{
      data: serialized,
      meta: GamendWeb.Pagination.meta(page, page_size, count, total_count)
    })
  end

  defp serialize_lobby(lobby) do
    Serializers.serialize_lobby(lobby, include_passworded: true, include_slowdown: true)
  end

  operation(:show,
    operation_id: "get_lobby",
    summary: "Get a single lobby",
    description:
      "Return details for a single lobby. Non-hidden lobbies can be viewed by anyone. Also returns the current member list.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Lobby ID",
        required: true
      ]
    ],
    responses: [
      ok:
        {"Lobby details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: @lobby_schema,
             spectator_count: %Schema{type: :integer, description: "Number of current spectators"},
             members: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   username: %Schema{type: :string},
                   display_name: %Schema{type: :string},
                   profile_url: %Schema{type: :string},
                   metadata: %Schema{
                     type: :object,
                     description: "User metadata (accessories, hat, color, etc.)"
                   },
                   is_online: %Schema{type: :boolean},
                   last_seen_at: %Schema{type: :string, format: "date-time"}
                 }
               }
             }
           }
         }},
      bad_request:
        {"Malformed id", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  def show(conn, %{"id" => id_str}) do
    with {:ok, lobby_id} <- Ecto.UUID.cast(id_str),
         %Gamend.Lobbies.Lobby{} = lobby <- Lobbies.get_lobby(lobby_id),
         true <- Lobbies.can_view_lobby?(Scope.user(conn.assigns[:current_scope]), lobby) do
      members =
        Lobbies.get_lobby_members(lobby)
        |> Enum.map(&User.serialize_brief/1)

      json(conn, %{
        data: serialize_lobby(lobby),
        members: members,
        spectator_count: SpectatorTracker.count(lobby.id)
      })
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid lobby id"})

      # 404 rather than 403 for a hidden lobby the caller is not in: a 403
      # confirms it exists, which is the thing hiding it is meant to conceal.
      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Lobby not found"})
    end
  end

  ### API actions (create/join/update/leave/kick) ###

  def create(conn, params) do
    # disallow hostless creation from public API
    if Map.get(params, "hostless") == true or Map.get(params, :hostless) == true do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    else
      case Scope.user(conn.assigns[:current_scope]) do
        %User{} = user ->
          user = Gamend.Accounts.get_user(user.id)

          cond do
            # Non-leader party members must leave the party first
            user.party_id != nil and not Parties.can_manage_party?(user, user.party_id) ->
              conn |> put_status(:forbidden) |> json(%{error: "in_party"})

            # Party leader: automatically bring the whole party
            user.party_id != nil and Parties.can_manage_party?(user, user.party_id) ->
              create_lobby_as_party_leader(conn, user, params)

            # Not in a party: normal create flow
            true ->
              create_lobby_solo(conn, user, params)
          end

        _ ->
          conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
      end
    end
  end

  defp create_lobby_as_party_leader(conn, user, params) do
    case Parties.create_lobby_with_party(user, params) do
      {:ok, lobby} ->
        conn
        |> put_status(:created)
        |> json(serialize_lobby(lobby))

      {:error, :member_in_lobby} ->
        conn |> put_status(:conflict) |> json(%{error: "member_in_lobby"})

      {:error, :not_enough_space} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_enough_space"})

      {:error, :member_offline} ->
        conn |> put_status(:forbidden) |> json(%{error: "member_offline"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "blocked"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)})

      _other ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unexpected_error"})
    end
  end

  defp create_lobby_solo(conn, user, params) do
    attrs = Map.put(params, "host_id", user.id)

    case Lobbies.create_lobby(attrs) do
      {:ok, lobby} ->
        conn
        |> put_status(:created)
        |> json(serialize_lobby(lobby))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        })

      _other ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unexpected_error"})
    end
  end

  def join(conn, %{"id" => id} = params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        user = Gamend.Accounts.get_user(user.id)
        password = Map.get(params, "password") || Map.get(params, :password)

        case Ecto.UUID.cast(to_string(id)) do
          {:ok, lobby_id} ->
            cond do
              # Non-leader party members cannot join a lobby individually
              user.party_id != nil and not Parties.can_manage_party?(user, user.party_id) ->
                conn |> put_status(:forbidden) |> json(%{error: "in_party"})

              # Party leader: bring the whole party
              user.party_id != nil and Parties.can_manage_party?(user, user.party_id) ->
                join_lobby_as_party_leader(conn, user, lobby_id, params)

              # Not in a party: normal join
              true ->
                join_lobby_solo(conn, user, lobby_id, %{password: password})
            end

          _ ->
            conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp join_lobby_as_party_leader(conn, user, lobby_id, params) do
    password = Map.get(params, "password") || Map.get(params, :password)
    opts = if password, do: %{password: password}, else: %{}

    case Parties.join_lobby_with_party(user, lobby_id, opts) do
      {:ok, lobby} ->
        json(conn, serialize_lobby(lobby))

      {:error, :invalid_lobby} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :locked} ->
        conn |> put_status(:forbidden) |> json(%{error: "locked"})

      {:error, :password_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "password_required"})

      {:error, :invalid_password} ->
        conn |> put_status(:forbidden) |> json(%{error: "invalid_password"})

      {:error, :member_in_lobby} ->
        conn |> put_status(:conflict) |> json(%{error: "member_in_lobby"})

      {:error, :not_enough_space} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_enough_space"})

      {:error, :member_offline} ->
        conn |> put_status(:forbidden) |> json(%{error: "member_offline"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "blocked"})

      {:error, :full} ->
        conn |> put_status(:forbidden) |> json(%{error: "full"})

      {:error, {:hook_rejected, _}} ->
        conn |> put_status(:forbidden) |> json(%{error: "rejected"})

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "cannot_join"})
    end
  end

  defp join_lobby_solo(conn, user, lobby_id, opts) do
    case Lobbies.join_lobby(user, lobby_id, opts) do
      {:ok, _member} ->
        lobby = Lobbies.get_lobby!(lobby_id)
        json(conn, serialize_lobby(lobby))

      {:error, :invalid_lobby} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :already_in_lobby} ->
        conn |> put_status(:forbidden) |> json(%{error: "already_in_lobby"})

      {:error, :password_required} ->
        conn |> put_status(:forbidden) |> json(%{error: "password_required"})

      {:error, :invalid_password} ->
        conn |> put_status(:forbidden) |> json(%{error: "invalid_password"})

      {:error, :locked} ->
        conn |> put_status(:forbidden) |> json(%{error: "locked"})

      {:error, :full} ->
        conn |> put_status(:forbidden) |> json(%{error: "full"})

      {:error, :blocked} ->
        conn |> put_status(:forbidden) |> json(%{error: "blocked"})

      {:error, {:hook_rejected, _}} ->
        conn |> put_status(:forbidden) |> json(%{error: "rejected"})

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "cannot_join"})
    end
  end

  def quick_join(conn, params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        user = Gamend.Accounts.get_user(user.id)

        if user.party_id != nil do
          # Party leader quick-joins with the whole party
          do_party_quick_join(conn, user, params)
        else
          do_quick_join(conn, user, params)
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp do_party_quick_join(conn, user, params) do
    case Gamend.Parties.quick_join_with_party(user, params) do
      {:ok, lobby} ->
        json(conn, serialize_lobby(lobby))

      {:error, :not_leader} ->
        conn |> put_status(:forbidden) |> json(%{error: "not_leader"})

      {:error, :member_in_lobby} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "member_in_lobby"})

      {:error, :members_offline} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "members_offline"})

      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})

      {:error, {:hook_rejected, _}} ->
        conn |> put_status(:forbidden) |> json(%{error: "rejected"})

      _other ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
    end
  end

  defp do_quick_join(conn, user, params) do
    title = Map.get(params, "title") || Map.get(params, :title)
    max_users = Map.get(params, "max_users") || Map.get(params, :max_users)

    # Normalize metadata: allow either a map (from parsed JSON) or a
    # JSON-encoded string. If a client sends the metadata as a string
    # (eg. form submission), try to decode it to a map; otherwise fall
    # back to an empty map.
    metadata_raw = Map.get(params, "metadata") || Map.get(params, :metadata)

    metadata =
      case metadata_raw do
        nil ->
          %{}

        "" ->
          %{}

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        m when is_map(m) ->
          m

        _ ->
          %{}
      end

    case Lobbies.quick_join(user, title, max_users, metadata) do
      {:ok, lobby} ->
        json(conn, serialize_lobby(lobby))

      {:error, :already_in_lobby} ->
        conn |> put_status(:conflict) |> json(%{error: "already_in_lobby"})

      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:forbidden) |> json(%{error: to_string(reason)})

      {:error, {:hook_rejected, _}} ->
        conn |> put_status(:forbidden) |> json(%{error: "rejected"})

      _other ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
    end
  end

  def update(conn, params) do
    with_target_lobby(conn, params, fn user, lobby ->
      case Lobbies.update_lobby_by_host(user, lobby, Map.drop(params, ["lobby_id", :lobby_id])) do
        {:ok, updated} ->
          json(conn, serialize_lobby(updated))

        {:error, :not_host} ->
          conn |> put_status(:forbidden) |> json(%{error: "not_host"})

        {:error, :too_small} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "too_small"})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)})

        _other ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
      end
    end)
  end

  # Which lobby the caller means. Normally the one it is sitting in — but a
  # pinned WebRTC host is seated in no lobby (that is the point of pinning one:
  # a headless server runs the room without occupying a slot), so it names the
  # lobby explicitly instead. `can_view_lobby?` gates the named one: a caller
  # with no relationship to a hidden lobby gets the same 404 as `show/2`, since
  # a 403 would confirm it exists. Authority itself is checked downstream, so
  # the answer to "may I?" comes from one place.
  defp with_target_lobby(conn, params, fun) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        case target_lobby(user, Map.get(params, "lobby_id") || Map.get(params, :lobby_id)) do
          {:ok, lobby} ->
            fun.(user, lobby)

          {:error, :not_in_lobby} ->
            conn |> put_status(:bad_request) |> json(%{error: "not_in_lobby"})

          {:error, :invalid_id} ->
            conn |> put_status(:bad_request) |> json(%{error: "Invalid lobby id"})

          {:error, :not_found} ->
            conn |> put_status(:not_found) |> json(%{error: "Lobby not found"})
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  defp target_lobby(%User{lobby_id: nil}, nil), do: {:error, :not_in_lobby}
  defp target_lobby(%User{lobby_id: lobby_id}, nil), do: {:ok, Lobbies.get_lobby!(lobby_id)}

  defp target_lobby(%User{} = user, raw_id) do
    with {:ok, lobby_id} <- Ecto.UUID.cast(raw_id),
         %Gamend.Lobbies.Lobby{} = lobby <- Lobbies.get_lobby(lobby_id),
         true <- Lobbies.can_view_lobby?(user, lobby) do
      {:ok, lobby}
    else
      :error -> {:error, :invalid_id}
      _ -> {:error, :not_found}
    end
  end

  def kick(conn, %{"target_user_id" => target_user_id}) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        if is_nil(user.lobby_id) do
          conn |> put_status(:bad_request) |> json(%{error: "not_in_lobby"})
        else
          lobby = Lobbies.get_lobby!(user.lobby_id)
          target = Gamend.Accounts.get_user!(target_user_id)

          case Lobbies.kick_user(user, lobby, target) do
            {:ok, _} ->
              json(conn, %{})

            {:error, :not_host} ->
              conn |> put_status(:forbidden) |> json(%{error: "not_host"})

            {:error, :cannot_kick_self} ->
              conn |> put_status(:forbidden) |> json(%{error: "cannot_kick_self"})

            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "not_found"})

            {:error, {:hook_rejected, _}} ->
              conn |> put_status(:forbidden) |> json(%{error: "rejected"})

            _other ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
          end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  def disband(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{lobby_id: lobby_id} = user when is_binary(lobby_id) ->
        do_disband(conn, user, Lobbies.get_lobby(lobby_id))

      %User{} ->
        conn |> put_status(:bad_request) |> json(%{error: "not_in_lobby"})

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end

  # A hostless lobby is server-managed: nobody is its owner, so nobody can end
  # it from the API.
  defp do_disband(conn, _user, %{hostless: true}),
    do: conn |> put_status(:forbidden) |> json(%{error: "not_host"})

  # Who may end a lobby is the context's rule — the same one `kick` and
  # `update` go through. Comparing host_id here was a second copy of it living
  # in the controller.
  defp do_disband(conn, user, %{} = lobby) do
    if Lobbies.can_manage_lobby?(user, lobby) do
      case Lobbies.delete_lobby(lobby) do
        {:ok, _} -> json(conn, %{})
        _ -> conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "not_host"})
    end
  end

  defp do_disband(conn, _user, _lobby),
    do: conn |> put_status(:bad_request) |> json(%{error: "not_in_lobby"})

  def leave(conn, _params) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user ->
        # Use the authenticated user's lobby (ignore path id)
        if is_nil(user.lobby_id) do
          json(conn, %{})
        else
          case Lobbies.leave_lobby(user) do
            {:ok, _} ->
              json(conn, %{})

            {:error, :not_in_lobby} ->
              json(conn, %{})

            {:error, {:hook_rejected, _}} ->
              conn |> put_status(:forbidden) |> json(%{error: "rejected"})

            _other ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: "unexpected_error"})
          end
        end

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Not authenticated"})
    end
  end
end
