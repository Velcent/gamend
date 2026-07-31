defmodule ExampleHook.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_hook,
      version: "0.1.1",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [hooks_module: Gamend.Modules.ExampleHook]
    ]
  end

  # NOTE: This example lives inside the main server repo, so we depend on the
  # in-repo SDK via a path dependency.
  defp deps do
    [
      {:gamend_sdk, path: "../../../sdk", runtime: false, optional: true},
      {:gamend_plugin_tools, path: "../../../sdk_tools", runtime: false},
      {:bunt, "~> 1.0"},
      # Typed hook payloads (see proto/example_hook.proto).
      {:protobuf, "~> 0.17"}
    ]
  end
end
