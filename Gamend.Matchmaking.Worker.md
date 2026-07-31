# `Gamend.Matchmaking.Worker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/matchmaking/worker.ex#L1)

Periodic driver for the matchmaking sweep.

Runs on every node as a plain local GenServer; the sweep body is serialized
cluster-wide via `Gamend.Lock`, so only one node forms matches per tick
and a node joining or leaving never breaks supervision (a `:global` name
would fail the second node's supervisor start with `:already_started`).

Each tick, inside the lock: prune tickets of users that went offline, then
group the queued tickets by `match_params` and create a hidden lobby per
formed match. Broadcasts go out after the lock's transaction commits.

    config :gamend_core, Gamend.Matchmaking.Worker,
      enabled: true               # set false to leave the worker idle

Disabled in test configs, like the other periodic workers: the tick owns no
sandbox connection, so it only produces "database is locked" noise. Tests
call `sweep/0` directly.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

# `sweep`

```elixir
@spec sweep() :: non_neg_integer()
```

One matchmaking sweep. Public so tests and consoles can run a tick on
demand without waiting for the timer.

Two phases: inside the cluster lock, prune offline players and *claim* the
formed matches (an atomic queued→matched flip). Outside the lock, create a
lobby per claimed match — lobby creation fires hooks and broadcasts, which
must never run inside a transaction. Claimed tickets are invisible to other
sweepers, and a failed lobby simply requeues them for the next tick.

Returns the number of lobbies created.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
