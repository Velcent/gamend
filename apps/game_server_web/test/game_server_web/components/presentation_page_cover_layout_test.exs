defmodule GameServerWeb.Components.PresentationPageCoverLayoutTest do
  @moduledoc """
  `"media_layout": "cover"` puts the image behind the section (object-cover +
  scrim) with the text overlaid — the banner style hosts use for full-bleed
  section art and blog covers.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServerWeb.PresentationPage

  defp render_section(section) do
    render_component(&PresentationPage.section/1, section: section)
  end

  test "the image covers the section instead of sitting beside the text" do
    html =
      render_section(%{
        "title" => "Three Games",
        "text" => "One vocabulary.",
        "media_layout" => "cover",
        "image" => %{"light" => "/images/sections/word-match.png"}
      })

    assert html =~ "object-cover"
    assert html =~ "absolute inset-0"
    refute html =~ "md:grid-cols"
    refute html =~ "object-contain"
  end

  test "text is overlaid, centered and readable over the art" do
    html =
      render_section(%{
        "title" => "T",
        "text" => "words",
        "media_layout" => "cover",
        "image" => %{"light" => "/x.png"}
      })

    assert html =~ "bg-gradient-to-t", "needs a scrim or the text drowns in the art"
    assert html =~ "text-center"
    assert html =~ "text-white"
    assert html =~ "relative z-10", "text must sit above the cover image"
  end

  test "height key still applies, so cover + full gives a viewport banner" do
    html =
      render_section(%{
        "title" => "T",
        "media_layout" => "cover",
        "height" => "full",
        "image" => %{"light" => "/x.png"}
      })

    assert html =~ "min-h-[calc(100svh-5rem)]"
  end

  test "buttons and icon render inside the overlay" do
    html =
      render_section(%{
        "title" => "T",
        "media_layout" => "cover",
        "icon" => "hero-play-solid",
        "image" => %{"light" => "/x.png"},
        "buttons" => [%{"label" => "Read", "href" => "/blog/x"}]
      })

    assert html =~ "Read"
    assert html =~ "hero-play-solid"
  end

  test "dark variant swaps by theme like ordinary sections" do
    html =
      render_section(%{
        "title" => "T",
        "media_layout" => "cover",
        "image" => %{"light" => "/l.png", "dark" => "/d.png"}
      })

    assert html =~ "/l.png"
    assert html =~ "/d.png"
    assert html =~ "[[data-theme=dark]_&]:block"
  end
end
