defmodule StressHook.MixProject do
  use Mix.Project

  def project do
    [
      app: :stress_hook,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [hooks_module: Gamend.Modules.StressHook]
    ]
  end

  # NOTE: This example lives inside the main server repo, so we depend on the
  # in-repo SDK via a path dependency.
  defp deps do
    [
      {:gamend_sdk, path: "../../../sdk", runtime: false, optional: true},
      {:gamend_plugin_tools, path: "../../../sdk_tools", runtime: false},
      # Compile-time only — the server supplies telemetry at runtime; this is
      # here so `:telemetry.attach/4` resolves when the plugin is built.
      {:telemetry, "~> 1.3", runtime: false}
    ]
  end
end
