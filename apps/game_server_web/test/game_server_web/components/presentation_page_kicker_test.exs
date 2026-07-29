defmodule GameServerWeb.Components.PresentationPageKickerTest do
  @moduledoc """
  The hero `"kicker"` is the one line that tells a first-time visitor what the
  product is ("Strategy Card Game • Free to Play" style). It comes straight
  from theme JSON, so it must render as text and never as markup.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServerWeb.PresentationPage

  defp render_page(hero) do
    render_component(&PresentationPage.page/1,
      page: %{"path" => "/", "hero" => hero, "sections" => []},
      background_icons: []
    )
  end

  test "a kicker renders under the hero title" do
    html = render_page(%{"title" => "Polyglot Pirates", "kicker" => "Co-op • Free"})

    assert html =~ "Co-op • Free"
  end

  test "no kicker, no extra element" do
    html = render_page(%{"title" => "Polyglot Pirates"})

    refute html =~ "tracking-widest"
  end

  test "an empty kicker is treated as absent" do
    html = render_page(%{"title" => "Polyglot Pirates", "kicker" => ""})

    refute html =~ "tracking-widest"
  end

  test "markup in the kicker is escaped, not rendered" do
    html = render_page(%{"title" => "T", "kicker" => "<b>free</b>"})

    refute html =~ "<b>free</b>"
    assert html =~ "&lt;b&gt;free&lt;/b&gt;"
  end
end
