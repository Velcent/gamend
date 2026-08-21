defmodule Gamend.Release do
  @moduledoc """
  Release-time equivalents of the `host.*` mix tasks.

  A release ships compiled `.beam` files and nothing else — no Mix, no project
  tree, no `mix` binary — so `mix db.migrate` cannot run inside an image built
  from `Dockerfile.release`. These functions are what the release's own
  entrypoint calls instead:

      bin/gamend_host eval "Gamend.Release.createdb()"
      bin/gamend_host eval "Gamend.Release.migrate()"

  Under Mix the `host.*` tasks stay the entry point. Both funnel through
  `Gamend.Repo.MigrationPaths`, so the two cannot drift on which migrations
  they consider.

  `eval` starts a fresh node, applies `config/runtime.exs` and runs the
  expression **without starting the application**, which is the point: a
  migration that fails takes the command down instead of half-booting an
  endpoint against a database it does not match.
  """

  alias Gamend.Repo.MigrationPaths

  @otp_app :gamend_core

  @doc """
  Runs every pending migration — core's and the host's — on each repo.
  """
  @spec migrate() :: :ok
  def migrate do
    paths = migration_paths()

    for repo <- repos() do
      {:ok, _migrated, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, paths, :up, all: true))
    end

    :ok
  end

  @doc """
  Rolls `repo` back down to `version`.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    paths = migration_paths()

    {:ok, _rolled_back, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, paths, :down, to: version))

    :ok
  end

  @doc """
  Creates the database when it does not exist yet, mirroring `mix ecto.create`.

  Idempotent: an existing database is left alone. Postgres deployments where
  the server provisions the database already can skip this entirely.
  """
  @spec createdb() :: :ok
  def createdb do
    for repo <- repos() do
      start_driver(repo)

      case repo.__adapter__().storage_up(repo.config()) do
        :ok ->
          :ok

        {:error, :already_up} ->
          :ok

        {:error, reason} ->
          raise "could not create storage for #{inspect(repo)}: #{inspect(reason)}"
      end
    end

    :ok
  end

  defp repos do
    Application.load(@otp_app)
    Application.fetch_env!(@otp_app, :ecto_repos)
  end

  # An empty path list is the one failure mode worth being loud about:
  # `Ecto.Migrator` given no paths runs nothing and returns success, so a
  # release whose priv dirs were resolved wrongly would report a clean
  # migration and then serve traffic against an un-migrated database. Crash
  # instead — a container that will not start is a far cheaper problem.
  defp migration_paths do
    case MigrationPaths.all() do
      [] ->
        raise """
        No migration directories found.

        Under a release these resolve through the code server, so this means
        neither :gamend_core nor the host application (RELEASE_NAME=#{System.get_env("RELEASE_NAME") || "<unset>"})
        ships a priv/repo/migrations. Refusing to report a successful migration
        that ran nothing.
        """

      paths ->
        paths
    end
  end

  # storage_up/1 opens its own connection before the repo is started, so the
  # driver application has to be running under its own steam.
  defp start_driver(repo) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> {:ok, _} = Application.ensure_all_started(:postgrex)
      Ecto.Adapters.SQLite3 -> {:ok, _} = Application.ensure_all_started(:exqlite)
      _other_adapter -> :ok
    end

    :ok
  end
end
