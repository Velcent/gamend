#!/usr/bin/env bash
#
# Drive the whole hardware/DB matrix on Fly, one cell at a time.
#
#   ./matrix.sh              # every cell
#   ./matrix.sh B F          # just these
#   DRY_RUN=1 ./matrix.sh    # print what it would do
#
# A cell is (database, machine size). For each one this resizes the bench app,
# waits for it to be healthy, runs the suite and the journeys from the k6
# machine in the same region, and pulls the summaries back into
# stress/results/. Machines bill per second, so the cost is roughly the time
# this takes, not the monthly price of the sizes it walks through.
#
# What it will NOT do on its own: create the apps, create the Postgres cluster,
# set secrets, or destroy anything. Those are one-time, they cost money, and
# they are printed by `./matrix.sh --setup` for you to run yourself.

set -uo pipefail

cd "$(dirname "$0")"
FLY_DIR="$(pwd)"
STRESS_DIR="$(cd .. && pwd)"

BENCH_APP="${BENCH_APP:-gamend-bench}"
K6_APP="${K6_APP:-gamend-k6}"
PG_APP="${PG_APP:-gamend-bench-pg}"
REGION="${REGION:-ams}"
BENCH_URL="${BENCH_URL:-http://${BENCH_APP}.internal:4000}"
PUBLIC_URL="${PUBLIC_URL:-https://${BENCH_APP}.fly.dev}"

# Per-cell load. The defaults are a full run; drop them for a rehearsal.
SUITE_VUS="${SUITE_VUS:-200}"
SUITE_DURATION="${SUITE_DURATION:-60s}"
PEAK="${PEAK:-2000}"
RAMP="${RAMP:-5m}"
HOLD="${HOLD:-2m}"
SOCKETS="${SOCKETS:-5000}"
DWELL="${DWELL:-3m}"

# What to run per cell.
#
#   core  — six scenarios, one operation each. Every other scenario in the
#           suite is a combination of these, which is why the baseline table
#           shows them clustering around these numbers. This is what answers
#           "what does one action cost on this machine size", and it is the
#           right profile for sweeping hardware.
#   suite — all 21 isolated scenarios, flows included.
#   full  — suite plus the four journeys (capacity, idle sockets, connect
#           storm, fan-out). Those are a capacity question, not a per-size
#           one: run them once on the size you intend to ship, not on every
#           cell.
#
# Cost, measured: k6 adds ~4s of fixed overhead per scenario on top of
# DURATION, so a profile is `scenarios x (DURATION + 4s)`. At the 30s default
# that is ~3.5 min for core and ~12 min for suite. `full` adds ~20 min of
# journeys on top, which is where "45 minutes a cell" came from.
PROFILE="${PROFILE:-core}"

CORE_SCENARIOS="${CORE_SCENARIOS:-me hook_noop kv_write kv_write_locked auth_device auth_email}"

DRY_RUN="${DRY_RUN:-}"

# Apps this script must never touch, whatever the environment says. Every
# destructive verb below — `scale vm`, `machine restart`, `ssh console -C
# 'rm -rf ...'` — takes `-a $BENCH_APP`, so a stale export or a typo is the
# difference between a benchmark and an outage. Names are matched exactly.
#
# Add your own production apps here. Being on this list costs nothing if you
# never make the mistake, and is the only thing in the way if you do.
PROTECTED_APPS="${PROTECTED_APPS:-game-server-uro}"

assert_not_production() {
  local app="$1" role="$2"

  for protected in $PROTECTED_APPS; do
    if [ "$app" = "$protected" ]; then
      echo "REFUSING TO RUN: $role is '$app', which is on PROTECTED_APPS." >&2
      echo "This script resizes, restarts and wipes state on that app." >&2
      exit 1
    fi
  done
}

assert_not_production "$BENCH_APP" "BENCH_APP"
assert_not_production "$K6_APP" "K6_APP"
assert_not_production "$PG_APP" "PG_APP"

# The deploy takes its app name from fly.bench.toml while everything else takes
# it from $BENCH_APP. If those disagree the run deploys to one app and resizes
# another, which is how a bench run ends up restarting something else.
toml_app=$(sed -n 's/^app *= *"\(.*\)"/\1/p' fly.bench.toml | head -1)

