# Stress test — what we did and what we found

One page. The harness is [`stress/`](README.md), the full numbers are in
[`baselines/2026-08-19-macbook-air-m1.md`](baselines/2026-08-19-macbook-air-m1.md),
the plan and the open questions are in
[`docs/specs/load-testing.md`](../docs/specs/load-testing.md).

## What was built

A k6 harness that answers three separate questions, because they need three
different tools:

| tool | question |
|---|---|
| `scenarios/` + `suite.sh` | what does each operation cost? (19 isolated scenarios) |
| `sweep.sh` | where does it stop scaling? (one scenario up a VU ladder) |
| `journeys/` | how many players fit? (weighted session, idle sockets, connect storm, broadcast storm, soak) |
| `report.mjs` | turn a run into a Markdown report and a self-contained HTML page |

Plus `modules/plugins_examples/stress_hook`, the server-side half: micro-benchmark
RPCs, triggers for writes a player has no endpoint for (quests, scores, wallet),
and the introspection that made the memory work possible.

Every write scenario reads its own write back, so a run that returns 200s fast
while serving stale data fails. That is the point of the check column.

## The headline numbers

MacBook Air M1, 8 cores, 16 GB, `MIX_ENV=prod`, k6 on the same machine — so a
floor, not a ceiling.

One operation per row, so the rows compare:

| operation | SQLite | Postgres |
|---|---:|---:|
| cached read | 17,489/s | 16,422/s |
| plugin call, no database | 16,372/s | 12,616/s |
| write | 4,266/s | 5,472/s |
| write inside a lock | 966/s | 1,574/s |
| email login (bcrypt) | 12/s | 11/s |

**Every read costs the same, plugin or not** — the hook layer adds nothing
measurable. A write is ~4x a read; a locked write ~4x again, with a p99 of
261 ms because the lock serialises writers for that key. Memory is ~24 KB of
process memory per connected player, flat in account size.

The two databases look closer on writes than they should because they are not
doing the same work: gamend runs SQLite with `synchronous=NORMAL` (fsync
deferred to a checkpoint) while PostgreSQL was measured on its default
`synchronous_commit=on`. Serial commits on the same machine: **3,096/s with
fsync, 7,448/s without**. PostgreSQL is doing more durability work per write and
still winning, and its real advantage is committing across a pool while SQLite
has one writer.

That finding is now shipped rather than recommended: **PostgreSQL defaults to
`synchronous_commit=off`** (consistent, not corruptible; the exposure is ~600 ms
of commits on an OS crash), sent per connection via
`GAMEND_DB_POSTGRES_SYNCHRONOUS_COMMIT`, with payments exempted automatically —
`Repo.durable_transaction/2` forces `on` around the writes that must not be
lost. The Postgres column above therefore understates what gamend now ships.
See the Performance guide.

Multi-step flows are reported as flows/s with their step count (signup 792/s,
lobby create+start+leave 279/s, friend request+accept+read-back 134/s), because
a flow spending seven requests is not slower than one spending a single request
— it is doing seven times the work.

**Capacity on this laptop:** ~10,000 concurrently active players on SQLite,
~20,000-30,000 on Postgres. Writes run out long before memory does.

**Against Nakama's published 1 CPU / 3 GB node** (matched by pinning the BEAM to
one scheduler): 1,037 registrations/s against their 528, 2,635 RPC calls/s
against ~800, ~27,000 sockets in 3 GB against 20,277. Ahead on everything they
publish — but an M1 core is faster than a GCP vCPU and their database was a
network hop away, so read it as "same order, ahead on each operation" rather
than as a multiplier.

## What it found, and what got fixed

| finding | effect |
|---|---|
| **Dev mode was hiding everything.** Phoenix checks for changed files per request. | 293 req/s → **18,918 req/s** in prod. Everything measured before this was the code reloader. |
| **SQLite pool of 10 was thrashing.** Ten connections raced one writer through a non-FIFO backoff. | 6 concurrent signups: 10-21 s and some 500s → **44-66 ms**, none. Pool default is now 1 for SQLite. |
| **Logins wrote three rows synchronously.** Two were fire-and-forget. | signup 687 req/s @ 36 ms → **1,215 req/s @ 2.4 ms**. |
| **Repeat quests re-armed once an hour**, not immediately. | fixed (separate session) |
| **Analytics writes failed the login they rode on** under a busy database. | fixed (separate session) |
| **Socket memory is an OS default, not our code.** ~105 KB/socket of binary memory follows the kernel's ~400 KB receive buffer. | `GAMEND_REALTIME_SOCKET_BUFFER_KB` exists, **off by default** — see below. |
| **Matchmaking took 3.1 s to match**, all of it waiting for the next sweep tick. | a join now nudges the worker (coalesced, 100 ms): **3,146 ms → 66 ms** time-to-match, and the scenario went 40 → 477 req/s. |
| **`leaderboards` fails 513 read-back checks on Postgres**, none on SQLite. | fixed — and it was not the score. `records/around/:user_id` ranked the caller in one query and windowed at that offset in another; a score submitted in between moved them, and past `half` positions of drift they were missing from their own page. One CTE, one snapshot: **497 failures → 0**. |

