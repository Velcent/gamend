import Config

# `mix cmd` (how host precommits run this app's tasks) pipes child output, so
# this BEAM boots with ANSI off even when the invoking terminal supports
# color. The parent sets FORCE_ANSI=true only when its own stdout is a TTY,
# so CI logs stay escape-free.
if System.get_env("FORCE_ANSI") == "true" do
  config :elixir, :ansi_enabled, true
end

config :gamend_web, :scopes,
  user: [
    default: true,
    module: Gamend.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Gamend.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :gamend_core, ecto_repos: [Gamend.Repo]

config :gamend_web,
  ecto_repos: [Gamend.Repo],
  generators: [timestamp_type: :utc_datetime],
  environment: config_env(),
  router: GamendWeb.Router,
  host_router: GamendWeb.Router,
  host_gettext_backend: GamendWeb.Gettext,
  home_banner_link: nil,
  host_static_app: :gamend_web,
  asset_static_app: :gamend_web,
  well_known_static_app: :gamend_web,
  host_static_paths: ~w(images game favicon.ico robots.txt .well-known theme.css)

default_adapter =
  if System.get_env("GAMEND_DB_ADAPTER") == "postgres",
    do: Ecto.Adapters.Postgres,
    else: Ecto.Adapters.SQLite3

config :gamend_core, Gamend.Repo,
  adapter: default_adapter,
  # All tables use UUID (v7) primary/foreign keys — see Gamend.UUIDv7.
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Background jobs (Gamend.Jobs / Gamend.Schedule). The `:engine` is
# injected at runtime from the Repo's actual adapter by
# Gamend.Jobs.oban_config/0. Kept in sync with config/host_config.exs — the
# web app is also published/tested standalone.
config :gamend_core, Oban,
  repo: Gamend.Repo,
  queues: [default: 10, hooks: 20, mailers: 5, storage: 5, webhooks: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Gamend.Schedule.TickWorker}]}
  ]

# Object storage — defaults to local disk (see config/host_config.exs).
config :gamend_core, Gamend.Storage, adapter: :local
config :ex_aws, json_codec: Jason

config :gamend_web, GamendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GamendWeb.ErrorHTML, json: GamendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Gamend.PubSub,
  live_view: [signing_salt: "ZPmggGLv"]

config :phoenix,
  gzippable_exts: ~w(.js .map .css .txt .text .html .json .svg .eot .ttf .wasm .pck)

config :gamend_core, Gamend.Mailer, adapter: Swoosh.Adapters.Local

config :gamend_core, Gamend.Cache,
  inclusion_policy: :inclusive,
  levels: [
    {Gamend.Cache.L1, []}
  ]

config :esbuild,
  version: "0.25.4",
  gamend_web: [
    args:
      ~w(js/app.js js/theme-init.js js/mermaid.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [
        Path.expand("../deps", __DIR__),
        Mix.Project.build_path(),
        Path.join(Mix.Project.build_path(), Atom.to_string(config_env()))
      ]
    }
  ]

config :tailwind,
  version: "4.1.7",
  gamend_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, ["password", "token", "secret", "authorization", "api_key"]

config :gamend_web, GamendWeb.Auth.Guardian,
  issuer: "gamend",
  secret_key: "REPLACE_THIS_IN_RUNTIME_CONFIG"

config :gamend_web, :webrtc,
  enabled: true,
  ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]

# MDEx renders every markdown surface (guides, blog, changelog). Its NIF only
# builds in the syntax highlighter when told to at compile time, and each app
# that compiles the NIF needs the flag - otherwise fenced code renders as one
# undifferentiated colour, or raises once highlighting is requested.
config :mdex_native, syntax_highlighter: :lumis

import_config "#{config_env()}.exs"

config :mime, :types, %{
  "application/octet-stream" => ["pck"]
}

config :ueberauth, Ueberauth,
  providers: [
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email"]},
    apple: {Ueberauth.Strategy.Apple, []},
    google: {Ueberauth.Strategy.Google, []},
    facebook: {Ueberauth.Strategy.Facebook, []},
    steam: {Ueberauth.Strategy.Steam, []}
  ]

# Provider credentials are not set here. Ueberauth reads them from its own
# application env, which the host's config/host_runtime.exs fills from the
# declared Gamend.OAuth.Providers settings — one source, resolved at boot.
config :ueberauth, Ueberauth.Strategy.Apple.OAuth,
  client_secret: {Gamend.Apple, :client_secret}
