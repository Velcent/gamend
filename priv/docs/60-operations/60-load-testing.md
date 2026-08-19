---
icon: hero-bolt
---

# Load Testing

Measure what your deployment can actually take, with the k6 harness in
[`stress/`](https://github.com/appsinacup/gamend/tree/main/stress).

Two different questions, answered by two different tools:

- **What does an operation cost?** `stress/scenarios/` — one isolated scenario
  per feature (login, lobby create, chat, matchmaking, quests, hook RPCs …),
  run one at a time by `suite.sh`.
- **Where does it stop scaling?** `stress/sweep.sh` — one scenario up a ladder
  of concurrency levels, so you can see the knee.

## Before you run anything

Three settings, and skipping any of them makes the numbers meaningless.

**1. Run the server in `MIX_ENV=prod`.** Not a detail — dev mode checks for
changed files on every request, so a dev benchmark measures the code reloader.
The same read scenario on the same machine: **293 req/s in dev, 18,918 req/s in
prod.**

```bash
mix assets.deploy
MIX_ENV=prod GAMEND_AUTH_SECRET_KEY_BASE=$(mix phx.gen.secret) \
  GAMEND_DB_SQLITE_PATH=/tmp/bench.db \
  GAMEND_RATELIMIT_ENABLED=false \
  GAMEND_AUTH_DEVICE_AUTH_ENABLED=true \
  GAMEND_FEATURES_LIST_LOBBIES_ENABLED=true \
  GAMEND_FEATURES_LIST_GROUPS_ENABLED=true \
  mix phx.server
```

**2. Turn rate limiting off.** Limits are per IP — 10 auth requests and 240
general requests a minute. Every virtual user shares one IP, so a run with
limits on measures the limiter and nothing else. Confirm with the
`rate_limit deny` counter on `/metrics`: it must stay at zero.

**3. Load only the stress plugin.** The example plugin writes a leaderboard
score on *every login*; left loaded it charges your server for a sample
plugin's writes.

```bash
cd modules/plugins_examples/stress_hook && mix deps.get && mix compile && mix plugin.bundle && cd -
mkdir -p stress/.plugins && cp -R modules/plugins_examples/stress_hook stress/.plugins/
# then add to the server command above:
#   GAMEND_CONTENT_PLUGINS_DIR=stress/.plugins
```

Never point a load test at a production server you care about: the harness
creates users, lobbies and groups, and is designed to push a machine past the
point where it answers correctly.

## Run it

```bash
cd stress
BASE_URL=http://localhost:4000 VUS=30 DURATION=15s ./suite.sh
```

One scenario while you iterate:

```bash
BASE_URL=http://localhost:4000 k6 run --vus 2 --iterations 4 scenarios/chat.js
```

Find where a path stops scaling:

```bash
BASE_URL=http://localhost:4000 ./sweep.sh auth_device 5 15 30 60 120 240
```

Rising req/s with flat p95 means headroom. Flat req/s with rising p95 means
saturation — work is queueing, not going faster. Falling req/s means contention.

## Running the matrix on Fly

`stress/fly/matrix.sh` walks a list of (database, machine size) cells: for each
one it resizes the bench app, waits for health, runs the suite and the journeys
from a k6 machine in the same region, and pulls the summaries back.

It is a **separate app from production** by construction — its own app name, its
own volume, its own database file — because it runs with rate limiting off and
gets its state wiped between cells. Two guards enforce that rather than trusting
it: the script refuses to start if any target app is listed in `PROTECTED_APPS`,
and it refuses if `BENCH_APP` disagrees with the app name in `fly.bench.toml`
(which would deploy to one app and resize another). Put your production apps in
`PROTECTED_APPS`:

```bash
PROTECTED_APPS="game-server-uro my-other-app" ./matrix.sh
```

See what it would do without doing it:

```bash
DRY_RUN=1 ./matrix.sh
```

### Setup

```bash
fly auth login
DRY_RUN=1 ./matrix.sh --setup   # see what it would create
./matrix.sh --setup             # create it
```

Idempotent — every step checks for what it creates and skips it — so it is safe
to re-run after it fails halfway, which is how it will usually be run. It
creates the two apps, the 10 GB volume, and the one secret the app will not boot
without: `GAMEND_AUTH_SECRET_KEY_BASE` is `required: :prod` with no gate, so a
bench app missing it raises "Missing required configuration" and never becomes
healthy. It is generated here rather than asked for, because it signs nothing
that outlives the bench.

Nothing else is required. The other `required: :prod` settings are all gated —
`captcha.secret_key` on captcha being enabled, `cache.redis_url` on a multi-node
cache — and none of those gates hold for a single bench machine.

Postgres is the one manual step, and deliberately so: `fly postgres create`
prints the password exactly once, and a script that swallows it leaves you with
a database you cannot connect to. Create it, then hand the URL back:

```bash
fly postgres create --name gamend-bench-pg --region ams --vm-size performance-2x
PG_URL='ecto://postgres:<password>@gamend-bench-pg.flycast:5432/gamend' ./matrix.sh --setup
```

Without it, cells A-D (SQLite) run and E-H do not.

### How many machines this creates

**Two.** `--setup` prints exactly this before it creates anything:

```
  2 apps          gamend-bench, gamend-k6      (app records: no machines, no cost)
  1 volume        bench_data, 10GB             (billed while it exists)
  1 secret        GAMEND_AUTH_SECRET_KEY_BASE  (generated here)
  1 machine       gamend-k6    @ performance-2x  (the load generator)
  1 machine       gamend-bench @ shared-cpu-4x   (the target, resized per cell)
```

`fly apps create` makes an app record and no machine. Only the two `fly deploy`
steps create machines, one each. `fly.bench.toml` pins
`min_machines_running = 1` and `max_machines_running = 1`, so the bench app
cannot grow a second one.

The matrix does not start eight machines. It **resizes the same one** through
the sizes with `fly scale vm`, one cell at a time — which is why the cells run
in sequence, and why running one is the normal case:

```bash
./matrix.sh A          # one cell, one size, then stop and look
```

After setup it lists the machines under each app so the count is something you
read rather than trust.

### The two machines, and what the sizes mean

| app | role |
|---|---|
| `gamend-bench` | **the machine under test.** Runs gamend with rate limiting off and its database wiped between cells. This is what the numbers are about. |
| `gamend-k6` | **the load generator.** Runs k6, has no inbound port, and is driven over SSH. Same region as the bench on purpose — a generator elsewhere adds internet latency and jitter to every measurement, and at high VU counts the path becomes the bottleneck being measured. |

The `[[vm]]` block in `fly.bench.toml` is the **boot size only** — what the
machine comes up at during setup, and what you get if you deploy that config
without the matrix. Every cell overwrites it with `fly scale vm`. It is matched
to production rather than to the first cell, so a bench deployed on its own
looks like the thing it stands in for.

Fly's sizes, for reference (`fly platform vm-sizes`) — the memory column is the
*default* for that size, and the matrix asks for more:

```
shared-cpu-1x   1 core    256 MB        performance-1x    1 core   2048 MB
shared-cpu-2x   2 cores   512 MB        performance-2x    2 cores  4096 MB
shared-cpu-4x   4 cores  1024 MB        performance-4x    4 cores  8192 MB
shared-cpu-6x   6 cores  1536 MB        performance-8x    8 cores 16384 MB
shared-cpu-8x   8 cores  2048 MB        performance-16x  16 cores 32768 MB
```

The default cells pin 2 GB across the shared sizes so CPU is the only variable
there, which puts `shared-cpu-1x` at that size's memory ceiling. They do not
cover `shared-cpu-6x` or `performance-1x/6x/10x/12x/14x`; pass `CELLS` to walk
those.

Cells are validated against this catalogue before anything is created, so a
typo in a custom `CELLS` list is refused up front rather than in the middle of
a run:

```
cell X: 'performance-3x' is not a Fly machine size
cell Y: adapter 'mysql' must be sqlite or postgres
```

### Shared CPUs cannot measure a ceiling

A `shared-cpu-Nx` is not N cores. Each shared CPU gets a baseline quota of **5ms
per 80ms — 6.25% of a core** — and bursts above it by spending a credit balance
that caps at 500 seconds of full use. Once that balance is gone it drops to the
baseline.

So on a shared machine a short run measures the burst, a long run measures the
throttle, and which one you get depends on how idle the machine has been. That
is not a property of gamend, and it is not comparable between cells run back to
back. `performance-Nx` gets the full 80ms with no throttling.

**Use `performance-*` for any number you intend to quote.** The shared cells are
kept because "what does the cheap box do" is a real question, and `matrix.sh`
prints a warning when a cell uses one:

```
NOTE: shared CPU — 6.25% of a core baseline, bursting from a credit
      balance that caps at 500s. Treat the numbers as burst behaviour,
      not as sustained capacity.
```

Memory ceilings follow the CPU type: **2 GB per shared CPU, 8 GB per
performance CPU**. So `shared-cpu-1x` cannot exceed the 2048 MB the cells ask
for, while `performance-1x` can go to 8192 MB.

### Cell N: the Nakama comparison

Nakama publishes its numbers on a 1 CPU / 3 GB node, and the baseline in
`stress/` matched that locally by pinning the BEAM to one scheduler. Cell `N`
is the same shape on real hardware — one **dedicated** core and 3 GB:

```bash
./matrix.sh N
```

`performance-1x` rather than `shared-cpu-1x` is the whole point: a shared core
would be answering with burst credits, which is not a number anyone can compare
to.

### What it costs

Approximate Amsterdam list prices, per month at each size's base memory. Fly
bills **per second**, so a five-minute cell costs the monthly price divided by
roughly 8,760:

| size | cores | base RAM | per month | per 5-min cell |
|---|---:|---:|---:|---:|
| `shared-cpu-1x` | 6.25% | 1 GB | ~$6 | ~$0.001 |
| `shared-cpu-4x` | 25% | 1 GB | ~$8 | ~$0.001 |
| `performance-1x` | 1 | 2 GB | ~$32 | ~$0.004 |
| `performance-2x` | 2 | 4 GB | ~$64 | ~$0.007 |
| `performance-4x` | 4 | 8 GB | ~$129 | ~$0.015 |
| `performance-8x` | 8 | 16 GB | ~$258 | ~$0.029 |
| `performance-16x` | 16 | 32 GB | ~$515 | ~$0.059 |

Extra RAM beyond a size's base is about **$5/GB/month**; volumes are
**$0.15/GB/month**, so the 10 GB bench volume is ~$1.50/month and persists
whether or not anything is running. A stopped machine costs only its rootfs
storage.

**A full eight-cell run at `PROFILE=core` is well under a dollar** — the bench
machine spends about five minutes at each size, and the k6 machine runs
throughout at ~$0.09/hour.

The expensive mistake is not the run, it is forgetting to stop. **The bench
machine keeps whatever size the last cell set**, so finishing on cell H and
walking away rents a `performance-16x` — about $515/month — to do nothing. The
matrix now says so on the way out:

```
┌─ STILL RUNNING ─────────────────────────────────────────────
│  gamend-bench   performance-16x   ~$515/month if left up
│  gamend-k6      performance-2x    ~$64/month if left up
│
│    ./matrix.sh --stop      stop both, keep apps/volume/secrets
└─────────────────────────────────────────────────────────────
```

### What $5/month actually buys

A `shared-cpu-1x`. At 256 MB that is roughly $2/month, and at 1 GB about $6 —
so five dollars lands you between those, and the CPU is the same either way:
**6.25% of a core sustained**, bursting on credits that run out after ~500
seconds of real work.

Two things follow, and both are measured rather than assumed. gamend's own BEAM
sits around 400–500 MB at rest once a plugin and the caches are loaded, so
**256 MB is not enough to run it** and 512 MB is tight — the first thing that
happens under load is an OOM kill, not a slowdown. And the CPU is the harder
limit: a game server that throttles to 6.25% of a core is fine for a handful of
players and falls over under a connect storm.

For comparison, one *dedicated* core with 2 GB — `performance-1x` — is ~$32/month.
That is the real floor for a box you intend to quote numbers about, which is why
cell `N` uses it.

### Stopping the bill

Neither machine auto-stops. The bench app turns it off deliberately — a machine
that stops between runs measures its own cold start — and the k6 app has no
`http_service` to trigger it. So **both run, and bill, until you stop them**,
and between sessions that is a `performance-2x` sitting idle.

```bash
./matrix.sh --stop      # stop both machines; apps, volume and secrets survive
./matrix.sh --destroy   # prints the commands to remove everything
```

`--stop` leaves the setup intact, so the next session starts at `./matrix.sh A`
rather than another setup. The volume bills while it exists either way.

### Knowing it is actually up — and not quietly dying

`./matrix.sh --status` reports the three things that matter, and is safe to run
from a second terminal while a cell is in flight:

```
── machine ──          state, size, and how long it has been up
── health checks ──    Fly's own checks against /api/v1/health
── restarts / OOM ──   OOM mentions and machine starts in the recent log
── BEAM memory ──      total / processes / binary / ets, plus RSS
```

The restart count is the one to watch. Fly restarts a machine the kernel
OOM-killed, so a machine that has started more than once when nobody restarted
it is the signature — the log says `Out of memory: Killed process`, and the
run before it produced perfectly ordinary-looking numbers right up to the point
it died.

BEAM memory comes from inside the app (`stress_memory_breakdown`), not from the
platform, because `fly machine status` reports the machine's *limit* and the gap
between that limit and what the BEAM is holding is the entire question. RSS is
in there too, since RSS is what the OOM killer actually reads.

Two places this now fires on its own:

- **A cell that never becomes healthy** prints the full status plus the last 40
  log lines instead of "never became healthy". The three usual causes — a
  missing required setting, an OOM kill, a machine that never started — are all
  visible in that output.
- **A cell that OOM-killed mid-run** is flagged explicitly:
  `*** OOM: 3 mentions — treat this cell's numbers as invalid ***`. Worth having,
  because such a cell still writes a results file, and its numbers look like a
  machine that got slower rather than one that died.

For graphs rather than a snapshot, Fly scrapes the app's `/metrics` into its own
Prometheus (`[metrics]` in `fly.bench.toml`) and graphs it at fly-metrics.net
next to machine CPU, RAM and network. `fly logs -a gamend-bench` and
`fly machine list -a gamend-bench` are the terminal equivalents and are what
`--status` wraps.

### Pick a profile before you pick a machine

`PROFILE` decides what runs per cell, and it is the difference between an hour
and a day:

| profile | what runs | per cell at `SUITE_DURATION=30s` |
|---|---|---|
| `core` (default) | 6 scenarios, one operation each | ~3.5 min |
| `suite` | all 21 isolated scenarios | ~12 min |
| `full` | suite plus the four journeys | ~32 min |

The arithmetic is `scenarios x (DURATION + 4s)` — k6's fixed startup and
graceful stop measure at about four seconds, so at a 30s duration a third of a
short run is overhead. Longer durations amortise it.

`core` is the right profile for sweeping hardware, because the six scenarios it
runs are the distinct cost classes and everything else is a combination of them:

| scenario | the ceiling it finds |
|---|---|
| `me` | cached read — no database touched |
| `hook_noop` | plugin call with no database, so the hook layer's own cost |
| `kv_write` | one unlocked write |
| `kv_write_locked` | one write under an advisory lock |
| `auth_device` | registration, the slowest write a player makes |
| `auth_email` | bcrypt, the one path that is purely CPU |

Subtracting one from the next attributes cost. The flows (`friends` at 7
requests an iteration, `groups` and `lobbies_http` at 5) are combinations of
those ceilings and tell you nothing new about a machine size — run them on the
size you intend to ship, not on every cell. The journeys answer "how many
players fit", which is also a one-size question.

### Cost

Machines bill by the second, so the cost is the wall-clock of the run rather
than the monthly price of the sizes it walks. Two things dominate it, and both
are now handled: the profile above, and redeploys. Only the adapter decides the
image, so walking four SQLite sizes is one deploy and four resizes — the script
skips the deploy when the image has not changed, which turns eight deploys into
two for the default matrix.

What is left per cell is a resize (~1 min), a health wait (~1 min) and the
profile itself. At `PROFILE=core SUITE_DURATION=30s` the whole eight-cell
matrix is under an hour.

Run them one at a time when you want to look between sizes — the results
accumulate in `stress/results/` and `report.mjs` renders whatever is there:

```bash
./matrix.sh A     # shared-cpu-1x
./matrix.sh B     # shared-cpu-4x
node ../report.mjs ../results
```

Any size can be walked without editing the script:

```bash
CELLS="I|sqlite|shared-cpu-2x|2048 J|postgres|performance-2x|4096" ./matrix.sh
```

Remember to stop or destroy the bench machines when you are done — nothing in
the script does it for you, on purpose.

## Get the results

```bash
node report.mjs results/ --md results/report.md --page results/report.html
```

- **`report.md`** — every table plus unicode bar charts; renders anywhere a
  Markdown file renders, no image assets.
- **`report.html`** — a self-contained page: total requests, peak throughput,
  concurrent users, measured time, checks run and failed, error rate, bytes
  transferred, then throughput and latency charts and the per-scenario and
  per-operation tables. No network required, so it opens from a file path or
  anywhere you host it.

Add saturation curves, and compare two configurations on the same axes:

```bash
node report.mjs results/ --page results/report.html \
  --sweep SQLite=results/sweep --sweep Postgres=results/sweep_pg
```

Compare two runs — the loop for checking whether a change helped:

```bash
RESULTS_DIR=results/before ./suite.sh
# …make the change, restart the server…
RESULTS_DIR=results/after ./suite.sh
node report.mjs --diff results/before results/after
```

## Reading a run

```
| scenario     | VUs | rps  | med  | p95  | p99  | errors | checks |
| me           |  30 | 18607|  1.3 |  3.0 |  4.4 |  0.00% | 100.00%|
```

The column that decides whether a run counts is **checks**, not latency. Every
write scenario reads its own write back, so a cache serving stale data shows up
as a check failure while the timings still look excellent. A run with failed
checks is not a slower run, it is a wrong one.

Then look at your server for the same window — `/metrics` carries CPU, memory,
BEAM run queue, Ecto queue time and cache hit ratio. A good p95 sitting on a
page of database errors is a failed run the client cannot see.

Two numbers that are the scenario rather than the server: `matchmaking` waits on
the matchmaking sweep tick, and `ws_join_idle` holds a socket for its dwell and
makes almost no requests. Neither is a throughput measurement.

## What it measures, in practice

The last full run on a MacBook Air M1 (8 cores, production build, generator on
the same machine, so a floor rather than a ceiling):

| operation | SQLite | PostgreSQL |
|---|---:|---:|
| cached read | 17,489/s | 16,422/s |
| plugin call (no database) | 16,372/s | 12,616/s |
| write | 4,266/s | 5,472/s |
| write inside a lock | 966/s | 1,574/s |

Reads all cost the same, plugin or not. Writes are ~4x a read, and a locked
write ~4x again. Read the suite's **flows/s** column rather than req/s when
comparing scenarios: a flow that spends five requests is not slower than one
that spends one. [Performance](performance) has the full operation table, capacity per
gigabyte, per-socket memory, and the comparison with other game backends.

## What a laptop number means

Only one thing: the same laptop, before and after your change. k6 and the server
share your cores, so past a few dozen virtual users you are partly measuring
that. For a figure you intend to quote, run the server on its own machine with
the generator in the same region — see the harness README for the Fly setup.

## Writing your own scenario

The scenarios are short because everything shared lives in `stress/lib/`:
`auth.js` (device and email login), `api.js` (one wrapper per endpoint),
`phx.js` (a Phoenix channel client, so you can time realtime event delivery),
`hooks.js` (plugin RPCs) and `checks.js` (read-your-write assertions). Copy the
closest scenario and change the middle.

Your own game's operations belong in your own plugin: the harness reaches quest
progress, score submission and wallet credits through
`modules/plugins_examples/stress_hook`, because those are server-side operations
with no player-facing endpoint by design.
