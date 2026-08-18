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

## What a laptop number means

Only one thing: the same laptop, before and after your change. k6 and the server
share your cores, so past a few dozen virtual users you are partly measuring
that. For a figure you intend to quote, run the server on its own machine with
the generator in the same region — see the harness README for the Fly setup.

A worked example, including hardware, is committed at
[`stress/baselines/`](https://github.com/appsinacup/gamend/tree/main/stress/baselines).

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
