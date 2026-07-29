defmodule GameServer.JobsObanConfigTest do
  @moduledoc """
  Queue concurrency is written for Postgres. SQLite serializes every writer
  behind one database-wide lock, so the same numbers turn into contention and
  "database is locked" crashes (Oban.Stager is the usual casualty). The config
  has to scale itself down for the Lite engine and leave Postgres alone.
  """
  use ExUnit.Case, async: false

  alias GameServer.Jobs

  defp with_adapter(adapter, fun) do
    repo_config = Application.get_env(:game_server_core, GameServer.Repo)
    oban_config = Application.get_env(:game_server_core, Oban)

    Application.put_env(
      :game_server_core,
      GameServer.Repo,
      Keyword.put(repo_config, :adapter, adapter)
    )

    Application.put_env(
      :game_server_core,
      Oban,
      Keyword.merge(oban_config, queues: [default: 10, hooks: 20, mailers: 5])
    )

    try do
      fun.()
    after
      Application.put_env(:game_server_core, GameServer.Repo, repo_config)
      Application.put_env(:game_server_core, Oban, oban_config)
    end
  end

  test "sqlite caps queue concurrency and stages less often" do
    with_adapter(Ecto.Adapters.SQLite3, fn ->
      config = Jobs.oban_config()

      assert config[:engine] == Oban.Engines.Lite
      assert Enum.all?(config[:queues], fn {_name, limit} -> limit <= 2 end)
      assert config[:stage_interval] >= :timer.seconds(5)
    end)
  end

  test "postgres keeps the configured concurrency untouched" do
    with_adapter(Ecto.Adapters.Postgres, fn ->
      config = Jobs.oban_config()

      assert config[:engine] == Oban.Engines.Basic
      assert config[:queues][:default] == 10
      assert config[:queues][:hooks] == 20
      refute Keyword.has_key?(config, :stage_interval)
    end)
  end
end
