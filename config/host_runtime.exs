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
# Under Mix this file sits in config/, so the host root is one level up. In a
# release it is copied to releases/<vsn>/, where the same expansion would point
# at releases/ — and every host-relative default (db/, data/) would silently
# resolve to a directory no volume is mounted on. RELEASE_ROOT is exported by
# the release's own boot script and is unset under Mix.
host_root = System.get_env("RELEASE_ROOT") || Path.expand("..", __DIR__)

for entry <- GamendWeb.HostRuntime.config(config_env(), host_root: host_root) do
  case entry do
    {app, opts} -> config app, opts
    {app, key, value} -> config app, key, value
  end
end
