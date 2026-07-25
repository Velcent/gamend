defmodule GameServer.ContentSettings do
  @moduledoc """
  Where the server finds host-supplied content: the theme config, hook plugins,
  and the GeoIP database.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :content,
    label: "Content & plugins"

  setting(:theme_config, :string,
    doc: "Base path of the theme JSON. Only locale-suffixed files are loaded (.en.json, ...)."
  )

  setting(:plugins_dir, :string,
    default: "modules/plugins",
    doc: "Directory containing OTP hook plugins."
  )

  setting(:geoip_db_path, :string,
    doc: "MaxMind mmdb file. Defaults to data/GeoLite2-Country.mmdb when present."
  )

  setting(:app_version, :string, doc: "Version reported in the OpenAPI spec and admin pages.")
end
