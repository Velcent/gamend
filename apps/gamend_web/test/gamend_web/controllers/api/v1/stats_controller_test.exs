defmodule GamendWeb.Api.V1.StatsControllerTest do
  @moduledoc """
  The public `/<resource>/stats` endpoints.

  Two properties matter beyond the numbers: they answer without a token (the
  point is embedding them on a website), and `/users/stats` is not swallowed by
  `/users/:id`, which is declared later and would otherwise treat "stats" as an
  id.
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies

  @paths [
    "/api/v1/users/stats",
    "/api/v1/lobbies/stats",
    "/api/v1/parties/stats",
    "/api/v1/quests/stats",
    "/api/v1/signaling/stats",
    "/api/v1/matchmaking/stats"
  ]

  # Every cache key the stats endpoints read through. Counts are cached, so a
  # snapshot taken by an earlier test would mask the rows this one inserts.
  @stats_cache_keys [
    {:accounts, :player_stats},
    {:accounts, :users_count},
    {:lobbies, :stats},
    {:parties, :stats},
    {:quests, :stats},
    {:signaling, :stats}
  ]

  defp clear_stats_cache do
    Enum.each(@stats_cache_keys, &Gamend.Cache.invalidate/1)
  end

  setup do
    previous = Application.get_env(:gamend_web, GamendWeb.Features)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, GamendWeb.Features, previous),
        else: Application.delete_env(:gamend_web, GamendWeb.Features)

      clear_stats_cache()
    end)

    clear_stats_cache()
    :ok
  end

  defp disable(feature) do
    config = Application.get_env(:gamend_web, GamendWeb.Features, [])
    Application.put_env(:gamend_web, GamendWeb.Features, Keyword.put(config, feature, false))
  end

  describe "access" do
    test "every stats endpoint answers without a token", %{conn: conn} do
      for path <- @paths do
        assert %{"data" => data} = conn |> get(path) |> json_response(200)
        assert is_map(data), "#{path} did not return a data object"
      end
    end

    test "public_stats=false 404s all of them", %{conn: conn} do
      disable(:public_stats)

      for path <- @paths do
        assert conn |> get(path) |> response(404)
      end
    end

    # /users/:id is declared after this route; without the ordering it would
    # match first and try to look up a user with the id "stats".
    test "/users/stats is not captured by /users/:id", %{conn: conn} do
      assert %{"data" => data} = conn |> get("/api/v1/users/stats") |> json_response(200)
      assert Map.has_key?(data, "players_total")
    end

    # The flag closes the browser page with the API, so turning stats off does
    # not leave a second way to read the same numbers.
    test "the /stats page follows the same flag", %{conn: conn} do
      assert conn |> get("/stats") |> html_response(200) =~ "Server stats"

      disable(:public_stats)

      assert_raise GamendWeb.NotFoundError, fn -> get(conn, "/stats") end
    end
  end

  describe "player counts" do
    test "reflect registered and online users", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      _ = Accounts.set_user_online(user.id)
      clear_stats_cache()

      assert %{"data" => data} = conn |> get("/api/v1/users/stats") |> json_response(200)

      assert data["players_total"] >= 1
      assert data["players_online"] >= 1
      assert data["players_offline"] == data["players_total"] - data["players_online"]
    end

    test "count a user seated in a lobby", %{conn: conn} do
      host = AccountsFixtures.user_fixture()
      # create_lobby seats the host, so this is a member without a join.
      {:ok, _lobby} = Lobbies.create_lobby(%{"title" => "Stats", "host_id" => host.id})
      clear_stats_cache()

      assert %{"data" => data} = conn |> get("/api/v1/users/stats") |> json_response(200)
      assert data["players_in_lobbies"] >= 1
    end
  end

  describe "lobby counts" do
    test "group lobbies by their game-defined state", %{conn: conn} do
      host = AccountsFixtures.user_fixture()
      {:ok, _lobby} = Lobbies.create_lobby(%{"title" => "Stats", "host_id" => host.id})
      clear_stats_cache()

      assert %{"data" => data} = conn |> get("/api/v1/lobbies/stats") |> json_response(200)

      assert data["lobbies_total"] >= 1
      assert is_map(data["by_state"])
      assert data["spectators"] >= 0
    end
  end
end
