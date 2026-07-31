defmodule GamendWeb.ThemeLiveTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Content
  alias Gamend.Theme.JSONConfig

  test "LiveView pages render without errors when GAMEND_CONTENT_THEME_CONFIG is unset", %{
    conn: conn
  } do
    # Ensure GAMEND_CONTENT_THEME_CONFIG unset so no theme is loaded
    orig =
      Gamend.SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :theme_config)

    Gamend.SettingsHelpers.delete(
      :gamend_core,
      Gamend.ContentSettings,
      :theme_config
    )

    JSONConfig.reload()
    Content.reload()

    on_exit(fn ->
      if orig,
        do:
          Gamend.SettingsHelpers.put(
            :gamend_core,
            Gamend.ContentSettings,
            :theme_config,
            orig
          ),
        else:
          Gamend.SettingsHelpers.delete(
            :gamend_core,
            Gamend.ContentSettings,
            :theme_config
          )

      JSONConfig.reload()
      Content.reload()
    end)

    {:ok, _lv, html} = live(conn, "/leaderboards")

    # Page should render without crashing even with no theme
    assert html =~ "<html"
  end
end
