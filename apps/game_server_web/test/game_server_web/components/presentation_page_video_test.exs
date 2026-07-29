defmodule GameServerWeb.Components.PresentationPageVideoTest do
  @moduledoc """
  Host presentation pages are driven entirely by theme JSON, and `rich_text/1`
  HTML-escapes, so `"video"` is the only way a host can put a `<video>` on a
  hero or section. These tests pin the behaviour that is invisible in the
  rendered page but expensive to get wrong.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServerWeb.PresentationPage

  defp render_media(item, variant \\ "hero") do
    render_component(&PresentationPage.media/1, item: item, variant: variant)
  end

  test "a video item renders a <video> in place of the image" do
    html = render_media(%{"video" => %{"src" => "/video/teaser.mp4"}})

    assert html =~ "<video"
    assert html =~ "/video/teaser.mp4"
  end

  test "the player is muted, user-started, and inline on iOS" do
    html = render_media(%{"video" => %{"src" => "/video/teaser.mp4"}})

    assert html =~ "muted", "must start silent"
    assert html =~ "controls", "the user needs a way to start it"
    assert html =~ "playsinline", "without this iOS Safari forces fullscreen on play"

    refute html =~ "autoplay", "the trailer must not start on its own"
  end

  test "preload defaults to metadata and only accepts the three HTML values" do
    assert render_media(%{"video" => %{"src" => "/v.mp4"}}) =~ ~s(preload="metadata")

    assert render_media(%{"video" => %{"src" => "/v.mp4", "preload" => "none"}}) =~
             ~s(preload="none")

    assert render_media(%{"video" => %{"src" => "/v.mp4", "preload" => "auto"}}) =~
             ~s(preload="auto")

    # A typo in theme JSON must not reach the attribute verbatim.
    assert render_media(%{"video" => %{"src" => "/v.mp4", "preload" => "sure"}}) =~
             ~s(preload="metadata")
  end

  test "muted can be turned off explicitly but any other value stays muted" do
    refute render_media(%{"video" => %{"src" => "/v.mp4", "muted" => false}}) =~ "muted"
    assert render_media(%{"video" => %{"src" => "/v.mp4", "muted" => true}}) =~ "muted"
    assert render_media(%{"video" => %{"src" => "/v.mp4"}}) =~ "muted"
  end

  test "poster and dimensions are carried through" do
    html =
      render_media(%{
        "video" => %{
          "src" => "/video/teaser.mp4",
          "poster" => "/images/teaser-poster.webp",
          "width" => 1920,
          "height" => 1080,
          "alt" => "Teaser"
        }
      })

    assert html =~ "/images/teaser-poster.webp"
    assert html =~ ~s(width="1920")
    assert html =~ ~s(height="1080")
    assert html =~ ~s(aria-label="Teaser")
  end

  test "a video suppresses the image and icon fallbacks in the same slot" do
    html =
      render_media(%{
        "video" => %{"src" => "/video/teaser.mp4"},
        "image" => %{"light" => "/images/banner.png", "dark" => "/images/banner_dark.png"},
        "icon" => "hero-play-solid"
      })

    assert html =~ "<video"
    refute html =~ "<img", "the image must not render alongside the video"
  end

  test "items without a video are unaffected" do
    html = render_media(%{"image" => %{"light" => "/images/banner.png"}})

    refute html =~ "<video"
    assert html =~ "<img"
    assert html =~ "/images/banner.png"
  end

  test "media_visual/1 tolerates being called without a video attr" do
    html =
      render_component(&PresentationPage.media_visual/1,
        image: %{light: "/images/banner.png", dark: nil, alt: "", width: nil, height: nil},
        variant: "hero",
        size: "hero"
      )

    assert html =~ "<img"
    refute html =~ "<video"
  end

  test "the video box is not squared, unlike the image box" do
    video = render_media(%{"video" => %{"src" => "/v.mp4"}}, "section")
    image = render_media(%{"image" => %{"light" => "/images/banner.png"}}, "section")

    # A 16:9 trailer in an aspect-square box collapses to a letterboxed sliver.
    refute video =~ "aspect-square"
    assert image =~ "aspect-square"
  end
end
