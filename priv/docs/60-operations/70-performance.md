---
icon: hero-chart-bar
---

# Performance

Measured numbers, not estimates. Everything below comes from the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress), which you can
run against your own deployment — see [Load Testing](load-testing).

## What one machine does

A MacBook Air M1 (8 cores, 16 GB), production build, database on the same
machine, load generator on the same machine. That last part matters: these are a
**floor**, not a ceiling — a real server with the generator elsewhere does
better.

| operation | SQLite | PostgreSQL |
|---|---:|---:|
| cached read (`GET /me`) | 16,131/s | 16,636/s |
| KV read | 13,606/s | 16,218/s |
| token refresh | 13,080/s | 14,929/s |
| plugin RPC | 3,541/s | 6,064/s |
| profile write | 2,976/s | 5,827/s |
| leaderboard submit + reads | 2,039/s | 3,999/s |
| device signup | 1,585/s | 3,078/s |
| lobby create + state change | 1,396/s | 3,176/s |
| chat message + delivery | 896/s | 2,038/s |
| email login (bcrypt) | 12/s | 11/s |

Reads are the same on both — they are cache hits and never reach the database.
**Every write path is roughly twice as fast on PostgreSQL.** Email login is
bcrypt, which is CPU-bound by design and unaffected by the database.

Matchmaking is a latency rather than a rate: a player waits a **median 66 ms**
from joining the queue to being matched, because a join asks the matcher to run
rather than waiting for its next sweep.

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

## Which database

Start on SQLite. It needs no second process, no network hop and no backup story
beyond copying a file, and it serves reads exactly as fast as PostgreSQL does.

Move to PostgreSQL when **writes** become the constraint — roughly twice the
write throughput, and about half the latency at every concurrency level. The
switch is a compile-time choice (`GAMEND_DB_ADAPTER=postgres`, or the
`-postgres` Docker tag), so plan it rather than flip it under load. See
[PostgreSQL Setup](postgresql-setup).

One caveat worth knowing: SQLite has a single writer, so its write throughput
*falls* as concurrency rises past a couple of dozen simultaneous writers, while
reads keep scaling. If your game writes constantly — persistent world state,
frequent saves — you will meet that sooner.

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
