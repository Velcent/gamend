---
icon: hero-chart-bar
---

# Performance

Measured numbers, not estimates. Everything below comes from the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress), which you can
run against your own deployment — see [Load Testing](load-testing).

## What it does, per feature

Three units, because three different things are worth knowing. Everything the
harness measures is here.

**Single operations** — one request each, so these compare directly:

| operation | SQLite | PostgreSQL | median |
|---|---:|---:|---:|
| KV read | 17,612/s | 11,980/s | 1.4 ms |
| cached read (`GET /me`) | 17,489/s | 16,422/s | 1.4 ms |
| plugin call, no database | 16,372/s | 12,616/s | 1.5 ms |
| token refresh | 15,677/s | 12,964/s | 1.5 ms |
| **write** | **4,266/s** | 5,472/s | 6.8 ms |
| **write inside a lock** | **966/s** | 1,574/s | p99 261 ms |
| email login (bcrypt) | 12/s | 11/s | 1,365 ms |

Every read costs the same, whether it goes through a plugin or not — the hook
layer adds nothing measurable. Writes are ~4x a read, a locked write ~4x again.
Email login is bcrypt: CPU-bound by design, paid once per session.

**Flows** — a real action is usually several requests, so these are flows per
second with the request count each one spends:

| flow | steps | SQLite | PostgreSQL |
|---|---:|---:|---:|
| profile update + read back | 2 | 1,552/s | 2,454/s |
| notification send + list + clear | 3 | 803/s | 1,869/s |
| device signup + verify | 2 | 792/s | 1,539/s |
| wallet credit + wallet/ledger/inventory | 4 | 654/s | 1,336/s |
| leaderboard submit + 3 reads | 4 | 509/s | 999/s |
| group create + read + members + leave | 5 | 403/s | 996/s |
| lobby create + state change + leave | 5 | 279/s | 635/s |
| chat send + delivery over a socket | 3 | 298/s | 679/s |
| quest event + list + claim | 4 | 222/s | 323/s |
| friend request + accept + both read back | 7 | 134/s | 250/s |
| web page render | 4 | 48/s | 44/s |

**Waits** — for realtime, the number that matters is how long a player waits,
end to end: the HTTP write, the database, PubSub, the per-socket serialize, and
the frame on the wire.

| what the player waits for | SQLite | PostgreSQL |
|---|---:|---:|
| chat message to reach the other players | 17 ms | 6 ms |
| lobby state change to reach the lobby | 16 ms | 7 ms |
| matchmaking to find a match | 66 ms | 66 ms |

Idle sockets are held at ~24 KB of process memory each, flat regardless of how
much the account has in it.

## Why the two databases are closer than you would expect

On writes, SQLite (4,266/s) and PostgreSQL (5,472/s) look almost level, which is
not what a single-writer file database against a real server should look like.
They are not doing the same work.

gamend runs SQLite with `synchronous=NORMAL` in WAL mode: a commit is a write to
the log, and the `fsync` is deferred to a checkpoint. PostgreSQL was measured on
its default `synchronous_commit=on`, which flushes every commit to disk before
returning. Measured directly on the same machine, serial commits:

| PostgreSQL | commits/s |
|---|---:|
| `synchronous_commit=on` (default) | 3,096/s |
| `synchronous_commit=off` | 7,448/s |

So **PostgreSQL is doing strictly more durability work per write and is still
ahead**. Equalise the durability and its ceiling is roughly 2.4x higher. The
per-write gap you can see in the table is the fsync, not the database.

That measurement is why gamend now defaults PostgreSQL to `synchronous_commit=off`
— the numbers in the comparison table above are from before that change, and
understate PostgreSQL accordingly.

### `synchronous_commit` is `off` by default

gamend ships `synchronous_commit=off` on PostgreSQL, and exempts payments from
it automatically. You do not have to do anything to get the numbers below; this
section is here so you know what you are running, and how to opt out.

The reason gamend can default this way and PostgreSQL cannot is that gamend
knows which of its writes are money. A general-purpose database has to assume
every commit is the important one.

What the setting actually risks is narrower than it sounds. `synchronous_commit
= off` lets a commit return before its log entry reaches the disk. The database
stays **consistent** — this is not `fsync = off`, which can corrupt — and a
PostgreSQL crash or a clean shutdown loses nothing. The exposure is an *operating
system* crash or power loss, and it is bounded: at most about three times
`wal_writer_delay`, so **roughly 600 ms of committed transactions** on the
default 200 ms.

Losing 600 ms of quest progress, positions, chat or lobby state in a power cut
is a trade most games should take for double the write throughput. Losing 600 ms
of *purchases* is not — and gamend has payments, entitlements and wallets, which
is exactly why those are handled separately rather than left to the operator to
remember.

Measured through gamend rather than through `psql`, at 30 concurrent users:

| write path | `on` | `off` |
|---|---:|---:|
| KV write | 3,811/s | **6,530/s** (+71%) |
| KV write inside a lock | 1,309/s | 1,647/s (+26%) |
| profile update + read back | 2,785/s | 3,085/s (+11%) |

The gain shrinks as a flow mixes in reads, which is the shape of most real
traffic — so expect something between those numbers rather than the headline.

No `postgresql.conf` and no `ALTER DATABASE` — it is a gamend setting, sent in
each connection's startup packet, so it applies to every connection in the pool
from its first query and an invalid value fails the connection at boot instead
of silently leaving the server default in place.

To opt back into PostgreSQL's durable default:

```bash
GAMEND_DB_POSTGRES_SYNCHRONOUS_COMMIT=on
```

