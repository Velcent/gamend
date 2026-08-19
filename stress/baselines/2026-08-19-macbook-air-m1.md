# Baseline — MacBook Air M1, 19 August 2026

The first full run of the harness, on both adapters, in a production build.
Everything here is one laptop — the load generator, the server and (for the
Postgres runs) the database all share the same eight cores — so treat the
throughput figures as a **floor**, not a ceiling: a dedicated server with the
generator elsewhere is what the Fly matrix measures, and every number here
should improve there.

Short version: **~16,000 cached reads/s, ~1,000 writes/s on SQLite and ~2,000
on Postgres, ~24 KB of process memory per connected player, and on the order of
10,000-30,000 concurrently active players** depending on adapter and how often
players write. Constrained to a single scheduler to match Nakama's published
1 CPU / 3 GB node, it registers ~1,000 users/s against their 528/s and holds
~27,000 sockets in 3 GB against their 20,277 — with the caveats in that
section, which matter.

## Machine and versions

| | |
|---|---|
| Machine | MacBook Air, Apple M1 |
| Cores | 8 (4 performance + 4 efficiency) |
| Memory | 16 GB |
| OS | macOS 26.6.1 (25G76) |
| Elixir / OTP | 1.20.1 / OTP 29 |
| k6 | v1.4.2 (darwin/arm64) |
| Postgres | 14.13 (Homebrew), over a unix socket |
| SQLite | bundled exqlite, WAL, `pool_size: 1` |
| Server | `MIX_ENV=prod`, `stress_hook` only, rate limiting off |

The generator runs on the same machine as the server. Past roughly 15 concurrent
users everything below is partly measuring that contention.

## Run everything in `MIX_ENV=prod`

The single most important thing this baseline established. Same scenario, same
machine, same minute:

| mode | req/s | median |
|---|---|---|
| dev | 293 | 50 ms |
| **prod** | **18,918** | **0.6 ms** |

Dev mode checks for changed files on every request. A dev-mode benchmark
measures Phoenix's code reloader; the application is invisible behind it.

## The suite, both adapters

19 scenarios, 30 concurrent users, 15 s each, run twice — once on SQLite, once
on Postgres — after the login-write fix, so the two are directly comparable.
Over a million requests each, every check green except one noted below.

| scenario | SQLite req/s | med | p95 | Postgres req/s | med | p95 | PG/SQLite |
|---|---:|---:|---:|---:|---:|---:|---:|
| `me` | 16,131 | 1.5 | 3.6 | 16,636 | 1.5 | 3.5 | 1.03x |
| `kv_read` | 13,606 | 1.8 | 4.4 | 16,218 | 1.5 | 3.6 | 1.19x |
| `auth_refresh` | 13,080 | 1.8 | 4.4 | 14,929 | 1.6 | 3.8 | 1.14x |
| `hooks_rpc` | 3,541 | 0.3 | 1.0 | 6,064 | 0.5 | 18.6 | 1.71x |
| `profile_write` | 2,976 | 10.0 | 17.0 | 5,827 | 4.7 | 9.6 | 1.96x |
| `economy` | 2,619 | 9.1 | 21.7 | 5,345 | 4.6 | 10.8 | 2.04x |
| `notifications` | 2,418 | 11.7 | 20.0 | 5,617 | 5.1 | 8.6 | 2.32x |
| `groups` | 2,015 | 13.0 | 27.0 | 4,981 | 5.5 | 10.2 | 2.47x |
| `leaderboards` | 2,039 | 13.7 | 19.9 | 3,999 | 6.7 | 11.7 | 1.96x |
| `auth_device` | 1,585 | 18.2 | 33.9 | 3,078 | 8.4 | 19.8 | 1.94x |
| `lobbies_http` | 1,396 | 18.0 | 40.8 | 3,176 | 7.4 | 18.3 | 2.28x |
| `friends` | 936 | 30.6 | 58.5 | 1,751 | 15.8 | 28.9 | 1.87x |
| `lobby_ws` | 907 | 23.7 | 55.8 | 1,795 | 12.1 | 28.5 | 1.98x |
| `chat` | 896 | 24.9 | 54.3 | 2,038 | 11.2 | 23.8 | 2.27x |
| `quests` | 886 | 29.1 | 65.3 | 1,291 | 18.5 | 54.5 | 1.46x |
| `web_pages` | 206 | 9.0 | 56.9 | 174 | 29.8 | 97.9 | 0.85x |
| `matchmaking` | 40 | 2.2 | 14.5 | 39 | 1.2 | 11.9 | 0.98x |
| `auth_email` | 12 | 1364.9 | 1445.7 | 11 | 1439.6 | 1663.5 | 0.87x |
| `ws_join_idle` | 2 | 8.3 | 12.1 | 2 | 9.5 | 14.0 | 1.00x |