if [ -n "$toml_app" ] && [ "$toml_app" != "$BENCH_APP" ]; then
  echo "REFUSING TO RUN: fly.bench.toml deploys to '$toml_app' but BENCH_APP is '$BENCH_APP'." >&2
  echo "Set BENCH_APP=$toml_app, or point -c at the matching config." >&2
  exit 1
fi

# cell | adapter | vm size | memory
#
# NOTE ON SHARED CPUs. A `shared-cpu-Nx` is not N cores. Each shared CPU gets a
# baseline quota of 5ms per 80ms — 6.25% of a core — and bursts above it by
# spending a credit balance that caps at 500 seconds. So a short run measures
# the burst and a long one measures the throttle, and which you get depends on
# how much the machine has been idle beforehand. That makes shared sizes
# unusable for a sustained throughput number, however tempting the price is.
# `performance-Nx` gets the full 80ms with no throttling.
#
# The shared cells below are kept because "what does the cheap box do" is a
# real question, but read them as burst behaviour, not as capacity. `matrix.sh`
# warns when a cell uses one.
#
# Memory ceilings are 2GB per shared CPU and 8GB per performance CPU, so
# shared-cpu-1x is capped at the 2048 the cells ask for, and performance-1x can
# go to 8192.
#
# SQLite stops at performance-8x: if it has already plateaued at 4x, a bigger
# box is not the answer to anything, and that plateau IS the result.
#
# Override the whole list to walk sizes this does not cover. The format is
# `cell|adapter|vm size|memory MB`, space-separated:
#
#   CELLS="I|sqlite|shared-cpu-2x|2048 J|sqlite|shared-cpu-8x|4096" ./matrix.sh
#
# Fly's sizes at time of writing: shared-cpu-1x/2x/4x/8x and
# performance-1x/2x/4x/8x/16x. Memory has a floor per size — `fly platform
# vm-sizes` lists the current set, and `fly scale vm` rejects a pairing it
# cannot honour, so a bad cell fails that cell rather than the run.
if [ -n "${CELLS:-}" ]; then
  read -r -a CELLS <<<"$CELLS"
else
CELLS=(
  "N|sqlite|performance-1x|3072"
  "A|sqlite|shared-cpu-1x|2048"
  "B|sqlite|shared-cpu-4x|2048"
  "C|sqlite|performance-4x|8192"
  "D|sqlite|performance-8x|16384"
  "E|postgres|shared-cpu-4x|2048"
  "F|postgres|performance-4x|8192"
  "G|postgres|performance-8x|16384"
  "H|postgres|performance-16x|32768"
)
fi

run() {
  echo "  \$ $*"
  [ -n "$DRY_RUN" ] && return 0

  if ! "$@"; then
    echo "  COMMAND FAILED: $*" >&2
    return 1
  fi
}

# Everything the bench needs to exist, created idempotently.
#
#   ./matrix.sh --setup            # do it
#   DRY_RUN=1 ./matrix.sh --setup  # print what it would do
#
# Idempotent because the interesting failure is running it twice: each step
# checks for what it creates and skips it. Safe to re-run after it fails
# halfway, which is how it will usually be run.
#
# It does NOT create the Postgres cluster. `fly postgres create` prints the
# password exactly once and never again, so a script that swallows it leaves
# you with a database you cannot connect to. That one step is yours; the
# command is printed, and passing the URL back in as PG_URL wires it up.
# Stop both machines without destroying anything. Neither app has auto-stop —
# the bench turns it off so a cell never measures its own cold start, and the k6
# app has no http_service to trigger it — so both run, and bill, until told
# otherwise. Between sessions that is a performance-2x sitting idle.
#
# Apps, volume and secrets survive, so the next run is `./matrix.sh A` rather
# than another setup.
if [ "${1:-}" = "--stop" ]; then
  for app in "$BENCH_APP" "$K6_APP"; do
    echo "── stopping $app ──"
    for id in $(fly machine list -a "$app" --json 2>/dev/null | grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4); do
      run fly machine stop "$id" -a "$app"
    done
  done
  echo
  echo "Machines stopped. The volume still bills; ./matrix.sh --destroy to see how to remove it."
  exit 0
