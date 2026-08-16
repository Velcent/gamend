defmodule Gamend.Analytics do
  @moduledoc """
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
  """

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.DailyCount
  alias Gamend.Cache
  alias Gamend.Economy.LedgerEntry
  alias Gamend.Payments.Purchase
  alias Gamend.Repo

  @stats_cache_ttl_ms :timer.minutes(5)
  @snapshot_cache_ttl_ms :timer.minutes(1)
  # A user's "already recorded today" marker. Longer than a day so it survives
  # into tomorrow, when the day comparison (not the TTL) triggers the next row.
  @seen_cache_ttl_ms :timer.hours(30)
  # The dashboard's daily table.
  @series_days 30
  # Cohorts considered for the headline D1/D7/D30 rates.
  @cohort_window_days 60
  @horizons [1, 7, 30]

  @type rate :: float() | nil

  # -- snapshot ------------------------------------------------------------------

  @doc """
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
  def snapshot do
    Cache.cached({:analytics, :snapshot}, [ttl: @snapshot_cache_ttl_ms], fn ->
      today = Date.utc_today()
      mm = Gamend.Matchmaking.stats()

      %{
        players: Accounts.player_stats(),
        activity: %{
          dau: dau(today),
          wau: wau(today),
          mau: mau(today),
          new_users_1d: new_users(today, today),
          new_users_7d: new_users(Date.add(today, -6), today),
          new_users_30d: new_users(Date.add(today, -29), today)
        },
        lobbies: Gamend.Lobbies.stats(),
        parties: Gamend.Parties.stats(),
        quests: Gamend.Quests.stats(),
        signaling: Gamend.Signaling.stats(),
        matchmaking: Map.take(mm, [:queued, :queues]),
        tournaments: Gamend.Tournaments.stats()
      }
    end)
  end

  @doc "Accounts created on any UTC day in `from..to` (inclusive)."
  @spec new_users(Date.t(), Date.t()) :: non_neg_integer()
  def new_users(%Date{} = from, %Date{} = to) do
    start = start_of_day(from)
    stop = start_of_day(Date.add(to, 1))

    Repo.one(
      from u in User,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        select: count(u.id)
    ) || 0
  end

  # -- daily counters --------------------------------------------------------------

  @doc """
  Adds `n` to the counter `key` for the UTC day of `now`. One atomic
  upsert-increment; safe to call from hot paths that already write (a level
  end, a purchase), not from paths that otherwise only read.

  Keys are dotted, game-owned strings up to #{DailyCount.key_max()} chars;
  put a dimension after a colon (`"level.started.lang:ja"`) so `counts/2`
  can pull a whole family by prefix. Never raises; a bad key is dropped.
  """
  @spec count(String.t(), pos_integer(), DateTime.t()) :: :ok
  def count(key, n \\ 1, now \\ DateTime.utc_now())

  def count(key, n, %DateTime{} = now)
      when is_binary(key) and key != "" and byte_size(key) <= 128 and is_integer(n) and n > 0 do
    day = DateTime.to_date(now)
    on_conflict = from(c in DailyCount, update: [inc: [count: ^n]])

    _ =
      %DailyCount{}
      |> DailyCount.changeset(%{day: day, key: key, count: n})
      |> Repo.insert(on_conflict: on_conflict, conflict_target: [:day, :key])

    :ok
  rescue
    Ecto.ConstraintError -> :ok
  end

  def count(_key, _n, _now), do: :ok

  @doc """
  Per-day values of one counter or a prefix family over the last `days` days
  ending on `today`, as `%{key => %{Date => count}}`. `key` may end in `*` to
  match a prefix (`"level.started.lang:*"`).
  """
  @spec counts(String.t(), pos_integer(), Date.t()) :: %{String.t() => %{Date.t() => integer()}}
  def counts(key, days \\ 7, today \\ Date.utc_today())
      when is_binary(key) and is_integer(days) and days > 0 do
    first = Date.add(today, -(days - 1))
    base = from(c in DailyCount, where: c.day >= ^first and c.day <= ^today)

    query =
      case String.split_at(key, -1) do
        {prefix, "*"} ->
          pattern = Repo.escape_like(prefix) <> "%"
          from(c in base, where: fragment("? LIKE ? ESCAPE '\\'", c.key, ^pattern))

        _ ->
          from(c in base, where: c.key == ^key)
      end

    query
    |> select([c], {c.key, c.day, c.count})
    |> Repo.all()
    |> Enum.group_by(fn {k, _, _} -> k end, fn {_, day, n} -> {to_date(day), n} end)
    |> Map.new(fn {k, pairs} -> {k, Map.new(pairs)} end)
  end

  @doc "Totals of `counts/3` per key over the window, largest first."
  @spec count_totals(String.t(), pos_integer(), Date.t()) :: [{String.t(), integer()}]
  def count_totals(key, days \\ 7, today \\ Date.utc_today()) do
    key
    |> counts(days, today)
    |> Enum.map(fn {k, by_day} -> {k, by_day |> Map.values() |> Enum.sum()} end)
    |> Enum.sort_by(fn {_, n} -> -n end)
  end

  # -- economy flow ----------------------------------------------------------------

  @doc """
  Currency granted and spent per UTC day per ledger `reason` over the last
  `days` days: `[%{day, currency, reason, granted, spent, entries}]`, newest
  first. `granted`/`spent` are positive integers (spent is the absolute
  value of negative deltas). Options: `:currency` to filter.
  """
  @spec economy_flow(pos_integer(), keyword()) :: [map()]
  def economy_flow(days \\ 7, opts \\ []) when is_integer(days) and days > 0 do
    today = Keyword.get(opts, :today, Date.utc_today())
    start = start_of_day(Date.add(today, -(days - 1)))
    stop = start_of_day(Date.add(today, 1))
    currency = Keyword.get(opts, :currency)

    base =
      from(e in LedgerEntry,
        where: e.inserted_at >= ^start and e.inserted_at < ^stop,
        group_by: [fragment("date(?)", e.inserted_at), e.currency, e.reason],
        select: %{
          day: fragment("date(?)", e.inserted_at),
          currency: e.currency,
          reason: e.reason,
          granted: sum(fragment("CASE WHEN ? > 0 THEN ? ELSE 0 END", e.delta, e.delta)),
          spent: sum(fragment("CASE WHEN ? < 0 THEN -? ELSE 0 END", e.delta, e.delta)),
          entries: count(e.id)
        }
      )

    query = if currency, do: from(e in base, where: e.currency == ^currency), else: base

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | day: to_date(row.day), granted: to_int(row.granted), spent: to_int(row.spent)}
    end)
    |> Enum.sort_by(fn r -> {Date.to_iso8601(r.day), r.currency, r.reason} end, :desc)
  end

  @doc """
  `economy_flow/2` collapsed over the window: one row per `{currency,
  reason}` with `granted`, `spent`, `net`, sorted by absolute net.
  """
  @spec economy_totals(pos_integer(), keyword()) :: [map()]
  def economy_totals(days \\ 7, opts \\ []) do
    days
    |> economy_flow(opts)
    |> Enum.group_by(&{&1.currency, &1.reason})
    |> Enum.map(fn {{currency, reason}, rows} ->
      granted = Enum.sum_by(rows, & &1.granted)
      spent = Enum.sum_by(rows, & &1.spent)

      %{
        currency: currency,
        reason: reason,
        granted: granted,
        spent: spent,
        net: granted - spent,
        entries: Enum.sum_by(rows, & &1.entries)
      }
    end)
    |> Enum.sort_by(&{&1.currency, -abs(&1.net)})
  end

  # -- recording ---------------------------------------------------------------

  @doc """
  Records that `user_id` was seen on the UTC day of `now`. Idempotent; the
  common case (already recorded today) is a single cache read. Never raises —
  a missing user (deleted mid-request) is a silent no-op, like the
  `last_seen_at` touch this rides along with.
  """
  @spec record_activity(Ecto.UUID.t(), DateTime.t()) :: :ok
  def record_activity(user_id, now \\ DateTime.utc_now())

  def record_activity(user_id, %DateTime{} = now) when is_binary(user_id) do
    day = DateTime.to_date(now)
    key = seen_key(user_id)

    case Cache.get!(key) do
      ^day ->
        :ok

      _ ->
        _ = insert_day(user_id, day)
        _ = Cache.put(key, day, ttl: @seen_cache_ttl_ms)
        :ok
    end
  end

  def record_activity(_user_id, _now), do: :ok

  defp insert_day(user_id, day) do
    %ActivityDay{}
    |> ActivityDay.changeset(%{user_id: user_id, day: day})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :day])
  rescue
    # A user deleted between the touch and this insert. Postgres names the
    # violated constraint and the changeset turns it into `{:error, _}`;
    # SQLite reports it anonymously, which Ecto can only raise.
    Ecto.ConstraintError -> {:error, :constraint}
  end

  defp seen_key(user_id), do: {:analytics, :seen_day, user_id}

  # -- active users --------------------------------------------------------------

  @doc "Distinct users seen on any day in `from..to` (inclusive, UTC dates)."
  @spec active_users(Date.t(), Date.t()) :: non_neg_integer()
  def active_users(%Date{} = from, %Date{} = to) do
    Repo.one(
      from a in ActivityDay,
        where: a.day >= ^from and a.day <= ^to,
        select: count(a.user_id, :distinct)
    ) || 0
  end

  @doc "Daily active users on `day` (default: today, UTC)."
  @spec dau(Date.t()) :: non_neg_integer()
  def dau(day \\ Date.utc_today()), do: active_users(day, day)

  @doc "Weekly active users: distinct users seen in the 7 days ending on `day`."
  @spec wau(Date.t()) :: non_neg_integer()
  def wau(day \\ Date.utc_today()), do: active_users(Date.add(day, -6), day)

  @doc "Monthly active users: distinct users seen in the 30 days ending on `day`."
  @spec mau(Date.t()) :: non_neg_integer()
  def mau(day \\ Date.utc_today()), do: active_users(Date.add(day, -29), day)

  # -- cohorts -------------------------------------------------------------------

  @doc """
  One row per UTC day for the last `days` days ending on `today`, oldest
  first: `%{day, active, new_users, d1, d7, d30}`. A retention rate is `nil`
  when the cohort is empty or the horizon day has not happened yet.
  """
  @spec daily_series(pos_integer(), Date.t()) :: [map()]
  def daily_series(days \\ @series_days, today \\ Date.utc_today())
      when is_integer(days) and days > 0 do
    first = Date.add(today, -(days - 1))
    active = active_counts_by_day(first, today)
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today)

    for offset <- 0..(days - 1) do
      day = Date.add(first, offset)
      size = Map.get(sizes, day, 0)

      %{
        day: day,
        active: Map.get(active, day, 0),
        new_users: size,
        d1: cohort_rate(retained, day, 1, size, today),
        d7: cohort_rate(retained, day, 7, size, today),
        d30: cohort_rate(retained, day, 30, size, today)
      }
    end
  end

  @doc """
  Headline numbers as of `today`: DAU / WAU / MAU, stickiness (DAU ÷ MAU),
  new users in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort
  of the last #{@cohort_window_days} days that is old enough to have reached
  the horizon, and payer conversion (distinct users with a completed purchase
  in the last 30 days ÷ MAU).
  """
  @spec summary(Date.t()) :: map()
  def summary(today \\ Date.utc_today()) do
    dau = dau(today)
    mau = mau(today)
    first = Date.add(today, -(@cohort_window_days - 1))
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today)

    pooled =
      Map.new(@horizons, fn n ->
        {n, pooled_rate(sizes, retained, n, today)}
      end)

    payers = payers_since(Date.add(today, -29))

    %{
      day: today,
      dau: dau,
      wau: wau(today),
      mau: mau,
      stickiness: ratio(dau, mau),
      new_users_7d: sum_sizes(sizes, Date.add(today, -6), today),
      new_users_30d: sum_sizes(sizes, Date.add(today, -29), today),
      d1: pooled[1],
      d7: pooled[7],
      d30: pooled[30],
      payers_30d: payers,
      conversion_30d: ratio(payers, mau)
    }
  end

  @doc "`summary/0` cached for a few minutes, for the admin index."
  @spec dashboard_stats() :: map()
  def dashboard_stats do
    Cache.cached({:analytics, :dashboard_stats}, [ttl: @stats_cache_ttl_ms], fn ->
      summary()
    end)
  end

  @doc "Distinct users with a completed purchase since `from` (UTC date, inclusive)."
  @spec payers_since(Date.t()) :: non_neg_integer()
  def payers_since(%Date{} = from) do
    start = start_of_day(from)

    Repo.one(
      from p in Purchase,
        where: p.status == "completed" and p.inserted_at >= ^start,
        select: count(p.user_id, :distinct)
    ) || 0
  end

  # Cohort sizes (users registered per UTC day) and retained counts
  # (`{cohort_day, seen_day} => users`) for cohorts registered in `first..today`.
  # One grouped query each; the join output is at most days² rows, so the
  # per-horizon lookups happen in Elixir rather than as N more queries.
  defp cohort_snapshot(first, today) do
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    sizes =
      from(u in User,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        group_by: fragment("date(?)", u.inserted_at),
        select: {fragment("date(?)", u.inserted_at), count(u.id)}
      )
      |> Repo.all()
      |> Map.new(fn {day, n} -> {to_date(day), n} end)

    retained =
      from(a in ActivityDay,
        join: u in User,
        on: u.id == a.user_id,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        where: a.day >= ^first and a.day <= ^today,
        group_by: [fragment("date(?)", u.inserted_at), a.day],
        select: {fragment("date(?)", u.inserted_at), a.day, count(a.user_id)}
      )
      |> Repo.all()
      |> Map.new(fn {cohort, day, n} -> {{to_date(cohort), to_date(day)}, n} end)

    %{sizes: sizes, retained: retained}
  end

  defp active_counts_by_day(first, today) do
    from(a in ActivityDay,
      where: a.day >= ^first and a.day <= ^today,
      group_by: a.day,
      select: {a.day, count(a.user_id)}
    )
    |> Repo.all()
    |> Map.new(fn {day, n} -> {to_date(day), n} end)
  end

  # Retention of one cohort at horizon `n`: nil until day+n has happened.
  defp cohort_rate(_retained, _day, _n, 0, _today), do: nil

  defp cohort_rate(retained, day, n, size, today) do
    target = Date.add(day, n)

    if Date.compare(target, today) == :gt,
      do: nil,
      else: Map.get(retained, {day, target}, 0) / size
  end

  # Sum of retained over sum of cohort sizes, cohorts old enough only. Pooling
  # (rather than averaging per-cohort rates) so a day with two sign-ups does
  # not weigh as much as a day with two hundred.
  defp pooled_rate(sizes, retained, n, today) do
    latest = Date.add(today, -n)

    {kept, total} =
      Enum.reduce(sizes, {0, 0}, fn {day, size}, {kept, total} ->
        if Date.compare(day, latest) == :gt,
          do: {kept, total},
          else: {kept + Map.get(retained, {day, Date.add(day, n)}, 0), total + size}
      end)

    ratio(kept, total)
  end

  defp sum_sizes(sizes, from, to) do
    sizes
    |> Enum.filter(fn {day, _} ->
      Date.compare(day, from) != :lt and Date.compare(day, to) != :gt
    end)
    |> Enum.map(fn {_, n} -> n end)
    |> Enum.sum()
  end

  defp ratio(_num, 0), do: nil
  defp ratio(num, den), do: num / den

  defp start_of_day(%Date{} = day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")

  # `date(...)` comes back as a Date on Postgres and as "YYYY-MM-DD" on SQLite.
  defp to_date(%Date{} = date), do: date
  defp to_date(text) when is_binary(text), do: Date.from_iso8601!(text)

  # `sum(bigint)` is a Decimal on Postgres and an integer on SQLite.
  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(f) when is_float(f), do: round(f)
end
