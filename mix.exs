defmodule GamendHost.MixProject do
  use Mix.Project

  def project do
    [
      app: :gamend_host,
      name: "Gamend",
      version: System.get_env("GAMEND_CONTENT_APP_VERSION") || "1.0.0",
      elixir: "~> 1.20",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      dialyzer: [plt_add_apps: [:mix]],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {GamendHost.Application, []},
      extra_applications:
        [:logger, :runtime_tools, :swoosh] ++
          if(Mix.env() == :prod, do: [:os_mon], else: [])
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      shared_dep(:gamend_core, "apps/gamend_core"),
      shared_dep(:gamend_web, "apps/gamend_web"),
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:oban_web, "~> 2.11"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.20"},
      {:gen_smtp, "~> 1.0"},
      {:req, "~> 0.6"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:ueberauth_discord, "~> 0.7"},
      {:ueberauth_apple, github: "appsinacup/ueberauth_apple", branch: "master"},
      {:ueberauth_google, "~> 0.12"},
      {:ueberauth_facebook, "~> 0.10"},
      {:bandit, "~> 1.9"},
      {:ueberauth, "~> 0.10"},
      {:open_api_spex, "~> 3.22"},
      {:credo, ">= 1.7.16", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:guardian, "~> 2.3"},
      {:ueberauth_steam_strategy, "~> 0.1"},
      {:corsica, "~> 2.0"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "db.setup", "assets.setup", "assets.build"],
      "dev.start": [
        "ecto.create --quiet -r Gamend.Repo",
        "db.migrate",
        "assets.build",
        "phx.server"
      ],
      "prod.start": ["assets.deploy", "db.setup", "phx.server"],
      "db.migrate": ["host.migrate -r Gamend.Repo"],
      "db.rollback": ["host.rollback -r Gamend.Repo"],
      "db.setup": ["host.db.setup"],
      "db.reset": ["host.db.reset"],
      test:
        [
          "ecto.create --quiet -r Gamend.Repo",
          "host.migrate --quiet -r Gamend.Repo",
          "test"
        ] ++ local_web_commands([web_test_cmd("test")]),
      lint:
        ["format --check-formatted", "credo --strict"] ++
          local_web_commands([web_cmd("format --check-formatted"), web_cmd("credo --strict")]),
      "deps.audit": [&prune_vendored_lockfiles/1, "deps.audit"],
      # The inner loop: fast checks only. Generators and the web app's own
      precommit:
        [
          "compile --warning-as-errors",
          "format",
          "gen.sdk",
          # Regenerate rather than --check, like format and gen.sdk above: a
          # stale settings doc is fixed and committed here, and CI runs the
          # --check form so a bypassed precommit still cannot ship one.
          "gamend.settings.env_example",
          "gamend.settings.guide",
          # Theme text lives in data, so `gettext.extract` cannot see it.
          "gamend.theme.extract",
          "test",
          "credo --strict",
          "gamend.api.lint"
        ] ++
          local_web_commands([
            web_test_cmd("compile --warning-as-errors"),
            web_test_cmd("xref unreachable"),
            web_cmd("format"),
            web_cmd("credo --strict")
          ]),
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind gamend_web", "esbuild gamend_web"],
      "assets.deploy": [
        "tailwind gamend_web --minify",
        "esbuild gamend_web --minify",
        "phx.digest"
      ]
    ]
  end

  # mix_audit's `apps/**/mix.lock` glob also matches lockfiles vendored inside
  # git dependencies (pigeon ships one). A dependency's own lock never drives our
  # resolution — ours does — so scanning it only reports false positives.
  defp prune_vendored_lockfiles(_args) do
    "apps/**/mix.lock"
    |> Path.wildcard()
    |> Enum.filter(&(&1 =~ ~r{(^|/)deps/}))
    |> Enum.each(&File.rm/1)
  end

  # `mix cmd` pipes the child's stdio, so the child BEAM boots with ANSI off
  # and cmd-wrapped steps lose color even on a TTY. Forward this process's own
  # color state; the web app's config.exs honors FORCE_ANSI. On CI (no TTY)
  # nothing is set and logs stay escape-free.
  defp force_ansi, do: if(IO.ANSI.enabled?(), do: "FORCE_ANSI=true ", else: "")

  defp web_cmd(task), do: "cmd --cd #{web_app_path()} env #{force_ansi()}mix #{task}"

  defp web_test_cmd(task),
    do: "cmd --cd #{web_app_path()} env MIX_ENV=test #{force_ansi()}mix #{task}"

  defp local_web_commands(commands) do
    if local_web_source?(), do: commands, else: []
  end

  defp local_web_source?, do: File.dir?("apps/gamend_web")

  defp web_app_path, do: shared_app_path(:gamend_web, "apps/gamend_web")

  defp shared_app_path(app, fallback) do
    dep_root = Mix.Project.deps_paths()[app]
    nested_dep_path = dep_root && Path.join(dep_root, fallback)

    cond do
      File.dir?(fallback) -> fallback
      nested_dep_path && File.dir?(nested_dep_path) -> nested_dep_path
      dep_root -> dep_root
      true -> fallback
    end
  end

  defp shared_dep(app, local_path) do
    if File.dir?(local_path) do
      {app, path: local_path}
    else
      {app, github: "appsinacup/gamend", sparse: local_path, override: true}
    end
  end
end
