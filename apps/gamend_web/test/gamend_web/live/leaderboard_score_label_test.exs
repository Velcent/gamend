defmodule GamendWeb.LeaderboardScoreLabelTest do
  @moduledoc """
  A board can name its own score column.

  The generic pair is "Rank" and "Score", which on a board counting kilometres
  printed a bare `500` next to a column literally called Rank — three senses of
  the same word on one screen. `metadata["score_label"]` and
  `metadata["score_unit"]` let the board say what it counts.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Leaderboards

  setup :register_and_log_in_user

  defp board!(metadata) do
    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        slug: "labelled_#{System.unique_integer([:positive])}",
        title: "Distance Sailed",
        description: "Kilometres sailed",
        sort_order: :desc,
        operator: :set,
        metadata: metadata
      })

    board
  end

  defp visible_text(html), do: String.replace(html, ~r/<[^>]*>/, " ")

  test "a board with a unit renders it beside every score", %{conn: conn, user: user} do
    board = board!(%{"score_label" => "Distance", "score_unit" => "km"})
    {:ok, _record} = Leaderboards.submit_score(board.id, user.id, 12_500)

    # Slug-only URL: an active board redirects the `/slug/:id` form to it.
    {:ok, _view, html} = live(conn, ~p"/leaderboards/#{board.slug}")

    # The reader's own card and the table cell both carry it, and the column is
    # headed by the board's own word.
    assert html =~ "Distance"
    assert html =~ "12,500 km"
    refute html =~ ">Score<"
  end

  test "a board without metadata keeps the generic column", %{conn: conn, user: user} do
    board = board!(%{})
    {:ok, _record} = Leaderboards.submit_score(board.id, user.id, 7)

    {:ok, _view, html} = live(conn, ~p"/leaderboards/#{board.slug}")

    assert html =~ "Score"
    # The score is there, and bare: no unit was declared, so none is invented.
    assert visible_text(html) =~ "7"
    refute html =~ "7 km"
  end
end
