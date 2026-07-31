import Config

# config/runtime.exs is executed for all environments, including during
# releases. It runs after compilation and before the system starts, so it is
# used to load production configuration and secrets from environment
# variables or elsewhere. Do not define any compile-time configuration here.

# .env is already loaded by host_config.exs during config evaluation; this is
# kept as a safety net for hosts whose compile-time config doesn't load it.
# (Code.require_file is a no-op when the file was already required.)
if config_env() == :dev do
  Code.require_file("dotenv.exs", __DIR__)
  Gamend.Dotenv.load(Path.expand("../.env", __DIR__))
end

# Every runtime derivation — declared settings read from the environment plus
# the translation into the shapes Phoenix, Ecto, Bandit, Swoosh and Pigeon
# expect — ships with GamendWeb.HostRuntime so host repos share one
# implementation instead of forking this file. Host-specific runtime config
# goes below the loop.
for entry <-
      GamendWeb.HostRuntime.config(config_env(), host_root: Path.expand("..", __DIR__)) do
  case entry do
    {app, opts} -> config app, opts
    {app, key, value} -> config app, key, value
  end
end