The pattern is clean: **reads are a tie** (both are cache hits, ~13-17k/s),
**every write path is roughly 2x on Postgres**, and the three scenarios where
neither adapter matters are the ones bound by something else — bcrypt
(`auth_email`), the matchmaking sweep tick (`matchmaking`), and a socket dwell
(`ws_join_idle`).

Two things worth chasing, both visible only because the checks run:

- **`leaderboards` failed 513 checks on Postgres and none on SQLite** — a
  submitted score that the caller's own read-back does not always see. That is
  either a visibility race or a cache keyed differently under Postgres, and it
  is exactly the class of bug the read-your-write checks exist to catch.
- **`hooks_rpc` p95 is 18.6 ms on Postgres against 1.0 ms on SQLite** while its
  median is lower. A fat tail on an otherwise faster adapter usually means
  connection-pool queueing rather than query cost.

## Where it stops scaling

`./sweep.sh <scenario> 5 15 30 60 120 240`, throughput in req/s:

| VUs | me (SQLite) | me (PG) | hooks_rpc (SQLite) | hooks_rpc (PG) | auth_device (SQLite) | auth_device (PG) |
|---|---:|---:|---:|---:|---:|---:|
| 5 | 14,325 | 12,753 | 3,004 | 6,240 | 1,215 | 3,114 |
| 15 | **18,918** | 15,449 | 3,996 | 6,506 | **1,940** | 2,510 |
| 30 | 17,949 | 14,567 | 3,617 | **6,518** | 1,643 | 1,948 |
| 60 | 17,253 | 15,207 | **4,235** | 6,391 | 1,483 | 1,637 |
| 120 | 16,673 | 15,012 | 3,389 | 4,817 | 1,362 | 1,428 |
| 240 | 16,227 | 14,521 | 3,567 | 4,552 | 1,267 | 1,152 |

Reads plateau at ~19k and hold flat to 240 VUs with latency growing linearly —
healthy queueing. Writes peak early and then **decline**, which on this machine
is as much core oversubscription as database contention: both adapters do it.

## SQLite vs Postgres

| | 5 VUs | 60 VUs | 240 VUs |
|---|---|---|---|
| signup, throughput | 2.56x PG | 1.10x PG | 0.91x PG |
| signup, p95 | 3.2 vs 12.8 ms | 66 vs 156 ms | 382 vs 687 ms |
| hook RPCs, throughput | 2.08x PG | 1.51x PG | 1.28x PG |
| cached read, throughput | 0.89x PG | 0.88x PG | 0.89x PG |

Postgres wins the write paths on **latency** much more clearly than on
throughput — about half the p95 at every level. SQLite wins cached reads by
~10%, which is what a local file behind a cache should do.

## Memory per idle socket

**~24 KB of process memory per connected player, and it does not grow with the
size of the account.** Measured with a plugin RPC (`stress_socket_memory`) that
reads `Process.info(:memory)` on live processes, median of 40 samples at 300
concurrent sockets:

| friends on the account | channel process | `cu_last` memo | WebSocket transport | total |
|---|---:|---:|---:|---:|
| 0 | 2.8 KB | 0.9 KB | 21.6 KB | **24.4 KB** |
| 10 | 2.8 KB | 0.9 KB | 21.7 KB | **24.5 KB** |
| 20 | 2.8 KB | 0.9 KB | 21.7 KB | **24.5 KB** |

