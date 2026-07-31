defmodule GamendWeb.TestSupport.Runtime do
  @moduledoc false

  alias Gamend.Hooks.PluginManager
  alias GamendWeb.Plugs.GeoCountry
  alias GamendWeb.Plugs.IpBan

  @supervisor __MODULE__.Supervisor

  def ensure_started do
    ensure_host_code_path()
    maybe_configure_host_router()
    maybe_register_content_paths()
    ensure_schedule_table()
    IpBan.init_table()
    GeoCountry.init_table()

    case Supervisor.start_link(children(), strategy: :one_for_one, name: @supervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp children do
    [
      Gamend.Repo,
      {Gamend.Cache, []},
      Gamend.Cache.Stats,
      {Task.Supervisor, name: Gamend.TaskSupervisor, max_children: 200},
      {Phoenix.PubSub, name: Gamend.PubSub},
      Gamend.Presence,
      Gamend.Cache.Sync,
      GamendWeb.ConnectionTracker,
      {GamendWeb.RateLimit, clean_period: :timer.minutes(5)},
      GamendWeb.AdminLogBuffer,
      PluginManager,
      {Oban, Gamend.Jobs.oban_config()}
    ] ++ maybe_endpoint_child()
  end

  defp maybe_endpoint_child do
    endpoint = Module.concat([GamendWeb, Endpoint])

    if Code.ensure_loaded?(endpoint) do
      [endpoint]
    else
      []
    end
  end

  defp maybe_configure_host_router do
    router = Module.concat([GamendHost, Router])

    if Code.ensure_loaded?(router) do
      Application.put_env(:gamend_web, :router, router, persistent: true)
    end
  end

  defp maybe_register_content_paths do
    content_paths = Module.concat([GamendHost, ContentPaths])

    if Code.ensure_loaded?(content_paths) and
         function_exported?(content_paths, :register_defaults, 0) do
      content_paths.register_defaults()
    end
  end

  defp ensure_host_code_path do
    host_ebin =
      Mix.Project.build_path()
      |> Path.join("lib/gamend_host/ebin")
      |> Path.expand(File.cwd!())

    if File.dir?(host_ebin) do
      Code.prepend_path(String.to_charlist(host_ebin))
    end
  end

  defp ensure_schedule_table do
    # Idempotent: creates the Schedule registry + protected-callback tables if
    # they don't exist yet.
    Gamend.Schedule.start_link()
  end
end
