defmodule GamendWeb.Api.V1.UserController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias GamendWeb.Features
  alias GamendWeb.Pagination
  alias OpenApiSpex.Schema

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  tags(["Users"])

  operation(:index,
    operation_id: "search_users",
    summary: "Search users by id, username, or display_name",
    parameters: [
      q: [in: :query, schema: %Schema{type: :string}],
      page: [in: :query, schema: %Schema{type: :integer}],
      page_size: [in: :query, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok:
        {"Users (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   username: %Schema{type: :string},
                   display_name: %Schema{type: :string},
                   metadata: %Schema{
                     type: :object,
                     description:
                       "User metadata, restricted to the keys named by the :public_user_metadata_keys setting. Empty by default."
                   },
                   lobby_id: %Schema{
                     type: :string,
                     format: :uuid,
                     nullable: false,
                     description:
                       "Lobby ID when user is currently in a lobby. -1 means not currently in a lobby."
                   },
                   party_id: %Schema{
                     type: :string,
                     format: :uuid,
                     nullable: false,
                     description:
                       "Party ID when user is currently in a party. -1 means not currently in a party."
                   },
                   is_online: %Schema{type: :boolean},
                   last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
                 }
               }
             },
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

  operation(:show,
    operation_id: "get_user",
    summary: "Get a user by id",
    parameters: [id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]],
    responses: [
      ok:
        {"User", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             username: %Schema{type: :string},
             display_name: %Schema{type: :string},
             metadata: %Schema{
               type: :object,
               description:
                 "User metadata, restricted to the keys named by the :public_user_metadata_keys setting. Empty by default."
             },
             lobby_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: false,
               description:
                 "Lobby ID when user is currently in a lobby. -1 means not currently in a lobby."
             },
             party_id: %Schema{
               type: :string,
               format: :uuid,
               nullable: false,
               description:
                 "Party ID when user is currently in a party. -1 means not currently in a party."
             },
             is_online: %Schema{type: :boolean},
             last_seen_at: %Schema{type: :string, format: :date_time, nullable: false}
           }
         }},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  operation(:stats,
    operation_id: "user_stats",
    summary: "Player counts",
    description:
      "Aggregate player counts. Public, and cached — treat the numbers as up to a minute old.",
    responses: [
      ok:
        GamendWeb.ApiStatsSchema.response("Player stats", [
          :players_online,
          :players_total,
          :players_offline,
          :players_in_lobbies,
          :players_in_parties
        ])
    ]
  )

  def stats(conn, _params), do: json(conn, %{data: Accounts.player_stats()})

  def index(conn, params) do
    q = Map.get(params, "q", "")
    {page, page_size} = Pagination.params(params)

    users = if q == "", do: [], else: Accounts.search_users(q, page: page, page_size: page_size)
    serialized = Enum.map(users, &serialize_user/1)

    total_count = if q == "", do: 0, else: Accounts.count_search_users(q)

    json(conn, Pagination.envelope(serialized, page, page_size, total_count))
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

      user_id ->
        case Accounts.get_user(user_id) do
          %{} = user -> json(conn, serialize_user(user))
          nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end
    end
  end

  # `serialize_brief/1` is built for party, lobby and friend member lists, where
  # the caller is already in the room with the user. These two endpoints are
  # public and unauthenticated, so handing back the same payload gives a
  # name-prefix search the whole game-defined metadata map. For a game that
  # keeps position, destination or study state in there, that is a stranger
  # tracking a named player with no account.
  #
  # Metadata is therefore default-deny here, and a host opts individual
  # sections back in through :public_user_metadata_keys.
  # `profile_url` goes with the metadata, for the same reason and one of its
  # own: it is set from an upload *or* imported verbatim from a Google, Discord,
  # Steam or Facebook profile, which means it is frequently a photograph of the
  # account holder. Handing that out from an unauthenticated endpoint, keyed to
  # a name prefix, is the picture and the name together.
  defp serialize_user(user) do
    user
    |> User.serialize_brief()
    |> Map.drop([:profile_url])
    |> Map.put(:metadata, public_metadata(user.metadata))
    |> Map.merge(%{
      # Deliberately blank on the public endpoints. These are unauthenticated
      # (`list_users` gate only), and a lobby id is enough to join a lobby or
      # walk into a WebRTC signaling room — so publishing "which room is this
      # player in" alongside a name search was the discovery half of several
      # other problems. Authenticated callers get membership from the lobby,
      # party and channel APIs, which check the caller's relationship to it.
      lobby_id: "",
      party_id: ""
    })
  end

  defp public_metadata(metadata) when is_map(metadata) do
    case Features.public_user_metadata_keys() do
      [] -> %{}
      keys -> Map.take(metadata, keys)
    end
  end

  defp public_metadata(_metadata), do: %{}
end
