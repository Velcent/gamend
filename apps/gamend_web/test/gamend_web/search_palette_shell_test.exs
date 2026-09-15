defmodule GamendWeb.SearchPaletteShellTest do
  @moduledoc """
  The palette's markup in the page.

  Three things it must get right, each of which has a way of going wrong that
  nothing else would catch:

    * exactly one dialog. It is rendered outside both navs for a reason, and
      a second copy would give two elements the same id and the JS the wrong
      one.
    * `phx-update="ignore"`. Without it morphdom re-sends the layout on every
      LiveView diff, and an open dialog has no `open` attribute in that
      markup — the palette would shut itself on any page with a ticking clock.
    * nothing at all when search is off.
  """
  use GamendWeb.ConnCase, async: false

  setup context do
    previous = Application.get_env(:gamend_web, :search_provider)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:gamend_web, :search_provider)
      else
        Application.put_env(:gamend_web, :search_provider, previous)
      end
    end)

    if Map.has_key?(context, :provider) do
      Application.put_env(:gamend_web, :search_provider, context.provider)
    end

    :ok
  end

  defp count(html, pattern), do: length(Regex.scan(pattern, html))

  test "the button and the dialog each appear exactly once", %{conn: conn} do
    html = conn |> get("/privacy") |> html_response(200)

    assert count(html, ~r/data-gamend-search-open/) == 1
    assert count(html, ~r/id="gamend-search"/) == 1
    assert count(html, ~r/data-gamend-search-input/) == 1
  end

  test "the dialog is exempt from LiveView patching and knows where its index is", %{conn: conn} do
    html = conn |> get("/privacy") |> html_response(200)

    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-index-url="/search/index.json?locale=en")
  end

  test "the dialog sits outside the header, where a hidden navbar cannot swallow it", %{
    conn: conn
  } do
    html = conn |> get("/privacy") |> html_response(200)

    [_before, after_header] = String.split(html, "</header>", parts: 2)

    assert after_header =~ ~s(id="gamend-search")
  end

  test "the index URL carries the locale of the page", %{conn: conn} do
    html = conn |> get("/de/privacy") |> html_response(200)

    assert html =~ ~s(data-index-url="/search/index.json?locale=de")
  end

  @tag provider: false
  test "turning search off removes the button and the dialog", %{conn: conn} do
    html = conn |> get("/privacy") |> html_response(200)

    refute html =~ "data-gamend-search-open"
    refute html =~ ~s(id="gamend-search")
  end
end
