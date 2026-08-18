#!/usr/bin/env bash
#
# Run every isolated scenario in turn and print one table.
#
# Sequential on purpose: each scenario gets the whole machine, so the numbers
# are comparable to each other. Running them concurrently would measure how
# they interfere, which is what the journeys are for.
#
#   ./suite.sh                                    # local defaults
#   VUS=50 DURATION=60s ./suite.sh                # a real run
#   CELL=B BASE_URL=http://gamend-bench.internal:4000 VUS=200 DURATION=5m ./suite.sh
#
# Every summary lands in results/ as <CELL->name.json; report.mjs renders them.

set -uo pipefail

cd "$(dirname "$0")"

BASE_URL="${BASE_URL:-http://localhost:4000}"
VUS="${VUS:-10}"
DURATION="${DURATION:-30s}"
RESULTS_DIR="${RESULTS_DIR:-results}"
CELL="${CELL:-}"
# Seconds of quiet between scenarios, so one scenario's tail (a lobby sweep, a
# quest re-arm, cache expiry) is not charged to the next one's numbers.
SETTLE="${SETTLE:-3}"

# Ordered cheapest-first: if the box is already failing on `me`, the expensive
# scenarios below it will only tell you the same thing more slowly.
SCENARIOS=(
  me
  kv_read
  auth_device
  auth_refresh
  profile_write
  hooks_rpc
  lobbies_http
  lobby_ws
  ws_join_idle
  chat
  matchmaking
  groups
  quests
  leaderboards
  economy
  friends
  notifications
  web_pages
  auth_email
)

# One scenario can be selected: ./suite.sh chat
if [ $# -gt 0 ]; then
  SCENARIOS=("$@")
fi

mkdir -p "$RESULTS_DIR"

# Clear the summaries this run is about to replace. Without this, a scenario
# that fails to start leaves the previous run's row in the table, and a stale
# number that looks current is worse than a missing one.
for name in "${SCENARIOS[@]}"; do
  rm -f "${RESULTS_DIR}/${CELL:+${CELL}-}${name}.json"
done

echo "suite: ${#SCENARIOS[@]} scenarios against $BASE_URL (VUS=$VUS DURATION=$DURATION${CELL:+ CELL=$CELL})"

failed=()
skipped=()

for name in "${SCENARIOS[@]}"; do
  script="scenarios/${name}.js"

  if [ ! -f "$script" ]; then
    echo "  ~ $name (no such scenario, skipping)"
    skipped+=("$name")
    continue
  fi

  echo
  echo "── $name ─────────────────────────────────────────────"

  if ! BASE_URL="$BASE_URL" VUS="$VUS" DURATION="$DURATION" \
       RESULTS_DIR="$RESULTS_DIR" CELL="$CELL" \
       k6 run --quiet "$script"; then
    # A threshold breach is a result, not a reason to stop: the whole point of
    # the run is to find which scenarios break first on this machine.
    failed+=("$name")
  fi

  sleep "$SETTLE"
done

echo
echo "════════════════════════════════════════════════════════"
node report.mjs "$RESULTS_DIR"

if [ ${#skipped[@]} -gt 0 ]; then
  echo
  echo "Skipped (not written yet): ${skipped[*]}"
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo
  echo "Thresholds breached: ${failed[*]}"
  exit 1
fi
