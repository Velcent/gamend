defmodule GamendWeb.Components.PresentationPageFullLayoutTest do
  @moduledoc """
  `"media_layout": "full"` stacks a section — full-width media, centered text.
  Hosts use it for wide 16:9 art that a side-by-side square box would crush.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  defp render_section(section) do
    render_component(&PresentationPage.section/1, section: section)
  end

  test "full layout stacks and centers instead of the side-by-side grid" do
    html =
      render_section(%{
        "title" => "Three Games",
        "text" => "One vocabulary.",
        "media_layout" => "full",
        "image" => %{"light" => "/images/sections/word-match.png"}
      })

    assert html =~ "flex w-full flex-col"
    assert html =~ "text-center"
    refute html =~ "md:grid-cols", "must not use the two-column grid"
  end

  test "full-layout image keeps its shape — no square box, wider cap" do
    html =
      render_section(%{
        "title" => "T",
        "media_layout" => "full",
        "image" => %{"light" => "/images/sections/word-match.png"}
      })

    refute html =~ "aspect-square"
    assert html =~ "max-h-[70dvh]"
  end

  test "text-only full section renders no media wrapper" do
    html = render_section(%{"title" => "T", "text" => "words", "media_layout" => "full"})

    refute html =~ "<img"
    refute html =~ "<video"
    assert html =~ "words"
  end

  test "icon-only full section still shows the icon" do
    html =
      render_section(%{"title" => "T", "media_layout" => "full", "icon" => "hero-play-solid"})

    assert html =~ "hero-play-solid"
  end

  test "buttons render centered in full layout" do
    html =
      render_section(%{
        "title" => "T",
        "media_layout" => "full",
        "buttons" => [%{"label" => "iOS", "href" => "/ios"}]
      })

    assert html =~ "iOS"
  end

  test "sections without media_layout keep the grid layout" do
    html =
      render_section(%{
        "title" => "T",
        "image" => %{"light" => "/images/sections/word-match.png"}
      })

    assert html =~ "md:grid-cols"
    assert html =~ "aspect-square"
  end
end