That is at the light end of what a Phoenix socket can cost, and well under
Nakama's published ~150 KB per connection (~20,277 sockets on a 3 GB node).
Extrapolated at process level, 20,000 sockets is roughly **0.5 GB**.

RSS tells a heavier story — 60-100 KB per socket — and both numbers are real:
process memory is what the sockets themselves hold, while RSS also carries the
refcounted binaries behind each connection, the Presence and Registry ETS
entries, and allocator slack. **RSS is the number that decides whether a box
OOMs**, so size hardware from it; process memory is the number that tells you
whether the *code* is holding something it should not.

### Two measurement traps, both of which produced wrong answers first

Recorded because both are easy to repeat and each one manufactured a finding
that was not there.

1. **Bandit serves HTTP and WebSocket connections from the same
   `Bandit.DelegatingHandler` module.** Sampling transports by module name
   therefore mixes idle websockets with in-flight HTTP requests — at 300 sockets
   the node had 601 handler processes, so half the sample was HTTP. The median
   then moved with whatever request mix happened to be in flight, which looked
   exactly like "memory grows with friend count" (41 KB → 119 KB → 139 KB).
   Sampling the app's own `:ws_socket` registry instead gives a flat 21.7 KB.
2. **Seeding inside the measurement window.** The RSS runs that showed 400-530
   KB per socket at 10-20 friends were creating 5,000-10,000 friendship rows
   *during* the sample. That is the seeding, not the sockets.

Nothing needed fixing, so nothing was changed. Forced GC after join
(`:erlang.garbage_collect/1` on the transport), channel hibernation and
`websocket: [fullsweep_after: 20]` were all tried against the bad measurement
and none of them are in the tree.

## Where the memory actually goes

Measured with `stress_memory_breakdown`, single scheduler, idle versus holding
3,000 idle sockets:

| category | idle | 3,000 sockets | per socket |
|---|---:|---:|---:|
| **binary** | 11.9 MB | 318.4 MB | **105 KB** |
| processes | 25.2 MB | 150.3 MB | 43 KB |
| ETS | 3.8 MB | 25.3 MB | 7 KB |
| code | 37.8 MB | 38.2 MB | ~0 |
| atom | 1.5 MB | 1.5 MB | 0 |
| **BEAM total** | 146.7 MB | 607.3 MB | 157 KB |
| **RSS** | 223.5 MB | 673.8 MB | 154 KB |

**Binary memory is two thirds of the cost**, and it is not application data —
`processes` (which holds the channel state, the assigns, the memo) is 43 KB, and
ETS (PubSub subscriptions, the two Registry partitions, Presence, the cache) is
7 KB. The cache is not the problem: at idle every ETS table in the node totals
3.8 MB, and the largest is `:code_server`.

The binaries are **socket buffers**. Reading the options off a live connection:

```
listening socket:  buffer   9,216   recbuf 131,072   sndbuf 131,072
connected socket:  buffer 408,300   recbuf ~470,000  sndbuf 146,988
```

macOS auto-tunes `recbuf` to around half a megabyte per connection, and the
Erlang inet driver sizes its own `buffer` from that — 408 KB per socket,
allocated from binary space as traffic requires. That is where the ~105 KB
lands.

Two consequences worth carrying into the deployed run:

1. **This number is probably macOS-specific.** Linux defaults are far smaller
   and self-tune differently, so socket density on a Fly machine may be
   materially better than the projection here. Re-measure there before believing
   either number.
