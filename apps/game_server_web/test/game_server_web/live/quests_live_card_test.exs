defmodule GameServerWeb.QuestsLiveCardTest do
  @moduledoc """
  The quest list is a grid of clickable cards, so it has to read like the
  leaderboard and tournament grids rather than as its own dialect.
  """

  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GameServer.Quests

  setup do
    for attrs <- [
          %{
            key: "card_daily",
            title: "Daily check-in",
            description: "Log in today.",
            category: "Daily",
            reset: "daily",
            icon_url: "/icons/calendar-days.svg",
            objectives: [%{event: "login", target: 1}]
          },
          %{
            key: "card_weekly",
            title: "Weekly regular",
            description: "Log in on five days.",
            category: "Achievements",
            reset: "weekly",
            icon_url: "/icons/calendar.svg",
            objectives: [%{event: "login", target: 5}]
          },
          %{
            key: "card_locked",
            title: "Loyal veteran",
            description: "Log in fifty times.",
            category: "Chained",
            reset: "never",
            prerequisite_quest_key: "card_daily",
            icon_url: "/icons/shield-check.svg",
            objectives: [%{event: "login", target: 50}]
          }
        ] do
      {:ok, _} = Quests.create_quest(attrs)
    end

    :ok
  end

  defp page(conn) do
    {:ok, _view, html} = live(conn, ~p"/quests")
    html
  end

  test "the icon sits in the title, with no boxed-off tile around it", %{conn: conn} do
    html = page(conn)

    assert html =~ ~s(class="card-title text-lg")

    refute html =~ "w-12 h-12 rounded-lg",
           "the icon tile is gone; the icon reads like the other grids"
  end

  test "title and description use the same sizes as the other grids", %{conn: conn} do
    html = page(conn)

    assert html =~ "card-title text-lg"
    assert html =~ "text-sm text-base-content/70 line-clamp-2"
  end

  test "a signed-out visitor gets no per-viewer status badge", %{conn: conn} do
    refute page(conn) =~ "Not started",
           "progress belongs to a viewer; seven cards reading Not started is noise"
  end

  test "a signed-in player does get one", %{conn: conn} do
    conn = log_in_user(conn, GameServer.AccountsFixtures.user_fixture())
    html = page(conn)

    assert html =~ "Daily check-in", "the signed-in user should still see the quests"
    IO.puts("DBG-AFTER " <> (html |> String.split("Daily check-in") |> Enum.at(1) |> String.slice(0, 500)))
    assert html =~ "Not started"
    assert html =~ "badge-neutral" or html =~ "badge-success"
  end

  test "the cadence badge is dropped when it just repeats the category", %{conn: conn} do
    html = page(conn)

    # "Daily check-in" is category Daily *and* reset daily — one badge, not two.
    daily_card =
      html
      |> String.split("Daily check-in")
      |> Enum.at(1, "")
      |> String.slice(0, 900)

    assert String.contains?(daily_card, "Daily"), "the category badge should still be there"

    refute Regex.scan(~r/>\s*Daily\s*</, daily_card) |> length() > 1,
           "Daily is shown twice on the same card"
  end

  test "the cadence badge stays when it differs from the category", %{conn: conn} do
    html = page(conn)
    weekly = html |> String.split("Weekly regular") |> Enum.at(1, "") |> String.slice(0, 900)

    assert String.contains?(weekly, "Achievements")
    assert String.contains?(weekly, "Weekly")
  end

  test "a category with nothing visible behind it gets no tab", %{conn: conn} do
    html = page(conn)

    assert html =~ "Daily"
    assert html =~ "Achievements"

    refute html =~ ~r/>\s*Chained\s*</,
           "the chained tier is locked, so its tab would open onto nothing"
  end
end