fi

# Printed, not run. Destroying the volume loses nothing you cannot regenerate,
# but it is not a thing to do by accident on the strength of a typo'd flag.
if [ "${1:-}" = "--destroy" ]; then
  cat <<DESTROY
To remove everything this created (each is irreversible):

  fly apps destroy $BENCH_APP    # machine, volume and secrets with it
  fly apps destroy $K6_APP
  fly postgres detach --app $BENCH_APP $PG_APP 2>/dev/null
  fly apps destroy $PG_APP       # only if you created it

To keep the setup but stop paying for compute:  ./matrix.sh --stop
DESTROY
  exit 0
fi

if [ "${1:-}" = "--setup" ]; then
  if [ -z "$DRY_RUN" ] && ! fly auth whoami >/dev/null 2>&1; then
    echo "Not logged in to Fly. Run: fly auth login" >&2
    exit 1
  fi

  # Said out loud before anything is created, because "it spins up the matrix"
  # reads like eight machines and it is two. The matrix resizes ONE machine
  # through the sizes; it never runs two at once.
  bench_size=$(awk '/^\[\[vm\]\]/{f=1} f&&/size *=/{gsub(/.*"|".*/,"");print;exit}' fly.bench.toml)
  k6_size=$(awk '/^\[\[vm\]\]/{f=1} f&&/size *=/{gsub(/.*"|".*/,"");print;exit}' fly.k6.toml)

  cat <<PLAN
