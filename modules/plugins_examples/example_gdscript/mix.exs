defmodule ExampleGdscript.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_gdscript,
      version: "0.1.0",
      elixir: "~> 1.20",
      # The only unusual line: source comes from `gen/`, which is generated from
      # `scripts/*.gd` and committed.
      elixirc_paths: ["gen"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [hooks_module: Gamend.Modules.ExampleGdscript]
    ]
  end

  defp deps do
    [
      {:gamend_sdk, path: "../../../sdk", runtime: false, optional: true},
      {:gamend_plugin_tools, path: "../../../sdk_tools", runtime: false}
    ]
  end

  defp aliases do
    [
      # One command: GDScript -> Elixir -> BEAM -> bundle.
      bundle: ["gamend.gdscript.compile", "plugin.bundle"]
    ]
  end
end
