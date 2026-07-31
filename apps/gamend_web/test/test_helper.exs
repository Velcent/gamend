repo_config = Application.get_env(:gamend_core, Gamend.Repo, [])

if repo_config[:adapter] == Ecto.Adapters.SQLite3 do
  ExUnit.configure(max_cases: 1)
end

GamendWeb.TestSupport.Runtime.ensure_started()

# capture_log: many tests deliberately exercise failure paths (OAuth CSRF
# rejection, payment decline, SMTP failure, plugin hook raising, log rotation
# probes). Their logs are captured per test and only printed when that test
# fails, so a green run stays readable without losing diagnostics.
ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Gamend.Repo, :manual)

# Some auth controller flows need Apple's audiences configured. Set once here
# and kept stable across async tests to avoid cross-test races.
alias Gamend.OAuth.Providers, as: OAuthProviders
alias Gamend.SettingsHelpers

for {key, value} <- [apple_client_id: "com.example.web", apple_ios_client_id: "com.example.ios"] do
  SettingsHelpers.put(
    :gamend_core,
    OAuthProviders,
    key,
    SettingsHelpers.get(:gamend_core, OAuthProviders, key) || value
  )
end