── what this creates ──
  2 apps          $BENCH_APP, $K6_APP        (app records: no machines, no cost)
  1 volume        bench_data, 10GB on $BENCH_APP    (billed while it exists)
  1 secret        GAMEND_AUTH_SECRET_KEY_BASE       (generated here)
  1 machine       $K6_APP @ ${k6_size:-performance-2x}      (the load generator)
  1 machine       $BENCH_APP @ ${bench_size:-shared-cpu-4x}   (the target, resized per cell)

  Two machines in total. The matrix resizes the bench machine through the
  sizes one cell at a time — it never starts a second one.

  Neither machine auto-stops, so both bill until \`./matrix.sh --stop\`.

PLAN

  app_exists() { fly apps list 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }
  secret_set() { fly secrets list -a "$1" 2>/dev/null | awk '{print $1}' | grep -qx "$2"; }

  echo "── apps ──"
  for app in "$BENCH_APP" "$K6_APP"; do
    if [ -z "$DRY_RUN" ] && app_exists "$app"; then
      echo "  $app already exists"
    else
      run fly apps create "$app" --org "${FLY_ORG:-personal}"
    fi
  done

  echo "── volume ──"
  if [ -z "$DRY_RUN" ] && fly volumes list -a "$BENCH_APP" 2>/dev/null | grep -q bench_data; then
    echo "  bench_data already exists"
  else
    run fly volumes create bench_data -a "$BENCH_APP" -r "$REGION" -s 10 --yes
  fi

  # The one secret the app refuses to boot without: `auth.secret_key_base` is
  # `required: :prod` with no gate, so a bench app without it raises "Missing
  # required configuration" and never becomes healthy. Generated here rather
  # than asked for — it signs nothing that outlives the bench.
  echo "── secrets ──"
  if [ -z "$DRY_RUN" ] && secret_set "$BENCH_APP" GAMEND_AUTH_SECRET_KEY_BASE; then
    echo "  GAMEND_AUTH_SECRET_KEY_BASE already set"
  elif [ -n "$DRY_RUN" ]; then
    echo "  \$ fly secrets set -a $BENCH_APP GAMEND_AUTH_SECRET_KEY_BASE=<generated>"
  else
    fly secrets set -a "$BENCH_APP" \
      GAMEND_AUTH_SECRET_KEY_BASE="$(openssl rand -base64 64 | tr -d '\n')" >/dev/null &&
      echo "  GAMEND_AUTH_SECRET_KEY_BASE generated and set"
  fi

  # Postgres cells only. PG_URL is what `fly postgres create` printed.
  if [ -n "${PG_URL:-}" ]; then
    run fly secrets set -a "$BENCH_APP" GAMEND_DB_URL="$PG_URL" GAMEND_DB_IPV6=true
  else
    echo "  GAMEND_DB_URL not set — SQLite cells (A-D) will run, Postgres cells (E-H) will not."
    echo "  To add them:"
    echo "    fly postgres create --name $PG_APP --region $REGION --vm-size performance-2x"
    echo "    PG_URL='ecto://postgres:<password>@$PG_APP.flycast:5432/gamend' ./matrix.sh --setup"
  fi

  echo "── generator ──"
  # Absolute paths, not relative. `fly deploy` resolves `-c` and `--dockerfile`
  # against the positional build directory rather than the shell's cwd, so
  # `-c fly.k6.toml` with `$STRESS_DIR` as the target looks for
  # `$STRESS_DIR/fly.k6.toml` and fails with "config file not found" — after
  # the bench app has already been created.
  run fly deploy -c "$FLY_DIR/fly.k6.toml" --dockerfile "$FLY_DIR/Dockerfile" "$STRESS_DIR"

  echo "── bench app ──"
  run fly deploy -c "$FLY_DIR/fly.bench.toml"

  echo
  echo "── what actually exists now ──"
  if [ -z "$DRY_RUN" ]; then
    for app in "$BENCH_APP" "$K6_APP"; do
      echo "  $app:"
      fly machine list -a "$app" 2>/dev/null | sed 's/^/    /' | head -5
    done
    echo "  (expect exactly one machine under each)"
  fi

  echo
  echo "Next: ./matrix.sh --status, then DRY_RUN=1 ./matrix.sh A, then ./matrix.sh A"
  echo "When you are done for the day: ./matrix.sh --stop"
  exit 0
fi

# k6 runs happen on the generator machine; this streams their output back.
k6_run() {
  local script="$1"
  shift

  local envs=""
  for kv in "$@"; do envs="$envs -e $kv"; done

  run fly ssh console -a "$K6_APP" -C \
    "k6 run --quiet$envs -e BASE_URL=$BENCH_URL /scripts/$script"
}

# The bench loads stress_hook ALONE, not the whole example set: example_hook
# submits a leaderboard score on every login and rejects matchmaking modes
# outside casual|ranked, so leaving it on charges core for a sample plugin's
# writes. The image ships both under modules/plugins_examples; this stages just
# the one onto the volume the app actually reads.
stage_plugins() {
  run fly ssh console -a "$BENCH_APP" -C \
    "sh -c 'rm -rf /data/bench_plugins && mkdir -p /data/bench_plugins && cp -R /app/modules/plugins_examples/stress_hook /data/bench_plugins/'"
  # Restarted by id, not `--select`. That flag opens an interactive picker, and
  # with no TTY it selects nothing and exits happily — so the copy landed, the
  # app never reloaded, and every plugin RPC answered `plugin_not_found` while
  # the non-plugin scenarios passed. A cell that looks half-broken rather than
  # broken is the expensive kind.
  local machines
  machines=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null | grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4)

  if [ -z "$machines" ] && [ -z "$DRY_RUN" ]; then
    echo "  no machines found on $BENCH_APP — cannot restart to load plugins" >&2
    return 1
  fi

  for id in $machines; do
    run fly machine restart "$id" -a "$BENCH_APP"
  done
}

# What the machine and the BEAM inside it are doing, right now.
#
# Runnable on its own (`./matrix.sh --status`) and from a second terminal while
# a cell is running, which is the point: a run that is slowly dying looks
# exactly like a run that is slowly working until you look.
#
# The three questions it answers, in the order they matter:
#   - is the machine even up, and has it been restarted? A restart count above
#     zero on a machine nobody restarted is an OOM kill or a crash loop.
#   - are Fly's own health checks passing?
#   - where is the memory inside the BEAM, and how close is RSS to the limit?
#     `fly machine status` shows the machine's memory ceiling; the BEAM's own
#     accounting is what says whether you are near it, and RSS is what the OOM
#     killer actually reads.
bench_status() {
  echo "── machine ──"
  fly machine list -a "$BENCH_APP" 2>/dev/null | head -5

  echo "── health checks ──"
  fly checks list -a "$BENCH_APP" 2>/dev/null | head -8

  echo "── restarts / OOM ──"
  # Fly restarts a machine the kernel OOM-killed, so the evidence is in the
  # log rather than in any status field. Both spellings appear depending on
  # whether the kernel or Fly's supervisor noticed first.
  local recent
  recent=$(fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -300)
  local oom
  oom=$(printf '%s\n' "$recent" | grep -ciE "out of memory|oom-killer|oom_kill|killed process|memory limit exceeded" || true)
  local restarts
  restarts=$(printf '%s\n' "$recent" | grep -ciE "machine started|Starting init" || true)
  echo "  OOM mentions in last 300 log lines: ${oom:-0}"
  echo "  machine starts in last 300 log lines: ${restarts:-0}  (>1 means it restarted)"

  echo "── BEAM memory ──"
  # From inside the app rather than from the platform: `fly machine status`
  # reports the machine's limit, not what the BEAM is holding, and the gap
  # between the two is the whole question.
  fly ssh console -a "$K6_APP" -C \
    "wget -q -O- --post-data='{\"plugin\":\"stress_hook\",\"fn\":\"stress_memory_breakdown\",\"args\":[3]}' --header='Content-Type: application/json' $BENCH_URL/api/v1/hooks/call" 2>/dev/null |
    head -c 600
  echo
}

if [ "${1:-}" = "--status" ]; then
  bench_status
  exit 0
fi

wait_healthy() {
  echo "  waiting for $BENCH_APP to be healthy"
  [ -n "$DRY_RUN" ] && return 0
  for _ in $(seq 1 60); do
    if fly ssh console -a "$K6_APP" -C "wget -q -O- $BENCH_URL/api/v1/health" >/dev/null 2>&1; then
      echo "  healthy"
      return 0
    fi
    sleep 5
  done

  # Never silently. "never became healthy" on its own sends you to the
  # dashboard to find out why; the three usual causes — a missing required
  # setting, an OOM kill, a machine that never started — are all visible here.
  echo "  never became healthy after 5 minutes. What the machine says:" >&2
  bench_status >&2
  echo "  last 40 log lines:" >&2
  fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -40 >&2
  return 1
}

# Check every cell against Fly's actual catalogue before touching anything.
#
# `fly scale vm` rejects an unknown size or an impossible memory pairing, but it
# does so in the middle of the run, after a deploy, with the previous cell's
# results already on disk — and a custom CELLS list is exactly where a typo
# lives. One API call up front turns that into a refusal to start.
#
# Memory is not validated against a range here because Fly's per-size ceiling
# is not in this output; `fly scale vm` remains the authority on that. The size
# name is the part that is cheap to get wrong.
validate_cells() {
  local sizes
  sizes=$(fly platform vm-sizes 2>/dev/null | awk '{print $1}' | grep -E '^(shared|performance)-')

  [ -z "$sizes" ] && return 0

  local bad=0
  for spec in "${CELLS[@]}"; do
    IFS='|' read -r cell adapter size memory <<<"$spec"

    if ! printf '%s\n' "$sizes" | grep -qx "$size"; then
      echo "cell $cell: '$size' is not a Fly machine size" >&2
      bad=1
    fi

    case "$adapter" in
      sqlite | postgres) ;;
      *)
        echo "cell $cell: adapter '$adapter' must be sqlite or postgres" >&2
        bad=1
        ;;
    esac

    if ! printf '%s' "$memory" | grep -qE '^[0-9]+$'; then
      echo "cell $cell: memory '$memory' must be a number in MB" >&2
      bad=1
    fi
  done

  if [ "$bad" -eq 1 ]; then
    echo >&2
    echo "Available sizes:" >&2
    printf '%s\n' "$sizes" | sed 's/^/  /' >&2
    exit 1
  fi
}

validate_cells

selected=("$@")

for spec in "${CELLS[@]}"; do
  IFS='|' read -r cell adapter size memory <<<"$spec"

  if [ ${#selected[@]} -gt 0 ] && ! printf '%s\n' "${selected[@]}" | grep -qx "$cell"; then
    continue
  fi

  echo
  echo "════════ cell $cell — $adapter on $size (${memory}MB) ════════"

  case "$size" in
    shared-*)
      echo "  NOTE: shared CPU — 6.25% of a core baseline, bursting from a credit"
      echo "        balance that caps at 500s. Treat the numbers as burst behaviour,"
      echo "        not as sustained capacity. Use performance-* to measure a ceiling."
      ;;
  esac

  # The adapter is compile-time, so switching database means switching image.
  image="ghcr.io/appsinacup/gamend:latest"
  [ "$adapter" = "postgres" ] && image="ghcr.io/appsinacup/gamend:latest-postgres"

  # Only the adapter decides the image, so walking four SQLite sizes is one
  # deploy and four resizes, not four deploys. The plugin directory lives on
  # the volume, which survives a resize, so it only needs staging when the
  # image actually changed. Ordering the cells by adapter (the default list
  # does) makes this two deploys for the whole matrix instead of eight —
  # several minutes a cell, which is most of the per-cell overhead.
  if [ "$image" != "${deployed_image:-}" ]; then
    run fly deploy -c fly.bench.toml --image "$image" --yes
    deployed_image="$image"
    redeployed=1
  else
    echo "  (image unchanged — skipping deploy)"
    redeployed=""
  fi

  # No `--yes` here. `fly deploy` takes it, `fly scale vm` does not, and passing
  # it makes the command exit non-zero with "unknown flag" without changing
  # anything — which is how seven cells were once measured on one machine.
  run fly scale vm "$size" --vm-memory "$memory" -a "$BENCH_APP" || continue

  # Read the size back off the machine and refuse the cell if it disagrees.
  # A benchmark whose hardware is assumed rather than verified produces a table
  # that looks like a scaling curve and is actually one machine's burst credits
  # draining. Nothing downstream can detect that; only this check can.
  if [ -z "$DRY_RUN" ]; then
    actual=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null |
      python3 -c "import sys,json;m=json.load(sys.stdin)[0]['config']['guest'];print(f\"{m['cpu_kind']}-{m['cpus']}x/{m['memory_mb']}\")" 2>/dev/null)
    expected="$(printf '%s' "$size" | sed 's/shared-cpu-/shared-/; s/performance-/performance-/')/$memory"
    # `fly` reports the kind as `shared`/`performance` and the count separately.
    want=$(printf '%s' "$size" | sed 's/shared-cpu-\([0-9]*\)x/shared-\1x/; s/performance-\([0-9]*\)x/performance-\1x/')/"$memory"

    if [ "$actual" != "$want" ]; then
      echo "  SIZE MISMATCH: asked for $want, machine reports ${actual:-unknown}" >&2
      echo "  Skipping cell $cell rather than recording numbers for the wrong hardware." >&2
      continue
    fi

    echo "  verified hardware: $actual"
    # Written next to the results so the size is in the record, not just in a
    # terminal that scrolled away.
    printf '%s\t%s\t%s\t%s\n' "$cell" "$adapter" "$actual" "$(date -u +%FT%TZ)" \
      >>"$STRESS_DIR/results/hardware.tsv"
  fi

  wait_healthy || continue

  if [ -n "$redeployed" ]; then
    stage_plugins
    wait_healthy || continue
  fi

  # Capture the server's own log for the whole cell. A run with a good p95 and
  # a page of DBConnection errors underneath it is a failed run, and k6 cannot
  # see that from the outside.
  logfile="$STRESS_DIR/results/${cell}.log"
  if [ -z "$DRY_RUN" ]; then
    fly logs -a "$BENCH_APP" >"$logfile" 2>&1 &
    logs_pid=$!
  fi

  case "$PROFILE" in
    core) scenario_args="$CORE_SCENARIOS" ;;
    *) scenario_args="" ;;
  esac

  echo "── scenarios ($PROFILE) ──"
  run fly ssh console -a "$K6_APP" -C \
    "bash -lc 'cd /scripts && CELL=$cell BASE_URL=$BENCH_URL VUS=$SUITE_VUS DURATION=$SUITE_DURATION ./suite.sh $scenario_args'"

  if [ "$PROFILE" = "full" ]; then
    echo "── capacity ──"
    k6_run "journeys/player_session.js" "CELL=$cell" "PEAK=$PEAK" "RAMP=$RAMP" "HOLD=$HOLD"

    echo "── idle sockets ──"
    k6_run "journeys/ws_idle.js" "CELL=$cell" "SOCKETS=$SOCKETS" "DWELL=$DWELL"

    echo "── connect storm ──"
    k6_run "journeys/ws_storm.js" "CELL=$cell" "SOCKETS=$SOCKETS" "HOLD=60s"

    echo "── global topic fan-out ──"
    k6_run "journeys/lobbies_storm.js" "CELL=$cell"
  fi

  if [ -z "$DRY_RUN" ]; then
    kill "$logs_pid" 2>/dev/null
    echo "── errors in $cell.log ──"
    grep -c "\[error\]" "$logfile" 2>/dev/null | sed 's/^/  [error] lines: /'
    grep -c "\*\* (" "$logfile" 2>/dev/null | sed 's/^/  exceptions:   /'

    # A cell that OOM-killed mid-run still produces a results file, and its
    # numbers look like a machine that got slower rather than one that died.
    # This is the difference.
    oom=$(grep -ciE "out of memory|oom-killer|oom_kill|killed process|memory limit exceeded" "$logfile" 2>/dev/null || echo 0)
    if [ "${oom:-0}" -gt 0 ]; then
      echo "  *** OOM: $oom mentions — treat this cell's numbers as invalid ***"
    fi
    echo "── resources at end of cell ──"
    bench_status | sed 's/^/  /'
  fi

  echo "── fetching results ──"
  # File by file. `fly ssh sftp get` takes a single remote file — pointed at a
  # directory it reports nothing and copies nothing, which looks exactly like a
  # cell that produced no results.
  if [ -z "$DRY_RUN" ]; then
    for f in $(fly ssh console -a "$K6_APP" -C "ls /results" 2>/dev/null | tr -d '\r' | grep "^${cell}-"); do
      fly ssh console -a "$K6_APP" -C "cat /results/$f" 2>/dev/null |
        grep -v '^Connecting to' >"$STRESS_DIR/results/$f"
      echo "  $f ($(wc -c <"$STRESS_DIR/results/$f" | tr -d ' ') bytes)"
    done
  else
    echo "  \$ (fetch $cell-*.json from $K6_APP:/results)"
  fi
done

# What is still running, and what it costs to leave it that way.
#
# The trap this exists for: the bench machine keeps whatever size the LAST cell
# set. Finish on cell H and walk away and you are renting a performance-16x —
# about $515/month — to do nothing. The run itself is pennies; only forgetting
# is expensive.
#
# Approximate ams list prices, per month, at each size's base memory. Fly bills
# per second, so treat these as "if left running for 30 days".
price_for() {
  case "$1" in
    shared-cpu-1x) echo "~\$6" ;;
    shared-cpu-2x) echo "~\$7" ;;
    shared-cpu-4x) echo "~\$8" ;;
    shared-cpu-8x) echo "~\$16" ;;
    performance-1x) echo "~\$32" ;;
    performance-2x) echo "~\$64" ;;
    performance-4x) echo "~\$129" ;;
    performance-8x) echo "~\$258" ;;
    performance-16x) echo "~\$515" ;;
    *) echo "?" ;;
  esac
}

echo
echo "════════ all cells done ════════"

if [ -z "$DRY_RUN" ]; then
  last_size=$(fly machine list -a "$BENCH_APP" 2>/dev/null | awk 'NR>1 && $0 ~ /(shared|performance)-/ {for(i=1;i<=NF;i++) if ($i ~ /^(shared|performance)-/) {print $i; exit}}')

  echo
  echo "┌─ STILL RUNNING ─────────────────────────────────────────────"
  echo "│  $BENCH_APP   ${last_size:-unknown}   $(price_for "${last_size:-x}")/month if left up"
  echo "│  $K6_APP      performance-2x   ~\$64/month if left up"
  echo "│"
  echo "│  The run itself cost pennies — machines bill per second. Only"
  echo "│  leaving them up is expensive, and the bench keeps whatever size"
  echo "│  the last cell set."
  echo "│"
  echo "│    ./matrix.sh --stop      stop both, keep apps/volume/secrets"
  echo "│    ./matrix.sh --destroy   remove everything"
  echo "└─────────────────────────────────────────────────────────────"
fi

[ -z "$DRY_RUN" ] && node "$STRESS_DIR/report.mjs" "$STRESS_DIR/results"
