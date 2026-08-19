---
icon: hero-chart-bar
---

# Performance

Measured numbers, not estimates. Everything below comes from the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress), which you can
run against your own deployment — see [Load Testing](load-testing).

## Operations

Measured on Fly, one machine at a time, resized between runs with the hardware
read back off the machine before load was applied. SQLite, 50 concurrent users,
30 seconds per scenario, generator in the same region. Requests per second:

| operation | shared-1x<br>0.06 core<br>1 GB | shared-4x<br>0.25 core<br>1 GB | shared-8x<br>0.5 core<br>2 GB | perf-1x<br>1 core<br>2 GB | perf-1x<br>1 core<br>3 GB | perf-2x<br>2 cores<br>4 GB | perf-4x<br>4 cores<br>8 GB |
|---|---:|---:|---:|---:|---:|---:|---:|
| cached read (`GET /me`) | 1,411 | 6,242 | **8,087** | 1,940 | 1,930 | 3,746 | 6,275 |
| plugin call, no database | 125 | 4,918 | **7,783** | 1,989 | 1,982 | 3,553 | 5,892 |
| write | 41 | 87 | 694 | 753 | 762 | 945 | **1,881** |
| write inside a lock | 30 | 57 | 206 | 462 | 462 | 517 | **692** |
| registration (device) | 44 | 125 | 184 | 495 | 589 | 712 | **1,015** |
| email login (bcrypt) | 0.3 | 1.2 | 2.1 | 4.0 | 4.0 | 7.9 | **15.6** |
| **cost / month** | $6 | $8 | $16 | $32 | $37 | $64 | $129 |

Every cell passed 100% of its read-your-write checks with zero errors, and the
server logged no OOM and no crashes at any size.

### Reading that table

**bcrypt is the only row that scales cleanly with cores** — 0.3, 1.2, 2.1, 4.0,
7.9, 15.6 against 0.06, 0.25, 0.5, 1, 2, 4 cores. That is ~3.9 email logins per
second per core, in a straight line, because it is the one path that is pure
CPU and nothing else. It is the number to size on if your players sign in with
passwords.

**Shared CPUs are not the cores they advertise.** A `shared-cpu-Nx` gets 5ms of
every 80ms per CPU — 6.25% — and bursts above that only while it has credit.
That is why `shared-cpu-8x` at $16 *beats* `performance-4x` at $129 on cached
reads (8,087 against 6,275): a cached read is short, bursty work and burst is
what a shared CPU is good at. Look at the same two boxes on bcrypt — 2.1 against
15.6 — for what happens when the work is sustained. Shared sizes are excellent
value for read-heavy traffic and useless for anything CPU-bound, and their
numbers depend on how idle the machine has been, so do not quote them as a
ceiling.

**More RAM did nothing.** `performance-1x` at 2 GB and at 3 GB are the same
machine with an extra gigabyte, and every row is within noise (cached read 1,940
vs 1,930, bcrypt 4.0 vs 4.0). gamend is CPU-bound at this scale. Buy cores.

## How many players

About **57 KB of server memory per idle socket**, measured rather than
extrapolated: 7,000 sockets took the BEAM from 29 MB to 383 MB of process memory
plus 50 MB of binary memory on a 1-core / 3 GB machine.

| what | measured |
|---|---:|
| idle sockets held on 1 core / 3 GB | **~10,000** |
| memory per idle socket | ~57 KB |
| server errors or OOM at that level | none |

The honest limit of that measurement: **the ramp is registration-bound, not
socket-bound.** Every socket in the test signs up its own device user first, and
at ~589 registrations/s on one core the generator cannot open sockets faster
than the server can create accounts. Ten thousand is what one generator reached
before the *generator* ran out of memory (k6 holds 1-3 MB per virtual user); the
server was still idle-cool at that point. Finding the real ceiling needs
pre-created users and several load generators, and is not yet done.

In practice the write ceiling binds first anyway: what sizes a server is how
often players write, not how many are connected.

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
