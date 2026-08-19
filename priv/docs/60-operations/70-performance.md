---
icon: hero-chart-bar
---

# Performance

Measured numbers, not estimates. Everything below comes from the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress), which you can
run against your own deployment — see [Load Testing](load-testing).

## Operations

One request each, so these compare directly:

| operation | SQLite | PostgreSQL | median |
|---|---:|---:|---:|
| KV read | **17,612/s** | 11,980/s | 1.4 ms |
| cached read (`GET /me`) | **17,489/s** | 16,422/s | 1.4 ms |
| plugin call, no database | **16,372/s** | 12,616/s | 1.5 ms |
| token refresh | **15,677/s** | 12,964/s | 1.5 ms |
| write | 4,266/s | **5,472/s** | 6.8 ms |
| write inside a lock | 966/s | **1,574/s** | 0.4 ms |
| email login (bcrypt) | **12/s** | 11/s | 1,365 ms |

The locked write is the one bimodal row: the lock is usually free (0.4 ms) or
contended (p99 261 ms), and the throughput is set by the contended half.

## How many players

About 24 KB of process memory per idle socket, or roughly 100 KB once binaries,
presence and registry entries are counted. On that basis:

| RAM | idle sockets |
|---|---:|
| 1 GB | ~7,500 |
| 2 GB | ~17,500 |
| 4 GB | ~37,000 |
| 8 GB | ~78,000 |

In practice the write ceiling binds first: what sizes a server is how often
players write, not how many are connected.

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
