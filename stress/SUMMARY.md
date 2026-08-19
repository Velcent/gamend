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

| | SQLite | Postgres |
|---|---:|---:|
| cached read | 16,131/s | 16,636/s |
| signup | 1,585/s | 3,078/s |
| chat | 896/s | 2,038/s |
| hook RPCs | 3,541/s | 6,064/s |
| email login (bcrypt) | 12/s | 11/s |

Reads tie; **every write path is roughly 2x on Postgres**. Memory is ~24 KB of
process memory per connected player, flat in account size.

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
| **`leaderboards` fails 513 read-back checks on Postgres**, none on SQLite. | open — a submitted score the caller cannot always read back. |

## What was wrong along the way

Recorded because the corrections were as informative as the findings, and both
of these are easy to repeat:

- **"Per-socket memory grows with friend count"** — it does not. Bandit serves
  HTTP and WebSocket connections from the same handler module, so sampling
  transports by module name mixed idle sockets with in-flight requests. Two
  "fixes" were built against that phantom and reverted.
- **"RSS says 400-530 KB per socket"** — those runs were writing thousands of
  friendship rows *inside* the measurement window.

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
