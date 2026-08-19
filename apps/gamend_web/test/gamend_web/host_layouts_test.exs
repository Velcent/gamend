defmodule GamendWeb.HostLayoutsTest do
  use ExUnit.Case, async: true

  alias GamendWeb.HostLayouts

  test "locale labels use display casing for native language names" do
    labels = HostLayouts.locale_labels()

    assert labels["cs"] == "Čeština"
    assert labels["fi"] == "Suomi"
    assert labels["hu"] == "Magyar"
  end

  test "theme image settings override host defaults" do
    theme =
      HostLayouts.resolve_theme("en", %{
        "title" => "Custom",
        "logo" => "/images/custom-logo.webp",
        "banner" => "/images/custom-banner.webp",
        "favicon" => "/images/custom.ico"
      })

    assert theme["logo"] == "/images/custom-logo.webp"
    assert theme["banner"] == "/images/custom-banner.webp"
    assert theme["favicon"] == "/images/custom.ico"
  end
end
