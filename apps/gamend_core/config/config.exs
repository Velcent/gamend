import Config

config :gamend_core, ecto_repos: [Gamend.Repo]

default_adapter =
  if System.get_env("GAMEND_DB_ADAPTER") == "postgres",
    do: Ecto.Adapters.Postgres,
    else: Ecto.Adapters.SQLite3

config :gamend_core, Gamend.Repo,
  adapter: default_adapter,
  # All tables use UUID (v7) primary/foreign keys — see Gamend.UUIDv7.
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

config :gamend_core, Gamend.Mailer, adapter: Swoosh.Adapters.Local

config :gamend_core, Gamend.Cache,
  inclusion_policy: :inclusive,
  levels: [
    {Gamend.Cache.L1, []}
  ]

# MDEx renders every markdown surface (guides, blog, changelog). Its NIF only
# builds in the syntax highlighter when told to at compile time, and each app
# that compiles the NIF needs the flag - otherwise fenced code renders as one
# undifferentiated colour, or raises once highlighting is requested.
config :mdex_native, syntax_highlighter: :lumis
