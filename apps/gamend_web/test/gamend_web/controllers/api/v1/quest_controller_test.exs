defmodule GamendWeb.Api.V1.QuestControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.AccountsFixtures
  alias Gamend.Quests
  alias GamendWeb.Auth.Guardian

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp create_quest(attrs) do
    defaults = %{
      key: "quest_#{System.unique_integer([:positive])}",
      title: "Test Quest",
      objectives: [%{event: "test_event", target: 1}]
    }

    {:ok, quest} = Quests.create_quest(Map.merge(defaults, attrs))
    quest
  end

  describe "GET /api/v1/me/quests category filter" do
    setup do
      daily = create_quest(%{category: "daily", reset: "daily"})
      achievement = create_quest(%{category: "achievement"})
      %{daily: daily, achievement: achievement, user: AccountsFixtures.user_fixture()}
    end

    test "an empty category lists every category, not none", ctx do
      # `?category=` is what a client asking for ALL quests sends: the generated
      # SDKs always include the param and default it to "". Treating that as a
      # literal category matched nothing and returned an empty list.
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests", %{category: "", page: 1, page_size: 100})
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      assert ctx.achievement.key in keys
      assert resp["meta"]["total_count"] == length(keys)
    end

    test "an omitted category lists every category", ctx do
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests")
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      assert ctx.achievement.key in keys
    end

    test "a named category still filters", ctx do
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests", %{category: "daily"})
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      refute ctx.achievement.key in keys
    end
  end
end
