#!/usr/bin/env bash
#
# Idle-socket ceiling for each machine size.
#
# `matrix.sh` measures operations per second; this measures how many connected
# players fit. It is separate because it needs a much larger load generator
# (k6 holds ~600 KB per virtual user, so 30,000 sockets is ~18 GB on the
# generator alone) and a paced ramp — arrival rate matters more than count.
#
#   ./socket_ladder.sh                 # every size
#   ./socket_ladder.sh P1 N            # just these
#
# Results append to results/sockets.tsv as: cell, size, target, peak, memory.
set -uo pipefail
cd "$(dirname "$0")"
FLY_DIR="$(pwd)"
STRESS_DIR="$(cd .. && pwd)"

BENCH_APP="${BENCH_APP:-gamend-bench}"
K6_APP="${K6_APP:-gamend-k6}"
BENCH_URL="http://${BENCH_APP}.internal:4000"
PROTECTED_APPS="${PROTECTED_APPS:-game-server-uro}"

for p in $PROTECTED_APPS; do
  [ "$BENCH_APP" = "$p" ] && { echo "REFUSING: BENCH_APP is protected" >&2; exit 1; }
done

# cell | size | memory MB | socket target | accounts
#
# Targets are set from the memory, at roughly the ~70 KB per socket the 3 GB
# box measured, then rounded down — the point is to find where each size stops,
# not to prove a number picked in advance. Accounts stay well below the socket
# count so the ramp measures sockets rather than registrations.
CELLS=(
  "S1|shared-cpu-1x|1024|9000|150"
  "S4|shared-cpu-4x|1024|9000|150"
  "S8|shared-cpu-8x|2048|18000|250"
  "P1|performance-1x|2048|18000|250"
  "N|performance-1x|3072|30000|300"
  "P2|performance-2x|4096|38000|350"
  "P4|performance-4x|8192|60000|400"
)

selected=("$@")
mkdir -p "$STRESS_DIR/results"
[ -f "$STRESS_DIR/results/sockets.tsv" ] ||
  printf 'cell\tsize\tmemory_mb\ttarget\tpeak_sockets\tmem_processes_mb\tmem_binary_mb\toom\n' \
    >"$STRESS_DIR/results/sockets.tsv"

k6_machine() {
  fly machine list -a "$K6_APP" --json 2>/dev/null |
    grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4 | head -1
}

wait_healthy() {
  for _ in $(seq 1 45); do
    [ "$(fly ssh console -a "$K6_APP" -C "wget -q -O- $BENCH_URL/api/v1/health" 2>/dev/null | grep -c ok)" -ge 1 ] && return 0
    sleep 10
  done
  return 1
}

for spec in "${CELLS[@]}"; do
  IFS='|' read -r cell size memory target accounts <<<"$spec"
  if [ ${#selected[@]} -gt 0 ] && ! printf '%s\n' "${selected[@]}" | grep -qx "$cell"; then continue; fi

  echo
  echo "════════ $cell — $size ${memory}MB, target ${target} sockets ════════"

  fly scale vm "$size" --vm-memory "$memory" -a "$BENCH_APP" >/dev/null 2>&1 || { echo "  scale failed"; continue; }

  actual=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null |
    python3 -c "import sys,json;g=json.load(sys.stdin)[0]['config']['guest'];print(f\"{g['cpu_kind']}-{g['cpus']}x/{g['memory_mb']}\")" 2>/dev/null)
  want=$(printf '%s' "$size" | sed 's/shared-cpu-/shared-/')/"$memory"
  [ "$actual" != "$want" ] && { echo "  SIZE MISMATCH: want $want got $actual — skipping"; continue; }
  echo "  verified $actual"

  wait_healthy || { echo "  never healthy — skipping"; continue; }

  K6=$(k6_machine)
  # Ramp always shorter than dwell, or the first sockets close while the last
  # are still connecting and the plateau never forms — which reads as a much
  # lower ceiling than the machine actually has.
  fly ssh console -a "$K6_APP" --machine "$K6" \
    -C "sh -c 'setsid sh /tmp/gen4.sh $target $accounts 400s 240s </dev/null >/tmp/gen.out 2>&1 &'" >/dev/null 2>&1

  fly ssh console -a "$K6_APP" --machine "$K6" -C "sh /tmp/sampler3.sh /tmp/ts.csv 560" 2>/dev/null |
    grep -vE "Connecting|No machine" >"$STRESS_DIR/results/sockets-$cell.csv"

  oom=$(fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -100 |
    grep -ciE "out of memory|oom-killer|oom_kill|killed process" || echo 0)

  python3 - "$STRESS_DIR/results/sockets-$cell.csv" "$cell" "$actual" "$memory" "$target" "$oom" \
    "$STRESS_DIR/results/sockets.tsv" <<'PY'
import csv, sys
path, cell, size, memory, target, oom, out = sys.argv[1:8]
rows = list(csv.DictReader(open(path)))
if not rows:
    print("  no samples"); raise SystemExit
peak = max(rows, key=lambda r: int(r["port_count"]))
print(f"  PEAK {int(peak['port_count']):,} sockets | {peak['mem_processes_mb']}MB proc + {peak['mem_binary_mb']}MB binary | OOM {oom}")
with open(out, "a") as f:
    f.write(f"{cell}\t{size}\t{memory}\t{target}\t{peak['port_count']}\t{peak['mem_processes_mb']}\t{peak['mem_binary_mb']}\t{oom}\n")
PY
done

echo
echo "════════ done — results/sockets.tsv ════════"
column -t "$STRESS_DIR/results/sockets.tsv" 2>/dev/null || cat "$STRESS_DIR/results/sockets.tsv"
