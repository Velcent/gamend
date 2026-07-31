defmodule GamendWeb.HomeThemeTest do
  use GamendWeb.ConnCase, async: true

  alias Gamend.Content
  alias Gamend.Theme.JSONConfig

  test "home page renders without errors when runtime theme has empty values", %{conn: conn} do
    # Empty values — no merging with packaged defaults
    base =
      Path.join(System.tmp_dir!(), "theme_test_home_#{System.unique_integer([:positive])}.json")

    File.write!(base, Jason.encode!(%{"title" => "", "tagline" => ""}))

    orig =
      Gamend.SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :theme_config)

    Gamend.SettingsHelpers.put(
      :gamend_core,
      Gamend.ContentSettings,
      :theme_config,
      base
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
      File.rm(base)
    end)

    resp = get(conn, "/") |> html_response(200)

    # Page should render without crashing
    assert resp =~ "<html"
    assert resp =~ "<title"
  end
end
