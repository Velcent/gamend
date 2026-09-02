defmodule GamendWeb.HostSupervision do
  @moduledoc """
  The canonical supervision tree for a Gamend host application.

  A host app owns its own `Application.start/2`, so historically it also owned a
  hand-written children list. That list is not host-specific — it is core's, and
  every core feature that adds a process needs a line in *every* host's copy.
  Nothing enforces that, and nothing fails loudly when it is missed: a missing
  child means enqueues target a process that was never started, so the feature
  silently no-ops while its config still reads "on".

  That is not hypothetical. Before this module existed, one host had drifted by
  six children (`Cache.Stats`, `Cache.Sync`, `IpBanSync`, `Retention`,
  `Tournaments.Ticker`, `Matchmaking.Worker`), an unbounded task supervisor, and
  the lobby-snapshots writer — the last of which cost a full debugging session
  to find, because every other signal said capture was working.

  So the list lives here, next to the features that populate it, and hosts call
  `children/1`. Host-specific processes go in `:extra` rather than into a fork
  of the list.

  ## Usage

      def start(_type, _args) do
        GamendWeb.HostSupervision.init_runtime()

        Supervisor.start_link(
          GamendWeb.HostSupervision.children(extra: [MyHost.Thing]),
          strategy: :one_for_one,
          name: MyHost.Supervisor
        )
      end
  """

  alias Gamend.Chat.Moderation.Cache, as: ModerationCache
  alias GamendWeb.Plugs.GeoCountry
  alias GamendWeb.Plugs.IpBan

  @doc """
  Set up the ETS tables and OS services children assume already exist.

  Must run before `children/1` is supervised: the Schedule tick reads the
  registry `Gamend.Schedule.start_link/0` creates, and the ban/geo plugs
  read theirs on the first request. Safe to call more than once.
  """
  @spec init_runtime() :: :ok
  def init_runtime do
    # Before anything starts: a missing required setting should stop the boot
    # here, with a list of what is missing, rather than surface later as a
    # crash-loop in whichever child needed it.
    env = Application.get_env(:gamend_web, :environment, :prod)
    Gamend.Settings.validate!(env)
    refuse_published_secret!(env)

    Application.start(:os_mon)

    # ETS owner for the Schedule registry + protected-callback set — must exist
    # before the Oban Cron tick fires.
    Gamend.Schedule.start_link()
    IpBan.init_table()
    GeoCountry.init_table()
    # Word blocklist + active mutes, read on every outgoing chat message.
    ModerationCache.init_table()

    :ok
  end

  # Secrets that have appeared in this repository, and are therefore known to
  # everyone. `docker-compose.yml` shipped the first one as a literal for a long
  # time, so a deployment that started from the stock file is running with a key
  # an attacker can read on GitHub — and since the Guardian secret falls back to
  # `secret_key_base`, that key mints API tokens for any account, admin included.
  #
  # Refusing to boot is the point: this cannot be a warning, because the failure
  # it prevents is silent and total, and a warning in a container log is a
  # warning nobody reads.
  @published_secrets [
    "1DdaMAX56nUh1tvXniEEuQNsGNvgADndawxrJ3YFZlLXc9EOahC/NFDgowCDUFwb"
  ]

  defp refuse_published_secret!(:prod) do
    [
      {"GAMEND_AUTH_SECRET_KEY_BASE", Gamend.Settings.get(Gamend.Accounts, :secret_key_base)},
      {"GAMEND_AUTH_GUARDIAN_SECRET_KEY",
       Gamend.Settings.get(Gamend.Accounts, :guardian_secret_key)}
    ]
    |> Enum.each(fn {name, value} ->
      if value in @published_secrets do
        raise """
        #{name} is set to a value published in the Gamend repository.

        It signs session cookies and API tokens, so anyone who has read the
        repository can forge a token for any account on this server, including
        an administrator.

        Generate a new one and restart:

            #{name}=$(mix phx.gen.secret)

        Treat any data this server has handled as exposed, and revoke sessions
        once the new key is in place.
        """
      end
    end)
  end

  defp refuse_published_secret!(_env), do: :ok

  @doc """
  Core's children, in start order.

  Options:

  - `:plugins` — start `Gamend.Hooks.PluginManager` (default `true`). Hosts
    that ship no plugins, and test configs that load them separately, pass
    `false`.
  - `:extra` — host-specific children, appended after core's. Anything here is
    genuinely host-owned; if it is a core feature it belongs in this list
    instead, so every host gets it.

  Order matters and is deliberate: `Repo` and `Cache` before anything that
  reads them, `PluginManager` before `Endpoint` so hooks resolve on the first
  request, and the periodic workers last so a slow sweep never delays boot.
  """
  @spec children(keyword()) :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children(opts \\ []) when is_list(opts) do
    plugins? = Keyword.get(opts, :plugins, true)
    extra = Keyword.get(opts, :extra, [])

    [
      GamendWeb.Telemetry,
      GamendWeb.PromEx,
      Gamend.Repo,
      {Gamend.Cache, []},
      # Aggregates cache hit/miss + overload counters for the admin dashboard
      Gamend.Cache.Stats,
      # Bounded: when full, Gamend.Async runs work inline (back-pressure)
      {Task.Supervisor, name: Gamend.TaskSupervisor, max_children: 200},
      {DNSCluster, query: Application.get_env(:gamend_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gamend.PubSub, pool_size: pool_size(:pubsub_pool_size)},
      # Apply cache invalidations broadcast by other instances
      Gamend.Cache.Sync,
      GamendWeb.ConnectionTracker,
      # Load persisted IP bans and mirror ban events from other instances
      GamendWeb.IpBanSync,
      # Load the word blocklist + mutes, mirror moderation events from other
      # instances, and sweep expired mutes
      Gamend.Chat.Moderation.Sync,
      {GamendWeb.RateLimit, clean_period: :timer.minutes(5)},
      GamendWeb.AdminLogBuffer,
      # Periodic cleanup of old geo-country minute buckets
      GamendWeb.GeoCountryCleaner
    ] ++
      plugin_children(plugins?) ++
      [
        GamendWeb.Endpoint,
        # Coalesces is_online transitions into one write per window, so a
        # connect storm of distinct players is not one transaction each.
        Gamend.Accounts.PresenceWriter,
        # Periodically mark stale online users as offline (safety net for crashes)
        Gamend.Accounts.StalePresenceSweeper,
        # Prune old chat messages / notifications / payment events (RETENTION_* env vars)
        Gamend.Retention,
        # Tournament lifecycle: transitions, draws, match deadlines, recurrence
        Gamend.Tournaments.Ticker,
        # Push delivery processes (Goth + Pigeon dispatchers); supervises
        # nothing when no PUSH_*/APNS_* vars are set. Before Oban so
        # dispatchers are up when push-queue workers start running.
        Gamend.Push.Supervisor,
        # Durable background jobs (Gamend.Jobs) + the per-minute Cron tick
        # that drives Gamend.Schedule.
        {Oban, Gamend.Jobs.oban_config()},
        # Worker that drives the matchmaking sweep
        Gamend.Matchmaking.Worker,
        # Buffers lobby snapshots/events and assigns seq. :global-registered, so
        # only one node runs it and start_link returns :ignore on the others.
        Gamend.LobbySnapshots.Writer,
        # Signaling relay for WebRTC user-to-user and client-server topologies
        {Gamend.Presence, pool_size: pool_size(:presence_pool_size)}
      ] ++
      extra
  end

  # Both pools shard by topic and default to 1, which is what a single-node
  # deployment has always run. Read here rather than baked into config so the
  # admin settings page reports the live value.
  defp pool_size(setting) do
    case Gamend.Settings.get(GamendWeb.Realtime, setting) do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  # Load hook plugins (OTP apps) shipped under modules/plugins/*.
  defp plugin_children(true), do: [Gamend.Hooks.PluginManager]
  defp plugin_children(false), do: []
end
