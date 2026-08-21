---
icon: hero-chart-bar
---

# Performance

We compared **Gamend** and **Nakama** on various machine sizes. Overall, **Gamend** is 2x faster and supports 2x more idle connections.

| operation | `shared-1x` | `shared-4x` | `shared-8x` | `perf-1x` | `perf-1x` | Nakama | `perf-2x` |
|---|---:|---:|---:|---:|---:|---:|---:|
| cores | 0.06 | 0.25 | 0.5 | 1 | 1 | 1 | 2 |
| memory | 1 GB | 1 GB | 2 GB | 2 GB | 3 GB | 3 GB | 4 GB |
| idle sockets | 6,867 | 9,055 | 22,333 | 22,359 | **37,854** | 20,277 | 51,225 |
| cached read (`GET /me`) | 1,411 | 6,242 | 8,087 | 1,940 | 1,930 | — | 3,746 |
| plugin call, no database | 125 | 4,918 | 7,783 | 1,989 | **1,982** | 700–825 | 3,553 |
| write | 41 | 87 | 694 | 753 | 762 | — | 945 |
| write inside a lock | 30 | 57 | 206 | 462 | 462 | — | 517 |
| registration (device) | 44 | 125 | 184 | 495 | **589** | 528 | 712 |
| email login (see below) | 0.3 | 1.2 | 2.1 | 4.0 | 4.0 | — | 7.9 |
| cost / month | $6 | $8 | $16 | $32 | $37 | — | $64 |

The email-login row was measured against **bcrypt at cost 12**, which is what
that path used at the time. It has since moved to **Argon2id** (16 MiB, t=3,
p=1) — measured locally at **21.5ms a hash against bcrypt's 253.4ms, 11.8x**,
and stronger, because Argon2id is memory-hard where bcrypt works in 4 KB. The
machines above have not been re-run, so treat that row as a floor rather than
scaling it by hand.

Argon2id costs memory where bcrypt did not, but it does not grow with traffic:
the hash runs on a dirty CPU scheduler and the BEAM has one per vCPU, so at
most that many hashes hold memory at once and the rest queue. Measured, 8
concurrent hashes added 112 MB of RSS and **512 concurrent added the same
112 MB**. The ceiling is `vCPUs x 16 MiB` — 16 MB on a one-core box, 128 MB on
`shared-cpu-8x` — a few percent of the machine either way. A login flood gets
slow rather than fatal. `GAMEND_AUTH_ARGON2_MEMORY_LOG2` lowers it further.

The Nakama column is their own
[published benchmarks](https://heroiclabs.com/docs/nakama/getting-started/benchmarks/),
for a single node at 1 vCPU / 3 GB with its database on a separate 8-vCPU
instance. It sits next to the perf-1x / 3 GB column because that is the same
configuration.

### It scales linearly

![Concurrent connections](images/sockets-by-memory.svg)

Per connection the cost is **68–75 KB**, and it barely moves across a 4x range
of memory and a 16x range of CPU.

## Measuring your own

The numbers above are reproducible in about ten minutes on your own hardware,
and your game's mix of reads and writes matters more than any table here. See
[Load Testing](load-testing) for the harness, and read its check column before
its latency column: a server that answers quickly with stale data is failing,
not performing.