**Payments are exempt whatever this is set to.**
`Gamend.Repo.durable_transaction/2` issues `SET LOCAL synchronous_commit = on`
for the length of the transaction, and `Payments.fulfill_purchase/2` and
`Payments.revoke_purchase/2` use it — so a charge the provider has already
taken is on disk before the player is told it worked. Use it for any write of
your own with the same property:

```elixir
Repo.durable_transaction(fn ->
  # …a write that must survive a power cut…
end)
```

It is a no-op on SQLite, where durability is `GAMEND_DB_SQLITE_SYNCHRONOUS`, a
connection-wide pragma with no per-transaction override.

This is also the trade SQLite has been making on your behalf all along, with
`synchronous = NORMAL`. Defaulting PostgreSQL to `off` does not make it less
safe than the SQLite default — it makes the two comparable, and PostgreSQL keeps
the per-transaction escape hatch that SQLite does not have.

On a cloud volume the gain is usually larger than the 2.4x measured here,
because a network-attached disk has a far worse `fsync` latency than the local
SSD this was measured on.

Two consequences worth carrying:

- **SQLite's write speed is partly a durability trade.** A crash can cost the
  last transactions since the checkpoint. That is usually an acceptable trade
  for a game, and it is a choice rather than a free lunch — `synchronous=FULL`
  removes it and slows writes.
- **PostgreSQL's real advantage is concurrency, not per-write speed.** The app
  commits across a pool of ten connections, which is why it reaches 5,472/s
  through the stack while a single serial session manages 3,096/s. SQLite has
  one writer and cannot do that at any pool size.

## How many players

Two different ceilings, and which one binds depends on what your players do.

**Connected but idle:** about 24 KB of process memory per socket, or roughly
100 KB once binaries, presence and registry entries are counted. On that basis:

| RAM | idle sockets |
|---|---|
| 1 GB | ~7,500 |
| 2 GB | ~17,500 |
| 4 GB | ~37,000 |
| 8 GB | ~78,000 |

**Actively playing:** writes are what run out, not memory. Taking the measured
write budget of the machine above:

| player behaviour | SQLite | PostgreSQL |
|---|---|---|
| one action every 5 s | ~5,000 | ~10,000 |
| one action every 15 s | ~14,000 | ~28,000 |
| one action every minute | ~59,000 | ~118,000 |

So a single modest server handles **thousands to tens of thousands of concurrent
players**, and the number is set by how often they write, not by how many are
connected.

## Where the cost is

Three tiers, and they are what to design around:

1. **Reads are effectively free** — ~16,000/s, 1.5 ms, and identical through a
   plugin. Read as much as you like; the cache absorbs it.
2. **A write is ~4x a read** — ~4,000-5,500/s. This is what actually bounds a
   busy game, so the question that sizes a server is how often players *write*,
   not how many are connected.
3. **A locked write is ~4x again**, with a long tail. `Gamend.Lock.serialize/3`
   serialises every writer for a key — `pg_advisory_xact_lock` on PostgreSQL, a
   cluster-wide mutex on SQLite. Use it only where a read-modify-write genuinely
   needs it, and prefer an atomic statement where one exists (`Economy.grant/4`
   and quest claiming both do, which is why they are not on the slow tier).

Email login sits outside all three at ~12/s: bcrypt is CPU-bound by design.
Players pay it once per session and refresh afterwards, and a token refresh is
in tier one.

## Which database

Start on SQLite. It needs no second process, no network hop and no backup story
beyond copying a file, and it serves reads exactly as fast as PostgreSQL does.

Move to PostgreSQL when **writes** become the constraint — roughly twice the
write throughput, and about half the latency at every concurrency level. The
switch is a compile-time choice (`GAMEND_DB_ADAPTER=postgres`, or the
`-postgres` Docker tag), so plan it rather than flip it under load. See
[PostgreSQL Setup](postgresql-setup).

Two caveats worth knowing. SQLite has a single writer, so its write throughput
*falls* as concurrency rises past a couple of dozen simultaneous writers, while
reads keep scaling — if your game writes constantly (persistent world state,
frequent saves) you will meet that sooner. And its write speed is partly bought
with `synchronous=NORMAL`, which defers the `fsync`; a crash can cost the
transactions since the last checkpoint. Set
`GAMEND_DB_SQLITE_SYNCHRONOUS=full` if that trade is not acceptable, and expect
writes to slow.

## Compared to Nakama

Nakama publishes figures for a single node at 1 CPU / 3 GB with its database on
a separate 8-vCPU instance. Matching that shape as closely as a laptop allows
(one BEAM scheduler, PostgreSQL as a separate process):

| operation | Nakama | gamend |
|---|---|---|
| user registration | 528/s @ 21 ms | 1,037/s @ 14 ms |
| custom RPC | ~700-825/s @ 20-27 ms | 2,635/s @ 1.6 ms |
| concurrent sockets in 3 GB | 20,277 | ~27,000 |

Ahead on each operation they publish — but read it as "the same order of
magnitude, ahead on each", not as a multiplier: an M1 core is faster than the
cloud vCPU they measured on, and their database sat across a network while this
one did not. Nakama also publishes a 2-million-CCU *cluster* result; gamend has
no comparable multi-node measurement yet.

## Measuring your own

The numbers above are reproducible in about ten minutes on your own hardware,
and your game's mix of reads and writes matters more than any table here. See
[Load Testing](load-testing) for the harness, and read its check column before
its latency column: a server that answers quickly with stale data is failing,
not performing.
