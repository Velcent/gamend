defmodule GamendWeb.Components.PaginationTest do
  @moduledoc """
  `pagination/1` renders nothing for a list that fits on one page — a disabled
  Prev, a "1 / 1" counter and a disabled Next appeared under every short list
  in the app (14 quests, 3 groups, an empty admin table).

  The size selector is the one part that can outlive a single page: raising the
  size until everything fits would otherwise hide the only control that puts it
  back.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @base [page: 1, on_prev: "prev_page", on_next: "next_page"]

  defp bar(opts), do: render_component(&GamendWeb.CoreComponents.pagination/1, @base ++ opts)

  test "one page with a selector that cannot split it renders nothing" do
    html =
      bar(
        total_pages: 1,
        total_count: 14,
        page_size: 24,
        page_sizes: [24, 50, 100, 200],
        on_page_size: "page_size"
      )

    assert String.trim(html) == ""
  end

  test "an empty list renders nothing" do
    html = bar(total_pages: 0, total_count: 0, page_size: 25, on_page_size: "page_size")

    assert String.trim(html) == ""
  end

  test "one page without a size selector renders nothing" do
    assert String.trim(bar(total_pages: 1, total_count: 3)) == ""
  end

  test "several pages render the full bar" do
    html =
      bar(total_pages: 2, total_count: 40, page_size: 25, on_page_size: "page_size")

    assert html =~ "Prev"
    assert html =~ "Next"
    assert html =~ "1 / 2 (40)"
    assert html =~ "<select"
  end

  test "extra values ride along on both buttons and the size form" do
    html =
      bar(
        total_pages: 3,
        total_count: 70,
        page_size: 25,
        on_page_size: "page_size",
        value: %{"section" => "purchases"}
      )

    assert html |> String.split("phx-value-section=\"purchases\"") |> length() == 3
    assert html =~ ~s(<input type="hidden" name="section" value="purchases")
  end

  test "one page only because the size was raised keeps the selector, not the buttons" do
    html =
      bar(
        total_pages: 1,
        total_count: 150,
        page_size: 200,
        page_sizes: [25, 50, 100, 200],
        on_page_size: "page_size"
      )

    refute html =~ "Prev"
    refute html =~ "Next"
    assert html =~ "<select"
  end
end