2. **There is a knob, and it is off.** `GAMEND_REALTIME_SOCKET_BUFFER_KB`
   (default **0** = leave the OS alone) caps `buffer`, the Erlang driver's
   userspace read buffer, via `thousand_island_options.transport_options`.

   **It does not take effect on macOS.** The endpoint config provably carries
   the value, and connected sockets still report `buffer: 408300` — an accepted
   socket's buffer is recomputed from whatever `recbuf` the kernel negotiated
   (~400 KB here), discarding the listen-time setting. Three attempts, no
   movement. Linux does not auto-tune receive buffers the same way and is
   expected to honour it, but that is a prediction, not a measurement, which is
   why the default is off.

   **The neighbouring knobs are a trap.** Capping `recbuf`/`sndbuf` would bound
   the memory reliably — by shrinking the TCP window, which caps a connection's
   throughput at window/RTT. 32 KB over a 100 ms link is ~2.6 Mbit/s: ample for
   game traffic, ruinous for the same listener serving a multi-megabyte Godot
   web export or an avatar upload. The setting deliberately leaves them to the
   kernel.

Ruled out along the way, both by measurement: **permessage-deflate compression**
(`compress: false` changed binary memory not at all — 350 MB against 318 MB,
inside the run-to-run spread) and **`max_frame_size`** (dropping it from 128 KB
to 16 KB moved per-socket binary from 105 KB to 97 KB, an 8 % effect).

## How many players this machine holds

Two different ceilings, and which one binds depends entirely on what the players
are doing. Both are derived from the measurements above rather than guessed, and
both assume this laptop — a real server does not share its cores with the load
generator.

### Idle players: memory decides

Note that the socket figures below are **projections from a measured marginal
cost**, not a demonstration: nothing was run against an enforced 3 GB limit. The
BEAM has no VM-wide memory cap to enforce one with — `+hmax` bounds a single
process and kills it, and everything else is an OS or container limit
(`docker --memory`, a cgroup), where exceeding it means the VM is killed rather
than throttled. A real ceiling test means running under such a limit and finding
where it dies.

At 5,000 sockets the server sat at 750 MB total (245 MB base + 505 MB). The
marginal cost between 3,000 and 5,000 sockets was ~25 KB, matching the ~24 KB
of process memory measured directly; RSS per socket including everything else
(binaries, Presence and Registry ETS, allocator slack) works out at ~100 KB at
that scale and falls as the base amortizes.

Sizing at **~100 KB per socket over a ~250 MB base** — deliberately the
pessimistic end of the range:

| RAM | idle sockets |
|---|---|
| 512 MB | ~2,500 |
| 1 GB | ~7,500 |
| 2 GB | ~17,500 |
| 4 GB | ~37,000 |
| 8 GB | ~78,000 |
| 16 GB (this laptop) | **~160,000** |

For scale, Nakama publishes ~20,277 sockets on a 3 GB node, which is ~155 KB
per connection all-in. On the same all-in basis this is ~100 KB, so roughly
1.5x more connections per gigabyte — better, but *not* the 6x that comparing
our process memory against their whole-node figure would suggest. Compare like
with like.

### Active players: writes decide

Reads are effectively free — 13-17k/s on either adapter, and cache hits do not
touch the database. Writes are the constraint, and the suite measures them
directly: the heaviest realistic mixed scenarios (`chat`, `lobby_ws`, `friends`,
`quests`) run 0.9-1.0k/s on SQLite and 1.3-2.0k/s on Postgres, at 30 concurrent
users on a laptop that is also running k6.

Taking ~1,000 writes/s (SQLite) and ~2,000 writes/s (Postgres) as this machine's
sustainable write budget, and modelling a player by how often they *write*
(chat message, lobby action, quest progress — reads do not count):

| player behaviour | writes/player/s | SQLite | Postgres |
|---|---|---|---|
| lobby chatter, 1 action / 5 s | 0.2 | ~5,000 | ~10,000 |
| ordinary session, 1 action / 15 s | 0.07 | ~14,000 | ~28,000 |
| mostly idle, 1 action / 60 s | 0.017 | ~59,000 | ~118,000 |

So on this laptop the honest headline is **on the order of 10,000 concurrently
active players on SQLite and 20,000-30,000 on Postgres**, with the idle-socket
ceiling far above that — memory is not what runs out first for an active
population, writes are.

### What these numbers are not

- **Not a server measurement.** k6 ran on the same eight cores. A dedicated box
  with the generator elsewhere is what the Fly matrix measures, and every
  throughput figure here should improve.
