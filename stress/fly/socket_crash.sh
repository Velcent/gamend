#!/usr/bin/env bash
#
# Ramp each machine size until the server actually breaks.
#
# Not a hold test: the question here is where the wall is, so every cell aims
# well above what the size is expected to take, ramps steadily into it, and
# holds only briefly. A cell that merely runs out of ramp is reported as
# "held", not as a ceiling — the two are different answers and conflating them
# is how a generator's limit gets published as a server's.
#
#   ./socket_crash.sh              # every size
#   ./socket_crash.sh P4           # one
#
set -uo pipefail
cd "$(dirname "$0")"
STRESS_DIR="$(cd .. && pwd)"

BENCH_APP="${BENCH_APP:-gamend-bench}"
K6_APP="${K6_APP:-gamend-k6}"
BENCH_URL="http://${BENCH_APP}.internal:4000"
PUBLIC_HEALTH="${PUBLIC_HEALTH:-https://${BENCH_APP}.fly.dev/api/v1/health}"

for p in ${PROTECTED_APPS:-game-server-uro}; do
  [ "$BENCH_APP" = "$p" ] && { echo "REFUSING: protected app" >&2; exit 1; }
done

# cell | size | memory MB | target | generators
#
# Targets are ~1.5x the linear prediction (~12,800 sockets per GB, measured on
# the 3 GB and 4 GB boxes) so every cell has room to fail rather than just
# running out of request. Generators hold ~15,000 virtual users each at
# performance-8x, so the count is set by the target, not by the server.
CELLS=(
  "S1|shared-cpu-1x|1024|16000|2"
  "S4|shared-cpu-4x|1024|16000|2"
  "S8|shared-cpu-8x|2048|32000|3"
  "P1|performance-1x|2048|32000|3"
  "N|performance-1x|3072|48000|4"
  "P2|performance-2x|4096|64000|5"
  "P4|performance-4x|8192|110000|8"
)

selected=("$@")
TSV="$STRESS_DIR/results/sockets.tsv"
[ -f "$TSV" ] || printf 'cell\tsize\tmemory_mb\ttarget\tpeak_sockets\tmem_processes_mb\tmem_binary_mb\toom\tverdict\n' >"$TSV"

for spec in "${CELLS[@]}"; do
  IFS='|' read -r cell size memory target gens <<<"$spec"
  if [ ${#selected[@]} -gt 0 ] && ! printf '%s\n' "${selected[@]}" | grep -qx "$cell"; then continue; fi

  per=$(( target / gens ))
  accounts=$(( target / 100 )); [ "$accounts" -lt 50 ] && accounts=50

  echo
  echo "════════ $cell — $size ${memory}MB — ramp to $target across $gens generators ════════"

  fly scale vm "$size" --vm-memory "$memory" -a "$BENCH_APP" >/dev/null 2>&1 || { echo "  scale failed"; continue; }
  actual=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null |
    python3 -c "import sys,json;g=json.load(sys.stdin)[0]['config']['guest'];print(f\"{g['cpu_kind']}-{g['cpus']}x/{g['memory_mb']}\")" 2>/dev/null)
  want=$(printf '%s' "$size" | sed 's/shared-cpu-/shared-/')/"$memory"
  [ "$actual" != "$want" ] && { echo "  SIZE MISMATCH: want $want got $actual"; continue; }
  echo "  verified bench: $actual"

  fly scale count "$gens" -a "$K6_APP" --yes >/dev/null 2>&1
  sleep 15
  fly machine list -a "$K6_APP" --json 2>/dev/null |
    grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4 >/tmp/k6ids
  echo "  generators: $(wc -l </tmp/k6ids | tr -d ' ')"

  # fd 3, because `fly ssh console` reads stdin and would eat the id list.
  while read -r id <&3; do fly machine start "$id" -a "$K6_APP" >/dev/null 2>&1; done 3</tmp/k6ids
  sleep 25

  # Readiness over the public URL, not over SSH into a generator. Each
  # `fly ssh console` costs a handshake and can hang outright with no timeout,
  # which turned a 45-try loop into an eleven-minute stall on a server that was
  # already answering. curl with a timeout answers in under a second.
  ok=""
  for _ in $(seq 1 40); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$PUBLIC_HEALTH" 2>/dev/null)
    [ "$code" = "200" ] && { ok=1; break; }
    sleep 5
  done
  [ -z "$ok" ] && { echo "  bench never healthy — skipping"; continue; }

  while read -r id <&3; do
    fly ssh console -a "$K6_APP" --machine "$id" -C "sh -c 'cat > /tmp/gen5.sh'" </tmp/gen5.sh >/dev/null 2>&1
    fly ssh console -a "$K6_APP" --machine "$id" -C "sh -c 'cat > /tmp/sampler4.sh'" </tmp/sampler4.sh >/dev/null 2>&1
    fly ssh console -a "$K6_APP" --machine "$id" \
      -C "sh -c 'setsid sh /tmp/gen5.sh $per $accounts 30s 150s </dev/null >/tmp/gen.out 2>&1 &'" </dev/null >/dev/null 2>&1
    echo "  launched $per on $id"
  done 3</tmp/k6ids

  sampler=$(head -1 /tmp/k6ids)
  fly ssh console -a "$K6_APP" --machine "$sampler" -C "sh /tmp/sampler4.sh /tmp/ts.csv 230" 2>/dev/null |
    grep -vE "Connecting|No machine" >"$STRESS_DIR/results/sockets-$cell.csv"

  oom=$(fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -150 |
    grep -ciE "out of memory|oom-killer|oom_kill|killed process" || echo 0)

  python3 socket_peak.py "$STRESS_DIR/results/sockets-$cell.csv" "$cell" "$actual" "$memory" "$target" "$oom" "$TSV"
done

echo
echo "════════ done ════════"
column -t "$TSV" 2>/dev/null || cat "$TSV"
