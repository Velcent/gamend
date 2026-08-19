defmodule Gamend.Modules.StressHook do
  @moduledoc """
  The load-test plugin: the server-side half of `stress/`.

  Two kinds of RPC live here, and the split is the point:

  1. **Micro-benchmarks** (`stress_noop`, `stress_memory_read`,
     `stress_kv_read`, `stress_kv_write`, `stress_kv_write_locked`) — each
     isolates one layer, so subtracting one latency from the next attributes
     cost: noop is pure HTTP→plug→plugin overhead, memory adds an in-memory
     lookup, kv_read adds a cached DB read, kv_write adds a write, and the
     locked variant adds an advisory lock around a read-modify-write.

  2. **Triggers for things a player cannot do over HTTP** (`stress_quest_event`,
     `stress_submit_score`, `stress_credit`, `stress_seed_users`). Quest
     progress, score submission and wallet credits are game-server operations
     by design — there is no player-facing endpoint for them — so a load test
     that wants to exercise those write paths has to come through a plugin,
     exactly as a real game does.

  Everything is namespaced `stress_` so a run cannot be confused with
  `example_hook`'s sample content sharing the same tables.

  Loaded like any other example plugin:

      export GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples

  A real deployment points that at its own directory, so this never loads in
  someone else's production.
  """

  use Gamend.Hooks
  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Economy
  alias Gamend.Friends
  alias Gamend.Hooks
  alias Gamend.KV
  alias Gamend.Leaderboards
  alias Gamend.Lock
  alias Gamend.Quests

  # `:persistent_term`, not ETS: an ETS table belongs to the process that
  # created it, and hook RPCs run in short-lived tasks — a table created inside
  # one dies with it, so the "memory read" it was meant to time degraded into a
  # missing-table rescue that returned nil. `:persistent_term` has no owner and
  # its reads are lock-free; writes are rare here (once per run, in setup),
  # which is the access pattern it is built for.
  @memory_ns :gamend_stress
  @leaderboard_slug "stress_score"
  @quest_key "stress_play"
  @quest_event "stress_play"
  @currency "gold"
  @writer "stress"

  @impl true
  def after_startup do
    Logger.info("[StressHook] after_startup")

    ensure_leaderboard()
    ensure_quest()

    :ok
  end

  # ── Micro-benchmarks ──────────────────────────────────────────────────
  #
  # Ordered cheapest-first; the harness runs them as separate scenarios and
  # reports the deltas.

  @doc "Instant return, no I/O. Measures pure RPC overhead."
  def stress_noop, do: :ok

  @doc "Read from memory. RPC overhead + an in-process-memory lookup, no I/O."
  def stress_memory_read(key) when is_binary(key) do
    :persistent_term.get({@memory_ns, key}, nil)
  end

  @doc "Read a KV entry (cache, then database)."
  def stress_kv_read(key) when is_binary(key) do
    case KV.get(key) do
      {:ok, entry} -> entry.value
      _ -> nil
    end
  end

  @doc """
  Write a KV entry with no lock.

  The unlocked counterpart to `stress_kv_write_locked/1`: the difference
  between the two is what serialization costs, which is the number that
  decides whether a read-modify-write path needs a lock or a cheaper design.
  """
  def stress_kv_write(key) when is_binary(key) do
    KV.put(key, %{"ts" => System.system_time(:millisecond), "writer" => @writer})
    :ok
  end

  @doc "Write a KV entry inside an advisory lock."
  def stress_kv_write_locked(key) when is_binary(key) do
    # `resource_id` must be a binary: the previous version passed
    # `:erlang.phash2(key)` (an integer), which matched no clause of
    # `Lock.serialize/3` — so this RPC returned 400 and the "locked write"
    # scenario was timing an error path, not a lock.
    # The return value is deliberately not inspected: the SDK stub for
    # `Lock.serialize/3` infers `nil`, so any `{:ok, _}` match on it — the usage
    # its own docs show — warns as unreachable. Whether the write actually
    # happened is checked where it is more meaningful anyway: the harness reads
    # the key back through `GET /kv/:key` and asserts this writer stamped it.
    _result =
      Lock.serialize("stress", key, fn ->
        KV.put(key, %{"ts" => System.system_time(:millisecond), "writer" => @writer})
      end)

    :ok
  end

  @doc """
  Echo back a payload of `size` bytes.

  Isolates serialization and transport cost from the work behind it: run it at
  a few sizes and the slope is what a byte costs on this box.
  """
  def stress_echo(size) when is_integer(size) and size >= 0 and size <= 65_536 do
    String.duplicate("x", size)
  end

  @doc "Idempotent: seed one key in memory and in KV, for the read benchmarks."
  def stress_setup(key) when is_binary(key) do
    :persistent_term.put({@memory_ns, key}, %{"seeded" => true})
    KV.put(key, %{"seeded" => true})
    :ok
  end

  # ── Triggers for server-owned writes ──────────────────────────────────

  @doc """
  Report a quest event for the calling user and return how many quests moved.

  Wired to the `stress_play` quest created at startup, which is `reset:
  "repeat"` with a target of 1 — so every call completes an objective and
  leaves something claimable. That is the heaviest quest path on purpose.
  """
  def stress_quest_event(amount \\ 1) when is_integer(amount) and amount > 0 do
    # Destructured, not guarded: every RPC here is reached through an
    # authenticated request, so a missing caller is a harness bug and should
    # crash loudly rather than return an error the load test would average away.
    %{id: user_id} = Hooks.caller_user()

    {:ok, advanced} = Quests.report_event(user_id, @quest_event, amount, %{})
    %{"advanced" => length(advanced)}
  end

  @doc "Submit a score for the calling user on the stress leaderboard."
  def stress_submit_score(score) when is_integer(score) do
    %{id: user_id} = Hooks.caller_user()
    %{id: board_id} = Leaderboards.get_active_leaderboard_by_slug(@leaderboard_slug)

    Leaderboards.submit_score(board_id, user_id, score)
    %{"leaderboard_id" => board_id}
  end

  @doc "Credit the calling user's wallet. A locked read-modify-write."
  def stress_credit(amount) when is_integer(amount) and amount > 0 do
    %{id: user_id} = Hooks.caller_user()

    {:ok, balance} = Economy.grant(user_id, @currency, amount, reason: "stress")
    %{"balance" => balance}
  end

  @doc """
  Sample live socket and channel processes and report where their memory is.

  RSS cannot answer "what costs 300 KB per connected player" on a laptop that is
  also running the load generator and the database — the run-to-run spread is
  wider than the effect. This reads the processes themselves instead:
  `Process.info(:memory)` is exact, and `:erts_debug.size/1` prices an
  individual term in the socket's assigns, so a retained memo can be told apart
  from a heap that merely grew during join.

  Returns words and bytes for the largest assigns entries, so the answer names
  the key rather than the total.
  """
  def stress_socket_memory(sample \\ 25) when is_integer(sample) and sample > 0 do
    by_module = Enum.group_by(Process.list(), &initial_module/1)

    # Channels are identifiable by module name. WebSocket transports are NOT:
    # Bandit serves HTTP and WebSocket connections from the same
    # `DelegatingHandler`, so matching the module name samples a mix of the two
    # and the median moves with whatever ratio of plain HTTP requests happens to
    # be in flight. The app's own registry knows which sockets are websockets,
    # so ask it — resolved at runtime, since a plugin cannot see the web app at
    # compile time.
    channels = pick(by_module, &String.ends_with?(&1, "Channel"), sample)
    transports = ws_transports(sample)

    %{
      "channel" => summarize_processes(channels),
      "transport" => summarize_processes(transports),
      "channel_assigns" => summarize_assigns(channels),
      # What the node is actually made of, so a miss above is diagnosable
      # rather than silent.
      "top_modules" =>
        by_module
        |> Enum.map(fn {mod, pids} -> {inspect(mod), length(pids)} end)
        |> Enum.sort_by(&(-elem(&1, 1)))
        |> Enum.take(8)
        |> Map.new()
    }
  end

  defp ws_transports(sample) do
    tracker = Module.concat(["GamendWeb", "ConnectionTracker"])

    if Code.ensure_loaded?(tracker) do
      # Called through a variable rather than `apply/3` (same runtime dispatch,
      # no compile-time dependency on the web app, and credo is happy).
      tracker.list_registered(:ws_socket)
      |> Enum.map(fn {pid, _meta} -> pid end)
      |> Enum.filter(&Process.alive?/1)
      |> Enum.take(sample)
    else
      []
    end
  end

  defp pick(by_module, matches?, sample) do
    by_module
    |> Enum.filter(fn {mod, _pids} -> matches?.(inspect(mod)) end)
    |> Enum.flat_map(fn {_mod, pids} -> pids end)
    |> Enum.take(sample)
  end

  # Grouped by `$initial_call` rather than by a registry: this plugin cannot see
  # the web app's modules at compile time, and OTP introspection needs nothing
  # from it.
  defp initial_module(pid) do
    with {:dictionary, dict} <- Process.info(pid, :dictionary),
         {mod, _fun, _arity} <- Keyword.get(dict, :"$initial_call") do
      mod
    else
      _ -> :unknown
    end
  end

  defp summarize_processes([]), do: %{"count" => 0}

  defp summarize_processes(pids) do
    mems =
      pids
      |> Enum.map(fn pid ->
        case Process.info(pid, :memory) do
          {:memory, bytes} -> bytes
          _dead -> 0
        end
      end)
      |> Enum.reject(&(&1 == 0))
      |> Enum.sort()

    %{
      "count" => length(mems),
      "median_kb" => kb(median(mems)),
      "min_kb" => kb(List.first(mems)),
      "max_kb" => kb(List.last(mems))
    }
  end

  # `:erts_debug.size/1` counts words the term occupies, accounting for sharing
  # inside the term — which is what decides whether dropping an assign would
  # actually free anything.
  defp summarize_assigns([]), do: %{}

  defp summarize_assigns(pids) do
    pids
    |> Enum.flat_map(fn pid ->
      case safe_state(pid) do
        %{assigns: assigns} when is_map(assigns) ->
          Enum.map(assigns, fn {key, value} ->
            {key, :erts_debug.size(value) * :erlang.system_info(:wordsize)}
          end)

        _other ->
          []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, sizes} -> {to_string(key), kb(median(Enum.sort(sizes)))} end)
  end

  defp safe_state(pid) do
    :sys.get_state(pid, 2_000)
  catch
    _kind, _reason -> nil
  end

  defp median([]), do: 0
  defp median(sorted), do: Enum.at(sorted, div(length(sorted), 2))

  defp kb(bytes), do: Float.round(bytes / 1024, 1)

  @doc """
  Count database queries over a window, grouped by source.

  A page that is fast on SQLite and slow on Postgres is usually not doing
  *expensive* work — it is doing many small queries, which cost microseconds
  against a local file and a round trip over a socket. Counting them is the only
  way to tell those two apart.

  `stress_query_probe("start")` attaches a telemetry handler;
  `stress_query_probe("read")` detaches and reports what it saw.
  """
  def stress_query_probe(action) when action in ["start", "read"] do
    case action do
      "start" -> start_query_probe()
      "read" -> read_query_probe()
    end
  end

  @probe_key {__MODULE__, :query_probe}
  @probe_handler :stress_hook_query_probe

  defp start_query_probe do
    :persistent_term.put(@probe_key, :counters.new(1, [:write_concurrency]))
    _ = :telemetry.detach(@probe_handler)

    :telemetry.attach(
      @probe_handler,
      [:gamend, :repo, :query],
      &__MODULE__.handle_query_event/4,
      nil
    )

    %{"probe" => "started"}
  end

  @doc false
  def handle_query_event(_event, _measurements, metadata, _config) do
    case :persistent_term.get(@probe_key, nil) do
      nil ->
        :ok

      ref ->
        :counters.add(ref, 1, 1)
        # A bounded ring of sources rather than every query: a diagnostic must
        # not become a memory leak on a busy node.
        slot = rem(:counters.get(ref, 1), 200)
        :persistent_term.put({__MODULE__, :query_sample, slot}, metadata[:source])
        :ok
    end
  end

  defp read_query_probe do
    count =
      case :persistent_term.get(@probe_key, nil) do
        nil -> 0
        ref -> :counters.get(ref, 1)
      end

    sources =
      0..199
      |> Enum.flat_map(fn i ->
        case :persistent_term.get({__MODULE__, :query_sample, i}, nil) do
          nil -> []
          source -> [to_string(source)]
        end
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(&(-elem(&1, 1)))
      |> Enum.take(8)
      |> Map.new()

    _ = :telemetry.detach(@probe_handler)
    _ = :persistent_term.erase(@probe_key)
    Enum.each(0..199, &:persistent_term.erase({__MODULE__, :query_sample, &1}))

    %{"queries" => count, "top_sources" => sources}
  end

  @doc """
  Where the node's memory actually is: BEAM categories, the largest ETS tables,
  and how much of it the allocators are holding but not using.

  `:erlang.memory/0` reports what the VM has *allocated to purposes*, which is
  reliably far less than RSS — the difference is allocator slack, and knowing
  which of the two a number came from is the difference between "the cache is
  huge" and "the allocator has not returned pages". Both are reported here.
  """
  def stress_memory_breakdown(top \\ 10) when is_integer(top) and top > 0 do
    mem = Map.new(:erlang.memory())
    word = :erlang.system_info(:wordsize)

    tables =
      :ets.all()
      |> Enum.map(fn t ->
        {safe_ets(t, :name), (safe_ets(t, :memory) || 0) * word, safe_ets(t, :size) || 0}
      end)
      |> Enum.sort_by(fn {_n, bytes, _rows} -> -bytes end)
      |> Enum.take(top)
      |> Enum.map(fn {name, bytes, rows} ->
        %{"table" => inspect(name), "mb" => mb(bytes), "rows" => rows}
      end)

    %{
      "beam_mb" =>
        Map.new(mem, fn {k, v} -> {to_string(k), mb(v)} end)
        |> Map.take(~w(total processes processes_used system atom binary code ets)),
      "ets_tables" => tables,
      "process_count" => :erlang.system_info(:process_count),
      "port_count" => :erlang.system_info(:port_count),
      # RSS as the OS sees it, so the allocator gap is visible rather than
      # inferred. `:erlang.memory(:total)` never includes it.
      "rss_mb" => rss_mb(),
      "schedulers" => :erlang.system_info(:schedulers_online),
      # Socket buffers live in the emulator's binary space, one per connection,
      # and are the usual explanation for binary memory that scales with the
      # connection count but not with traffic.
      "socket_buffers" => socket_buffers()
    }
  end

  defp socket_buffers do
    Port.list()
    |> Enum.filter(fn port ->
      match?({:name, ~c"tcp_inet"}, Port.info(port, :name))
    end)
    |> Enum.take(6)
    |> Enum.flat_map(fn port ->
      case :inet.getopts(port, [:buffer, :recbuf, :sndbuf]) do
        {:ok, opts} -> [Map.new(opts, fn {k, v} -> {to_string(k), v} end)]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp safe_ets(table, key) do
    :ets.info(table, key)
  catch
    _kind, _reason -> nil
  end

  defp rss_mb do
    case :os.type() do
      {:unix, _} ->
        pid = :os.getpid()

        case System.cmd("ps", ["-o", "rss=", "-p", to_string(pid)]) do
          {out, 0} ->
            out |> String.trim() |> String.to_integer() |> Kernel./(1024) |> Float.round(1)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp mb(bytes), do: Float.round(bytes / 1_048_576, 1)

  @doc """
  Give the calling user `count` accepted friendships, server-side.

  `ws_idle.js` varies friend count because `UserChannel`'s join memoises the
  caller's friend list on the socket's heap for the socket's whole life — so
  per-socket memory scales with it, and a memory-per-socket figure taken at one
  friend count says nothing about a player with two hundred friends.

  Done here rather than over HTTP because the client-side handshake is two
  requests per friend plus a second logged-in user: at five thousand sockets
  that is the load test rather than its setup. Friends come from a shared pool
  of `stress_friend_<i>` device users created on demand, so the pool is made
  once and every socket after that costs `count` inserts.

  Returns `%{"friends" => n}` — the caller's total, not the number added.
  """
  def stress_seed_friends(count) when is_integer(count) and count >= 0 and count <= 1_000 do
    %{id: user_id} = Hooks.caller_user()

    Enum.each(1..max(count, 1)//1, fn i ->
      %{id: pool_id} = ensure_pool_user(i)

      if pool_id != user_id, do: befriend(user_id, pool_id)
    end)

    %{"friends" => Friends.count_friends_for_user(user_id)}
  end

  # Device users, not email ones: no password to hash, so a pool of a few
  # hundred costs a few hundred inserts rather than minutes of bcrypt.
  # `find_or_create_from_device/1` is already idempotent, which is what makes
  # the pool shared across every socket instead of per-socket.
  defp ensure_pool_user(i) do
    {:ok, user} = Accounts.find_or_create_from_device("stress_friend_#{i}")
    user
  end

  # The request's return value is looked up again rather than destructured: the
  # SDK stub for `create_request/2` infers `{:ok, nil}`, so matching the
  # friendship it really returns warns as unreachable. `get_by_pair/2` also
  # covers the repeat case for free — on a second run the pair already exists
  # and is already accepted, and this leaves it alone.
  defp befriend(user_id, other_id) do
    Friends.create_request(user_id, other_id)

    case Friends.get_by_pair(user_id, other_id) do
      %{id: id, status: "pending"} -> Friends.accept_friend_request(id, %User{id: other_id})
      _accepted_or_missing -> :ok
    end
  end

  @doc """
  Create `count` email+password users named `<prefix><i>@stress.local`.

  Two steps, not one: `register_user/1` composes only the email and username
  changesets — this product registers by magic link and sets a password later —
  so a password passed to it is silently dropped and the row lands with a NULL
  hash. `update_user_password/2` is what actually casts it. Without that second
  call every seeded user answers 401 and `auth_email.js` times
  `Bcrypt.no_user_verify/0` instead of a real login.

  No mailer and no confirmation token are involved: `SessionController` only
  checks `Accounts.user_activated?/1`, and activation is off by default.

  Existing users are skipped, so this is safe to call before every run. It
  cannot repair one: `hashed_password` is deliberately absent from the SDK's
  `User` struct, so a plugin cannot tell a passwordless row from a good one.
  A database seeded before this two-step fix needs a fresh `EMAIL_PREFIX`
  (or a wiped database, which is what the matrix does between cells).

  Returns `%{"created" => n, "existing" => n}`.
  """
  def stress_seed_users(count, prefix, password)
      when is_integer(count) and count > 0 and count <= 10_000 and is_binary(prefix) and
             is_binary(password) do
    Enum.reduce(1..count, %{"created" => 0, "existing" => 0}, fn i, acc ->
      email = "#{prefix}#{i}@stress.local"

      # `match?/2` rather than a `case`: a concurrent seeder losing the unique
      # index is an ordinary outcome here, and counting it with a boolean keeps
      # the tolerance without an unreachable-clause warning.
      created? =
        is_nil(Accounts.get_user_by_email(email)) and
          match?({:ok, _user}, create_stress_user(email, password))

      Map.update!(acc, if(created?, do: "created", else: "existing"), &(&1 + 1))
    end)
  end

  defp create_stress_user(email, password) do
    with {:ok, user} <- Accounts.register_user(%{email: email}) do
      set_password(user, password)
      {:ok, user}
    end
  end

  defp set_password(user, password) do
    Accounts.update_user_password(user, %{password: password, password_confirmation: password})
  end

  # ── Setup ─────────────────────────────────────────────────────────────

  defp ensure_leaderboard do
    case Leaderboards.get_active_leaderboard_by_slug(@leaderboard_slug) do
      nil ->
        Leaderboards.create_leaderboard(%{
          slug: @leaderboard_slug,
          title: "Stress scores",
          description: "Scores submitted by the load-test harness.",
          sort_order: :desc,
          operator: :best
        })

      _existing ->
        :ok
    end
  end

  defp ensure_quest do
    attrs = %{
      key: @quest_key,
      title: "Stress play",
      description: "Advances once per stress_quest_event call.",
      category: "Stress",
      reset: "repeat",
      objectives: [%{event: @quest_event, target: 1}],
      rewards: [%{type: "currency", code: @currency, amount: 1}]
    }

    case Quests.get_quest_by_key(@quest_key) do
      nil -> Quests.create_quest(attrs)
      quest -> Quests.update_quest(quest, Map.delete(attrs, :key))
    end
  end
end
