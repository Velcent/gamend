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

  ## The shell derives ten assigns from five attrs, and a function component is
  ## stateless, so `assign/3` marks every one of them changed on every render
  ## unless something stops it. Left unstopped, the navbar and the footer
  ## re-render on every diff any LiveView sends, and the client morphs the
  ## server's markup back over the DOM — which closes an open `<details>`
  ## dropdown. Nothing about that is visible in rendered markup, so these
  ## assert on `__changed__` itself.
  describe "app shell change tracking" do
    @derived [
      :background_icons,
      :breadcrumbs,
      :current_path,
      :current_query,
      :footer,
      :known_locales,
      :locale,
      :navigation,
      :notif_unread_count,
      :theme
    ]

    defp app_assigns(changed) do
      %{
        __changed__: changed,
        flash: %{},
        current_scope: nil,
        current_path: "/tests/spanish",
        flush: false,
        background_icons: nil,
        inner_block: []
      }
    end

    test "a diff that only touched the page body leaves the shell alone" do
      changed = HostLayouts.prepare_app_assigns(app_assigns(%{inner_block: true})).__changed__

      assert Map.has_key?(changed, :inner_block)

      for key <- @derived do
        refute Map.has_key?(changed, key), "#{key} would re-render the navbar on every diff"
      end
    end

    test "a flash does not re-render the shell either" do
      changed = HostLayouts.prepare_app_assigns(app_assigns(%{flash: true})).__changed__

      for key <- @derived, do: refute(Map.has_key?(changed, key))
    end

    test "a new path re-renders the shell" do
      changed =
        HostLayouts.prepare_app_assigns(app_assigns(%{current_path: true})).__changed__

      for key <- @derived, do: assert(Map.has_key?(changed, key))
    end

    test "a change of scope re-renders the shell" do
      changed =
        HostLayouts.prepare_app_assigns(app_assigns(%{current_scope: true})).__changed__

      assert Map.has_key?(changed, :navigation)
      assert Map.has_key?(changed, :footer)
      assert Map.has_key?(changed, :notif_unread_count)
    end

    ## `nil` is how the engine says "not change tracking" — a dead render, or a
    ## first render. Freezing anything there would leave the navbar unrendered.
    test "a render with no change tracking renders everything" do
      assigns = HostLayouts.prepare_app_assigns(app_assigns(nil))

      assert assigns.__changed__ == nil
      assert assigns.navigation
      assert assigns.theme["title"]
    end
  end
end
