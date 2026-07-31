defmodule GamendPluginTools.MixProject do
  use Mix.Project

  @version "1.0.26"
  @source_url "https://github.com/appsinacup/gamend"

  def project do
    [
      app: :gamend_plugin_tools,
      version: System.get_env("APP_VERSION") || @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Tools for building Gamend plugins (hooks).
    """
  end

  defp package do
    [
      name: "gamend_plugin_tools",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
