# What a Game Server Actually Costs

I benchmarked gamend across seven machine sizes on Fly, from a $6/month shared
CPU to a $129/month four-core box, and measured what each one can actually do.

The short version: **buy cores, not RAM**, most of the sizes on offer are the
wrong shape, and the thing that limits how many players you can hold is not what
I expected.

Every number here is measured. Where I could not measure something I say so
rather than extrapolating, because I spent most of the first evening producing
numbers that turned out to be fiction — more on that at the end, because it is
the most useful part.

## The setup

One machine under test, resized between runs. A second machine in the same
region generating load with [k6](https://k6.io). Six operations, each isolated
so they subtract:

| operation | what it adds over the line above |
|---|---|
| cached read | HTTP, routing, auth, a cache hit |
| plugin call, no database | + the plugin layer |
| write | + one database write |
| write inside a lock | + an advisory lock |
| registration | + account creation and its indexes |
| email login | + bcrypt |

Every write reads itself back, so a run that returns 200s quickly while serving
stale data fails instead of looking fast.

## The numbers

SQLite, 50 concurrent users, requests per second:

| operation | shared-1x<br>$6 | shared-4x<br>$8 | shared-8x<br>$16 | perf-1x<br>$32 | perf-2x<br>$64 | perf-4x<br>$129 |
|---|---:|---:|---:|---:|---:|---:|
| cached read | 1,411 | 6,242 | **8,087** | 1,940 | 3,746 | 6,275 |
| plugin call | 125 | 4,918 | **7,783** | 1,989 | 3,553 | 5,892 |
| write | 41 | 87 | 694 | 753 | 945 | **1,881** |
| write in a lock | 30 | 57 | 206 | 462 | 517 | **692** |
| registration | 44 | 125 | 184 | 495 | 712 | **1,015** |
| email login | 0.3 | 1.2 | 2.1 | 4.0 | 7.9 | **15.6** |

Three things fall out of that table.

### bcrypt is the only honest ruler

Email login goes 0.3, 1.2, 2.1, 4.0, 7.9, 15.6 against 0.06, 0.25, 0.5, 1, 2 and
4 cores. That is **3.9 logins per second per core**, in a straight line, across a
64x range of hardware.

It is the only row that behaves that way, because it is the only path that is
purely CPU. Everything else is part cache, part disk, part lock. If your players
sign in with passwords, this is the row to size on — and if 4 logins a second on
a $32 box sounds low, that is bcrypt doing its job.

### Shared CPUs are not the cores they advertise

Look at `shared-cpu-8x` at $16 beating `performance-4x` at $129 on cached reads —
8,087 against 6,275. Then look at the same two boxes on email login: 2.1 against
15.6.

A Fly shared CPU gets 5ms of every 80ms — **6.25% of a core** — and bursts above
that only while it has credit banked. A cached read is short bursty work, which
is exactly what a burst budget is good at. bcrypt is sustained work, which is
exactly what it is not.

So shared sizes are excellent value for read-heavy traffic and useless for
anything CPU-bound. Worse, their numbers depend on how idle the machine has
been, which means you cannot really quote them at all. My first run measured
reads falling 6,262 → 6,150 → 486 → 472 → 227 across "different machine sizes"
that were all the same machine, spending its credits.

### More RAM bought nothing

I ran `performance-1x` twice, at 2 GB and 3 GB. Cached read 1,940 against 1,930.
Email login 4.0 against 4.0. Writes 753 against 762. All noise.

gamend is CPU-bound at this scale. The extra gigabyte cost $5/month and bought
nothing measurable.

## How many players fit

**28,240 concurrent idle sockets on one core with 3 GB**, holding above 20,000
for four minutes, using 2 GB and never OOMing. Nakama publishes 20,277 on the
same shape of box.

Getting there meant fixing three things that all looked like the server giving
up and none of which were.

**The file-descriptor limit.** Every socket is a descriptor, and Fly gives a
process 10,240. The connection count plateaued at exactly 10,240 and fell off a
cliff — which is what a hard limit looks like, where running out of memory
arrives as a slowdown. Raising it to 262,144 in the Dockerfile moved the wall by
a factor of three.

**The same limit on the load generator.** This one fooled me twice: I raised it
on the server, re-ran, and got exactly 10,240 again. k6 opens a descriptor per
virtual user too.

**The ramp wasn't ramping.** My test staggered the channel *join* but not the
socket *connect*, so 24,000 sockets arrived in 21 seconds against a configured
130-second ramp. That OOMs the server at counts it holds comfortably when
connections arrive gradually — and adding a fourth gigabyte doesn't help,
because the problem is arrival rate, not capacity. Once the connects were paced,
the same machine held 28,240.

That last one is worth taking seriously outside a benchmark: a fleet of clients
reconnecting simultaneously after a deploy is precisely that shape. A jittered
reconnect backoff buys more than RAM does.

One measurement trap while you are at it: `:erlang.memory()` reported about
1 GB where the kernel killed the process at 2.7 GB RSS. The gap is allocator
overhead, and the OOM killer reads RSS.

## The part where I was wrong

Three separate times, this benchmark produced clean, plausible, completely
wrong numbers. None of them looked like errors.

**`fly scale vm --yes` is not a flag.** That flag belongs to `fly deploy`. The
command exited non-zero with `unknown flag` and my script did not check exit
codes, so seven cells in a row ran on the same machine. The resulting table read
like a scaling curve. It was one machine's burst credits draining.

**`fly machine restart --select` needs a terminal.** Without one it selects
nothing and exits successfully. The plugin directory was staged correctly, the
app never reloaded, and every plugin call returned `plugin_not_found` — while
the non-plugin scenarios passed cleanly. A cell that is half broken is much
worse than one that is obviously broken.

**Sharing accounts between sockets created a race.** To avoid the socket ramp
measuring registration throughput, I spread sockets across a pool of shared
accounts. But `/login/device` is find-or-create, so fifty virtual users assigned
to the same new account all missed the lookup, all inserted, and all but one hit
the unique constraint. 98% of logins failed. The sockets themselves were fine —
the joins that got through took 3.5ms — so it read as "the server cannot take
it". The fix was creating the accounts once, before the run.

The lesson I actually took from this: **a benchmark must verify its own
premises.** The harness now reads the machine size back off the machine before
applying load and refuses the cell if it disagrees, and it logs the verified
hardware next to the results. Nothing downstream can catch a benchmark that
measured the wrong box — the numbers look fine, they are just about something
else.

## What I would rent

For a game with device login and moderate writes, `performance-1x` at $32/month
is the first size worth quoting: one dedicated core, ~500 registrations/s,
~750 writes/s, ~10,000 concurrent players.

Below that, the shared sizes are genuinely good value if your traffic is
read-heavy and bursty — a $16 `shared-cpu-8x` serves cached reads faster than a
$129 box — as long as you understand you are buying burst, not capacity.

Above it, you are buying writes and bcrypt, both of which scale with cores
almost exactly.

The harness is in [`stress/`](https://github.com/appsinacup/gamend/tree/main/stress)
and runs against your own deployment. The full per-size table lives in the
[Performance guide](/docs/performance).
