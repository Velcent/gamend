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

DRY_RUN="${DRY_RUN:-}"

# cell | adapter | vm size | memory
#
# Memory is pinned at 2 GB on the shared sizes so CPU is the only variable
# there. SQLite stops at performance-8x: if it has already plateaued at 4x,
# a bigger box is not the answer to anything, and that plateau IS the result.
CELLS=(
  "A|sqlite|shared-cpu-1x|2048"
  "B|sqlite|shared-cpu-4x|2048"
  "C|sqlite|performance-4x|8192"
  "D|sqlite|performance-8x|16384"
  "E|postgres|shared-cpu-4x|2048"
  "F|postgres|performance-4x|8192"
  "G|postgres|performance-8x|16384"
  "H|postgres|performance-16x|32768"
)

if [ "${1:-}" = "--setup" ]; then
  cat <<SETUP
One-time setup (run these yourself — they create billable resources):

  fly auth login

  # The bench target and its volume
  fly apps create $BENCH_APP
  fly volumes create bench_data -a $BENCH_APP -r $REGION -s 10

  # The generator, in the same region
  fly apps create $K6_APP
  fly deploy -c fly.k6.toml --dockerfile Dockerfile "$STRESS_DIR"

  # Postgres for cells E-H. Kept at one size across every app size on purpose,
  # so the app machine is the only thing changing.
  fly postgres create --name $PG_APP --region $REGION --vm-size performance-2x
  fly secrets set -a $BENCH_APP \\
    GAMEND_DB_URL='ecto://postgres:<password>@${PG_APP}.flycast:5432/gamend' \\
    GAMEND_DB_IPV6=true

  # First deploy of the SQLite image
  fly deploy -c fly.bench.toml

Then: ./matrix.sh
SETUP
  exit 0
fi

run() {
  echo "  \$ $*"
  [ -n "$DRY_RUN" ] && return 0
  "$@"
}

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
  # Plugins are loaded at boot, so the copy only takes effect after a restart.
  run fly machine restart -a "$BENCH_APP" --select
}

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
  echo "  never became healthy — skipping this cell" >&2
  return 1
}

selected=("$@")

for spec in "${CELLS[@]}"; do
  IFS='|' read -r cell adapter size memory <<<"$spec"

  if [ ${#selected[@]} -gt 0 ] && ! printf '%s\n' "${selected[@]}" | grep -qx "$cell"; then
    continue
  fi

  echo
  echo "════════ cell $cell — $adapter on $size (${memory}MB) ════════"

  # The adapter is compile-time, so switching database means switching image.
  image="ghcr.io/appsinacup/gamend:latest"
  [ "$adapter" = "postgres" ] && image="ghcr.io/appsinacup/gamend:latest-postgres"

  run fly deploy -c fly.bench.toml --image "$image" --yes
  run fly scale vm "$size" --vm-memory "$memory" -a "$BENCH_APP" --yes

  wait_healthy || continue
  stage_plugins
  wait_healthy || continue

  # Capture the server's own log for the whole cell. A run with a good p95 and
  # a page of DBConnection errors underneath it is a failed run, and k6 cannot
  # see that from the outside.
  logfile="$STRESS_DIR/results/${cell}.log"
  if [ -z "$DRY_RUN" ]; then
    fly logs -a "$BENCH_APP" >"$logfile" 2>&1 &
    logs_pid=$!
  fi

  echo "── suite ──"
  run fly ssh console -a "$K6_APP" -C \
    "bash -lc 'cd /scripts && CELL=$cell BASE_URL=$BENCH_URL VUS=$SUITE_VUS DURATION=$SUITE_DURATION ./suite.sh'"

  echo "── capacity ──"
  k6_run "journeys/player_session.js" "CELL=$cell" "PEAK=$PEAK" "RAMP=$RAMP" "HOLD=$HOLD"

  echo "── idle sockets ──"
  k6_run "journeys/ws_idle.js" "CELL=$cell" "SOCKETS=$SOCKETS" "DWELL=$DWELL"

  echo "── connect storm ──"
  k6_run "journeys/ws_storm.js" "CELL=$cell" "SOCKETS=$SOCKETS" "HOLD=60s"

  echo "── global topic fan-out ──"
  k6_run "journeys/lobbies_storm.js" "CELL=$cell"

  if [ -z "$DRY_RUN" ]; then
    kill "$logs_pid" 2>/dev/null
    echo "── errors in $cell.log ──"
    grep -c "\[error\]" "$logfile" 2>/dev/null | sed 's/^/  [error] lines: /'
    grep -c "\*\* (" "$logfile" 2>/dev/null | sed 's/^/  exceptions:   /'
  fi

  echo "── fetching results ──"
  run fly ssh sftp get -a "$K6_APP" "/results" "$STRESS_DIR/results/"
done

echo
echo "════════ all cells done ════════"
[ -z "$DRY_RUN" ] && node "$STRESS_DIR/report.mjs" "$STRESS_DIR/results"
