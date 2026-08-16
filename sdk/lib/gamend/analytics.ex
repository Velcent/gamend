defmodule Gamend.Analytics do
  @moduledoc ~S"""
  The one place aggregate numbers come from. Four families:

  * **Activity & retention** — DAU / WAU / MAU, new users per day, strict
    D1 / D7 / D30 cohort retention, payer conversion. Derived from
    `user_activity_days` (one row per user per UTC day seen, written by
    `record_activity/2` from the `last_seen_at` touches in `Gamend.Accounts`),
    `users.inserted_at` for cohorts and `purchases` for payers.
  * **Snapshot** — `snapshot/0`: every context's live counters (players,
    lobbies, parties, quests, signaling, matchmaking, tournaments) composed
    once and cached, so the public stats page, the admin index and the
    `/api/v1/stats` endpoint show the same numbers instead of each calling
    six modules.
  * **Economy flow** — `economy_flow/2`: coins granted and spent per day per
    ledger `reason`, straight from `ledger_entries`.
  * **Daily counters** — `count/3` + `counts/2`: named per-day counters for
    events that have no table of their own (a level finished, a start blocked
    by empty hearts). The game picks the keys; the engine sums them.

  Days are UTC, like every other period boundary on the server. "D7" means
  *seen on the 7th day after the registration day*, not "seen at any point in
  the first week" — the classic strict definition, so numbers compare with
  the ones stores and ad networks report.

  Reads are cheap enough for a dashboard on a small database; the composed
  views (`snapshot/0`, `dashboard_stats/0`) cache for a minute or a few.
  Nothing here is exposed to players except through the operator-gated
  public stats page.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type rate() :: float() | nil

  @doc ~S"""
    Distinct users seen on any day in `from..to` (inclusive, UTC dates).
  """
  @spec active_users(Date.t(), Date.t()) :: non_neg_integer()
  def active_users(_from, _to) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.active_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Adds `n` to the counter `key` for the UTC day of `now`. One atomic
    upsert-increment; safe to call from hot paths that already write (a level
    end, a purchase), not from paths that otherwise only read.
    
    Keys are dotted, game-owned strings up to 128 chars;
    put a dimension after a colon (`"level.started.lang:ja"`) so `counts/2`
    can pull a whole family by prefix. Never raises; a bad key is dropped.
    
  """
  @spec count(String.t(), pos_integer(), DateTime.t()) :: :ok
  def count(_key, _n, _now) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Analytics.count/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Totals of `counts/3` per key over the window, largest first.
  """
  @spec count_totals(String.t(), pos_integer(), Date.t()) :: [{String.t(), integer()}]
  def count_totals(_key, _days, _today) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.count_totals/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Per-day values of one counter or a prefix family over the last `days` days
    ending on `today`, as `%{key => %{Date => count}}`. `key` may end in `*` to
    match a prefix (`"level.started.lang:*"`).
    
  """
  @spec counts(String.t(), pos_integer(), Date.t()) :: %{
          required(String.t()) => %{required(Date.t()) => integer()}
        }
  def counts(_key, _days, _today) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Analytics.counts/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    One row per UTC day for the last `days` days ending on `today`, oldest
    first: `%{day, active, new_users, d1, d7, d30}`. A retention rate is `nil`
    when the cohort is empty or the horizon day has not happened yet.
    
  """
  @spec daily_series(pos_integer(), Date.t()) :: [map()]
  def daily_series(_days, _today) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.daily_series/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `summary/0` cached for a few minutes, for the admin index.
  """
  @spec dashboard_stats() :: map()
  def dashboard_stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.dashboard_stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Daily active users on `day` (default: today, UTC).
  """
  @spec dau(Date.t()) :: non_neg_integer()
  def dau(_day) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.dau/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Currency granted and spent per UTC day per ledger `reason` over the last
    `days` days: `[%{day, currency, reason, granted, spent, entries}]`, newest
    first. `granted`/`spent` are positive integers (spent is the absolute
    value of negative deltas). Options: `:currency` to filter.
    
  """
  @spec economy_flow(
          pos_integer(),
          keyword()
        ) :: [map()]
  def economy_flow(_days, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.economy_flow/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `economy_flow/2` collapsed over the window: one row per `{currency,
    reason}` with `granted`, `spent`, `net`, sorted by absolute net.
    
  """
  @spec economy_totals(
          pos_integer(),
          keyword()
        ) :: [map()]
  def economy_totals(_days, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.economy_totals/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Monthly active users: distinct users seen in the 30 days ending on `day`.
  """
  @spec mau(Date.t()) :: non_neg_integer()
  def mau(_day) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.mau/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Accounts created on any UTC day in `from..to` (inclusive).
  """
  @spec new_users(Date.t(), Date.t()) :: non_neg_integer()
  def new_users(_from, _to) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.new_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Distinct users with a completed purchase since `from` (UTC date, inclusive).
  """
  @spec payers_since(Date.t()) :: non_neg_integer()
  def payers_since(_from) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.payers_since/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Records that `user_id` was seen on the UTC day of `now`. Idempotent; the
    common case (already recorded today) is a single cache read. Never raises —
    a missing user (deleted mid-request) is a silent no-op, like the
    `last_seen_at` touch this rides along with.
    
  """
  @spec record_activity(Ecto.UUID.t(), DateTime.t()) :: :ok
  def record_activity(_user_id, _now) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Analytics.record_activity/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every context's live counters in one map, cached for a minute:
    
        %{
          players: %{players_online, players_total, players_offline, players_in_lobbies, players_in_parties},
          activity: %{dau, wau, mau, new_users_1d, new_users_7d, new_users_30d},
          lobbies: %{lobbies_total, by_state, spectators},
          parties: %{parties_active, players_in_parties},
          quests: %{quests_total, completed, claimed},
          signaling: %{rooms_enabled, rooms_active, peers_connected},
          matchmaking: %{queued, queues},
          tournaments: %{tournaments, entries, matches}
        }
    
    Everything in it is safe to show publicly (the stats page is opt-in via
    `:public_stats`); `matchmaking` is the already-public subset. Consumers
    read this rather than calling the contexts, so the same number cannot
    drift between two pages.
    
  """
  @spec snapshot() :: map()
  def snapshot() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.snapshot/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Headline numbers as of `today`: DAU / WAU / MAU, stickiness (DAU ÷ MAU),
    new users in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort
    of the last 60 days that is old enough to have reached
    the horizon, and payer conversion (distinct users with a completed purchase
    in the last 30 days ÷ MAU).
    
  """
  @spec summary(Date.t()) :: map()
  def summary(_today) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.summary/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Weekly active users: distinct users seen in the 7 days ending on `day`.
  """
  @spec wau(Date.t()) :: non_neg_integer()
  def wau(_day) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.wau/1 is a stub - only available at runtime on Gamend"
    end
  end
end
