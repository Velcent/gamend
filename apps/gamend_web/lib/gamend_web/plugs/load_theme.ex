defmodule GamendWeb.Plugs.LoadTheme do
  @moduledoc """
  Plug that assigns the resolved theme map into `conn.assigns.theme` so
  templates and LiveViews can render provider-driven copy alongside the
  host-owned branding assets.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    require Logger

    locale = Map.get(conn.assigns, :locale) || Gettext.get_locale(GamendWeb.Gettext)
    theme = GamendWeb.Layouts.resolve_theme(locale)

    # In development & test environments log the resolved theme_map to make
    # runtime debugging easier when things appear blank in the UI.
    if log_theme?() do
      Logger.debug(
        "LoadTheme: assigned theme=#{inspect(theme)} (GAMEND_CONTENT_THEME_CONFIG=#{inspect(Gamend.Settings.get(Gamend.ContentSettings, :theme_config))})"
      )
    end

    assign(conn, :theme, theme)
  end

  defp log_theme? do
    Application.get_env(:gamend_web, :environment, :prod) in [:dev, :test]
  end
end