## What was wrong along the way

Recorded because the corrections were as informative as the findings, and both
of these are easy to repeat:

- **"Per-socket memory grows with friend count"** — it does not. Bandit serves
  HTTP and WebSocket connections from the same handler module, so sampling
  transports by module name mixed idle sockets with in-flight requests. Two
  "fixes" were built against that phantom and reverted.
- **"RSS says 400-530 KB per socket"** — those runs were writing thousands of
  friendship rows *inside* the measurement window.

## Four bottleneck hypotheses, one survived

Read from the numbers, then checked against the code. Worth recording because
the check is the part that matters:

| hypothesis | verdict |
|---|---|
| Matchmaking's 3.1 s is the sweep interval, not work | **true** — fixed, 48x faster |
| Advisory locks (+8 ms on Postgres) are hurting hot write paths | **false** — `Economy.grant` is already lock-free (atomic upsert / conditional update). The 8 ms was `stress_kv_write_locked`, a synthetic probe of the lock primitive, not a production path |
| `quest_claim` takes two locks | **false** — it takes none. `transition_to_claimed` is an atomic conditional `UPDATE`, and the reward grant is lock-free. Its 54 ms is several sequential *writes* |
| `page_home` is 4.5x slower on Postgres, so N+1 | **false** — the home page issues **1 query** and renders in 6 ms warm. The 88 ms was the conditions of that run |

What is left, and not attempted: `Quests.advance_quest` genuinely does hold a
per-(user, quest) advisory lock, because merging objective progress is a
read-modify-write of a JSON map. That is the one hot path where the lock cost is
real — but making it atomic across both adapters is a design change with
correctness risk, not tuning, and it deserves its own scope.

## What is left, in order of expected value

1. **The quest progress lock.** `Quests.advance_quest` holds a per-(user, quest)
   advisory lock because merging objective progress is a read-modify-write of a
   JSON map. It is the one hot path still taking a lock, and it shows: quests is
   the slowest flow per step in the suite. Both adapters can update JSON
   atomically (`jsonb_set`, `json_set`), which would remove the lock — a design
   change with correctness risk, so it needs its own scope.
2. **`synchronous_commit = off` on PostgreSQL** — +71% on writes, already
   documented with the payment caveat. A deployment decision rather than a code
   change.
3. **Pool sizing** — attempted here and inconclusive: `me` fell 11.0k → 8.8k →
   5.6k req/s across the three pool levels, which is the laptop degrading, not
   the pool. Belongs on the matrix, where the plan already calls for 10/20/40 on
   the 8- and 16-vCPU cells.
4. **bcrypt rounds** — 12 logins/s. Only matters for a login storm after a
   restart; the lever is `config :bcrypt_elixir, :log_rounds`.

Ahead of all of them was **`leaderboards` failing 513 read-back checks on
PostgreSQL** — correctness outranks throughput. That one is now fixed; the
per-check breakdown is what named it, because the aggregate check rate says
only that *something* failed. It is worth re-reading the failing scenario's
checks one at a time before theorising about the cause: the read-back everyone
assumed was broken (`records/me`) never failed once.

## What is not done

- **Nothing has run on real hardware.** The Fly matrix (`fly/matrix.sh`, cells
  A-H across SQLite/Postgres and 1-16 vCPU) is built and dry-run clean, but
  every number here comes from one laptop sharing cores with the load generator.
- **No horizontal test.** One node, no clustering. Nakama's 2M-CCU headline is a
  cluster result and has no counterpart here yet.
- **The socket-buffer setting is unverified and therefore off.** It caps the
  Erlang driver's read buffer, but an accepted socket recomputes that from the
  kernel's negotiated `recbuf`, so macOS discards it — three attempts, no
  change. Linux does not auto-tune the same way and should honour it; nobody
  has watched that happen. Turning it on without measuring per-socket memory
  before and after would be cargo cult.

  Capping `recbuf`/`sndbuf` instead *would* bound the memory — by shrinking the
  TCP window, which caps throughput at window/RTT. At 32 KB over a 100 ms link
  that is ~2.6 Mbit/s, ample for game messages and ruinous for the same listener
  serving a multi-megabyte Godot web export. The setting deliberately does not
  touch them.
