#!/usr/bin/env bash
#
# Run one scenario at increasing VU counts and print the curve.
#
#   ./sweep.sh me                       # default ladder
#   ./sweep.sh hooks_rpc 10 50 100 200  # explicit ladder
#   VUS_LIST="10 100" DURATION=30s ./sweep.sh lobbies_http
#
# `suite.sh` answers "what does this cost". This answers "where does it stop
# scaling": throughput climbs with concurrency until something saturates, then
# flattens while latency keeps climbing. The knee — the last level where p95 is
# still inside the SLO — is the capacity of this machine for that operation.
#
# Read the three columns together. Rising rps with flat p95 means headroom.
# Flat rps with rising p95 means saturation: the work is queueing, not going
# faster. Rising errors means past it.

set -uo pipefail

cd "$(dirname "$0")"

SCENARIO="${1:-me}"
shift || true

BASE_URL="${BASE_URL:-http://localhost:4000}"
DURATION="${DURATION:-20s}"
SETTLE="${SETTLE:-3}"
RESULTS_DIR="${RESULTS_DIR:-results/sweep}"

if [ $# -gt 0 ]; then
  LEVELS=("$@")
else
  read -r -a LEVELS <<<"${VUS_LIST:-5 15 30 60 120 240}"
fi

script="scenarios/${SCENARIO}.js"
[ -f "$script" ] || { echo "no such scenario: $script" >&2; exit 1; }

mkdir -p "$RESULTS_DIR"

echo "sweep: $SCENARIO against $BASE_URL, ${DURATION} per level"
echo
printf '%6s  %10s  %10s  %10s  %10s  %8s\n' VUs req/s med p95 p99 errors
printf '%6s  %10s  %10s  %10s  %10s  %8s\n' ------ ---------- ---------- ---------- ---------- --------

for vus in "${LEVELS[@]}"; do
  # THINK=0 by default in lib/config.js — a sweep must not be pacing-bound, or
  # every level reports `vus / think` and the curve is a straight line.
  BASE_URL="$BASE_URL" VUS="$vus" DURATION="$DURATION" THINK="${THINK:-0}" \
    RESULTS_DIR="$RESULTS_DIR" CELL="vu${vus}" RUN_TAG="sweep${vus}" \
    k6 run --quiet "$script" >/dev/null 2>&1

  summary="${RESULTS_DIR}/vu${vus}-${SCENARIO}.json"
  if [ -f "$summary" ]; then
    node -e '
      const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).metrics;
      const v = (k) => (m[k] && m[k].values) || {};
      const d = v("http_req_duration");
      const f = (x, n = 1) => (x == null ? "-" : Number(x).toFixed(n));
      process.stdout.write(
        [process.argv[2], f(v("http_reqs").rate), f(d.med), f(d["p(95)"]), f(d["p(99)"]),
         f((v("http_req_failed").rate || 0) * 100, 2) + "%"]
          .map((s, i) => String(s).padStart(i === 0 ? 6 : i === 5 ? 8 : 10)).join("  ") + "\n",
      );
    ' "$summary" "$vus"
  else
    printf '%6s  %s\n' "$vus" "(no summary — the run failed to start)"
  fi

  sleep "$SETTLE"
done

echo
echo "summaries in ${RESULTS_DIR}/ — compare two levels with:"
echo "  node report.mjs --diff ${RESULTS_DIR}/vu5-${SCENARIO}.json ${RESULTS_DIR}/vu240-${SCENARIO}.json"
