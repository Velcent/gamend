defmodule GamendWeb.Components.PresentationPageSrcsetTest do
  @moduledoc """
  `"widths": [...]` on a config image opts it into a responsive `srcset`. The
  variants are addressed by convention (`foo.png` + 480 is `foo-480.png`), so
  nothing but this list connects the config to the files on disk — and a wrong
  guess is a broken image rather than a heavy one.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GamendWeb.PresentationPage

  # priv/static/images/media-fixture.png and its -4 variant ship with the app
  # precisely so this can assert the positive case.
  @fixture "/images/media-fixture.png"

  defp render_media(item, variant \\ "section") do
    render_component(&PresentationPage.media/1, item: item, variant: variant)
  end

  test "no widths means no srcset, exactly as before the attribute existed" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x"}})

    assert html =~ "<img"
    refute html =~ "srcset"
    refute html =~ "sizes"
  end

  test "a declared width whose file exists lands in the srcset with its descriptor" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}})

    assert html =~ "srcset="
    assert html =~ "/images/media-fixture-4.png"
    assert html =~ "4w"
  end

  test "a declared width whose file is missing is dropped, not emitted as a 404" do
    # A 404 inside a srcset is not a graceful fallback to `src` — it is a broken
    # image on whichever viewport picked that candidate.
    html =
      render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4, 9999]}})

    assert html =~ "/images/media-fixture-4.png"
    refute html =~ "media-fixture-9999.png"
  end

  test "every width missing leaves the img with no srcset at all" do
    html = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [7777]}})

    assert html =~ "<img"
    refute html =~ "srcset"
    refute html =~ "sizes"
  end

  test "sizes describes the slot, so the browser can pick before layout" do
    # Without `sizes` the browser assumes 100vw and takes the largest candidate,
    # which throws away the point of shipping variants at all.
    section = render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}})

    hero =
      render_media(%{"image" => %{"light" => @fixture, "alt" => "x", "widths" => [4]}}, "hero")

    assert section =~ "45vw"
    assert hero =~ "55vw"
  end

  test "an explicit sizes in the config wins over the per-slot default" do
    html =
      render_media(%{
        "image" => %{"light" => @fixture, "alt" => "x", "widths" => [4], "sizes" => "42vw"}
      })

    assert html =~ "42vw"
    refute html =~ "45vw"
  end

  test "the light/dark pair gets a srcset per theme, from each one's own variants" do
    html =
      render_media(%{
        "image" => %{
          "light" => @fixture,
          # No `-4` twin on disk for this one, so only the light img is
          # responsive — the dark img must not borrow the light srcset.
          "dark" => "/images/media-missing-dark.png",
          "alt" => "x",
          "widths" => [4]
        }
      })

    assert html =~ "/images/media-fixture-4.png"
    refute html =~ "media-missing-dark-4.png"
  end

  test "media_visual/1 still tolerates a partial image map" do
    # It is public, and a host may build the map by hand. Missing srcset keys
    # must not be a KeyError.
    html =
      render_component(&PresentationPage.media_visual/1,
        image: %{light: @fixture, dark: nil, alt: "", width: nil, height: nil},
        variant: "hero",
        size: "hero"
      )

    assert html =~ "<img"
    refute html =~ "srcset"
  end
end