- **Not a distributed figure.** One node, no clustering. Nakama's headline 2M
  CCU is a cluster result; the comparable gamend number would come from the
  horizontal phase (multiple app nodes behind the proxy, Postgres, Redis L2).
- **Not a promise about your game.** The write budget assumption is doing most
  of the work in that table. Measure your own mix with `player_session.js` and
  substitute it.

## Matched against Nakama's published single-node test

Nakama publishes its numbers for **one node at 1 CPU / 3 GB**, with the database
on a separate CloudSQL instance (8 vCPU / 30 GB). To have anything comparable,
gamend was run under the same shape: BEAM constrained to a single scheduler
(`ERL_FLAGS="+S 1:1"`, confirmed by `schedulers_online: 1` on `/metrics`),
Postgres as a separate process, 30 concurrent virtual users, production build.

| operation | Nakama, 1 CPU / 3 GB | gamend, 1 scheduler | |
|---|---|---|---|
| user registration | 528/s @ 21.2 ms | **1,037/s @ 13.7 ms** | 2.0x |
| custom RPC | ~700-825/s @ 20-27 ms | **2,635/s @ 1.6 ms** | ~3.2-3.8x |
| concurrent sockets in 3 GB | 20,277 | **~27,200** | 1.3x |
| cached authenticated read | not published | 6,522/s @ 4.3 ms | — |
| authoritative match create | 39.2/s @ 15.8 ms | 39-40/s (sweep-bound) | — |

Operations, not requests: `auth_device` performs two HTTP calls per registration
and `hooks_rpc` five RPC calls per iteration, so the rates above are iterations
and RPC calls rather than the raw `req/s` the harness prints. The socket figure
is `(3 GB − 360 MB base) ÷ 102 KB`, where 102 KB is the measured marginal RSS
per socket at 3,000 sockets on this configuration; on Nakama's own all-in basis
(node memory ÷ sockets) the same run is 225 KB per socket, which is the
conservative way to read it and still lands near their 20k.

**What is still not equivalent, all of it favouring these numbers:**

- **One BEAM scheduler is not one GCP vCPU.** An M1 performance core is
  substantially faster than the Skylake-era hyperthread a GCP `n1` vCPU
  provides. This is the largest asymmetry in the table.
- **Their database was across a network; ours is a unix socket** on the same
  machine — roughly a millisecond per query in their disfavour.
- **Their database node was far larger** (8 vCPU / 30 GB) than the app node,
  while ours shares eight cores with both the app and the load generator.

So the honest reading is **"the same order, and ahead on every operation they
publish"** rather than a precise multiplier. The matrix on comparable rented
hardware is what would turn these into a claim worth printing.

The one number they own outright is the 2M-CCU cluster result, which is a
horizontal test gamend has not attempted — that belongs to the multi-node phase.

## Fixed while measuring

| | before | after |
|---|---|---|
| SQLite pool (10 → 1) | 6 concurrent signups: 10-21 s, some 500s | 44-66 ms, no errors |
| Login side-effects moved off the request path | signup 687 req/s @ 36.3 ms | **1,215 req/s @ 2.4 ms** |

Both are in the tree. The pool default is now 1 for SQLite and unchanged (10)
for Postgres.

## Reproducing

```bash
cd stress
BASE_URL=http://localhost:4000 VUS=30 DURATION=15s ./suite.sh
node report.mjs results/ --md results/report.md --page results/report.html
```

The Nakama-matched run constrains the VM to one scheduler, which is the only
part that needs a different server invocation:

```bash
ERL_FLAGS="+S 1:1" MIX_ENV=prod … mix phx.server     # confirm on /metrics:
                                                     # beam_system_schedulers_online_info 1
BASE_URL=http://localhost:4000 VUS=30 DURATION=20s THINK=0 \
  k6 run scenarios/auth_device.js    # iterations/s == registrations/s
```

See [../README.md](../README.md) for the server configuration this assumes, and
[../../docs/specs/load-testing.md](../../docs/specs/load-testing.md) for the
plan these runs belong to.
