#!/usr/bin/env bash
#
# Idle-socket ceiling driven by several load generators at once.
#
# One k6 machine holds roughly 25,000-28,000 virtual users before its own
# memory runs out (~600 KB each), and that ceiling is indistinguishable from a
# server ceiling in the results: cells N (3 GB) and P2 (4 GB) both stopped at
# exactly 28,240, which is the generator, not gamend. Past that the load has to
# come from more than one machine.
#
#   ./socket_multi.sh P4 performance-4x 8192 60000 4
#     cell, size, memory MB, total sockets, generator count
#
# The peak is read from the SERVER's port count, so it sums across generators
# without the script having to add anything up.
set -uo pipefail
cd "$(dirname "$0")"
STRESS_DIR="$(cd .. && pwd)"

CELL="${1:?cell}"; SIZE="${2:?size}"; MEM="${3:?memory MB}"
TOTAL="${4:?total sockets}"; GENS="${5:-4}"

BENCH_APP="${BENCH_APP:-gamend-bench}"
K6_APP="${K6_APP:-gamend-k6}"
BENCH_URL="http://${BENCH_APP}.internal:4000"

for p in ${PROTECTED_APPS:-game-server-uro}; do
  [ "$BENCH_APP" = "$p" ] && { echo "REFUSING: protected app" >&2; exit 1; }
done

PER=$(( TOTAL / GENS ))
ACCOUNTS=$(( TOTAL / 100 ))
[ "$ACCOUNTS" -lt 50 ] && ACCOUNTS=50

echo "════════ $CELL — $SIZE ${MEM}MB — $TOTAL sockets across $GENS generators ($PER each) ════════"

fly scale vm "$SIZE" --vm-memory "$MEM" -a "$BENCH_APP" >/dev/null 2>&1 || { echo "  scale failed"; exit 1; }
actual=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null |
  python3 -c "import sys,json;g=json.load(sys.stdin)[0]['config']['guest'];print(f\"{g['cpu_kind']}-{g['cpus']}x/{g['memory_mb']}\")" 2>/dev/null)
want=$(printf '%s' "$SIZE" | sed 's/shared-cpu-/shared-/')/"$MEM"
[ "$actual" != "$want" ] && { echo "  SIZE MISMATCH: want $want got $actual"; exit 1; }
echo "  verified bench: $actual"

fly scale count "$GENS" -a "$K6_APP" --yes >/dev/null 2>&1
sleep 20

# Machine ids to a file, then `while read`. `for id in $(...)` does not
# word-split in zsh, which silently launched one generator instead of four.
fly machine list -a "$K6_APP" --json 2>/dev/null |
  grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4 >/tmp/k6ids
echo "  generators: $(wc -l </tmp/k6ids | tr -d ' ')"

# Read the id list on fd 3, not stdin. `fly ssh console` reads stdin, so a
# plain `while read ... done < file` loop has its own input consumed by the
# first iteration's ssh — which launched one generator out of four and looked
# like the server refusing connections.
while read -r id <&3; do fly machine start "$id" -a "$K6_APP" >/dev/null 2>&1; done 3</tmp/k6ids
sleep 25

for _ in $(seq 1 45); do
  [ "$(fly ssh console -a "$K6_APP" -C "wget -q -O- $BENCH_URL/api/v1/health" 2>/dev/null | grep -c ok)" -ge 1 ] && break
  sleep 10
done

while read -r id <&3; do
  fly ssh console -a "$K6_APP" --machine "$id" -C "sh -c 'cat > /tmp/gen5.sh'" </tmp/gen5.sh >/dev/null 2>&1
  fly ssh console -a "$K6_APP" --machine "$id" -C "sh -c 'cat > /tmp/sampler3.sh'" </tmp/sampler3.sh >/dev/null 2>&1
  fly ssh console -a "$K6_APP" --machine "$id" \
    -C "sh -c 'setsid sh /tmp/gen5.sh $PER $ACCOUNTS ${DWELL:-40s} ${RAMP:-360s} </dev/null >/tmp/gen.out 2>&1 &'" </dev/null >/dev/null 2>&1
  echo "  launched $PER on $id"
done 3</tmp/k6ids

SAMPLER=$(head -1 /tmp/k6ids)
fly ssh console -a "$K6_APP" --machine "$SAMPLER" -C "sh /tmp/sampler3.sh /tmp/ts.csv 620" 2>/dev/null |
  grep -vE "Connecting|No machine" >"$STRESS_DIR/results/sockets-$CELL.csv"

oom=$(fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -120 |
  grep -ciE "out of memory|oom-killer|oom_kill|killed process" || echo 0)

python3 - "$STRESS_DIR/results/sockets-$CELL.csv" "$CELL" "$actual" "$MEM" "$TOTAL" "$oom" \
  "$STRESS_DIR/results/sockets.tsv" <<'PY'
import csv, sys
path, cell, size, memory, target, oom, out = sys.argv[1:8]
rows = list(csv.DictReader(open(path)))
if not rows:
    print("  no samples"); raise SystemExit
peak = max(rows, key=lambda r: int(r["port_count"]))
mem = float(peak["mem_processes_mb"]) + float(peak["mem_binary_mb"])
print(f"  PEAK {int(peak['port_count']):,} sockets | {mem:.0f} MB | {mem*1024/int(peak['port_count']):.0f} KB/socket | OOM {oom}")
lines = [l for l in open(out) if not l.startswith(cell + "\t")]
lines.append(f"{cell}\t{size}\t{memory}\t{target}\t{peak['port_count']}\t{peak['mem_processes_mb']}\t{peak['mem_binary_mb']}\t{oom}\n")
open(out, "w").writelines(lines)
PY
