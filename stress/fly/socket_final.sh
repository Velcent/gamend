#!/usr/bin/env bash
#
# Ramp every machine size until it actually breaks, and record where.
#
# Built around what proved reliable rather than what was tidy: generators are
# driven by parallel backgrounded `fly ssh console` calls (a serial loop stalls
# whenever one handshake hangs), and the server is sampled with curl against
# its public /metrics from the machine running this script (sampling over SSH
# hung twice and cost twenty minutes each time).
#
# Targets are ~1.5x each size's previously observed peak so every cell has room
# to fail, and the ramp is held near 330 sockets/s — the rate above which the
# earlier runs OOMed on arrival rate rather than on capacity, which is a
# different finding and must not be confused with a ceiling.
set -uo pipefail
cd "$(dirname "$0")"
STRESS_DIR="$(cd .. && pwd)"

BENCH_APP="${BENCH_APP:-gamend-bench}"
K6_APP="${K6_APP:-gamend-k6}"
HEALTH="https://${BENCH_APP}.fly.dev/api/v1/health"
METRICS="https://${BENCH_APP}.fly.dev/metrics"
GENS="${GENS:-8}"

for p in ${PROTECTED_APPS:-game-server-uro}; do
  [ "$BENCH_APP" = "$p" ] && { echo "REFUSING: protected app" >&2; exit 1; }
done

# cell | size | memory MB | target | ramp seconds
CELLS=(
  "S4|shared-cpu-4x|1024|16000|120"
  "S8|shared-cpu-8x|2048|34000|120"
  "P1|performance-1x|2048|34000|120"
  "N|performance-1x|3072|56000|180"
  "P2|performance-2x|4096|76000|240"
  "P4|performance-4x|8192|110000|335"
)

selected=("$@")
TSV="$STRESS_DIR/results/sockets.tsv"
[ -f "$TSV" ] || printf 'cell\tsize\tmemory_mb\ttarget\tpeak_sockets\tmem_mb\toom\tverdict\n' >"$TSV"

fly scale count "$GENS" -a "$K6_APP" --yes >/dev/null 2>&1
sleep 20
fly machine list -a "$K6_APP" --json 2>/dev/null | grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4 >/tmp/k6ids
while read -r id <&3; do fly machine start "$id" -a "$K6_APP" >/dev/null 2>&1 & done 3</tmp/k6ids
wait
echo "generators ready: $(wc -l </tmp/k6ids | tr -d ' ')"

for spec in "${CELLS[@]}"; do
  IFS='|' read -r cell size memory target ramp <<<"$spec"
  if [ ${#selected[@]} -gt 0 ] && ! printf '%s\n' "${selected[@]}" | grep -qx "$cell"; then continue; fi

  gens=$(wc -l </tmp/k6ids | tr -d ' ')
  per=$(( target / gens ))
  accounts=$(( target / 120 )); [ "$accounts" -lt 50 ] && accounts=50

  echo
  echo "════════ $cell — $size ${memory}MB — ramp to $target over ${ramp}s ($(( target / ramp ))/s) ════════"

  fly scale vm "$size" --vm-memory "$memory" -a "$BENCH_APP" >/dev/null 2>&1 || { echo "  scale failed"; continue; }
  actual=$(fly machine list -a "$BENCH_APP" --json 2>/dev/null |
    python3 -c "import sys,json;g=json.load(sys.stdin)[0]['config']['guest'];print(f\"{g['cpu_kind']}-{g['cpus']}x/{g['memory_mb']}\")" 2>/dev/null)
  want=$(printf '%s' "$size" | sed 's/shared-cpu-/shared-/')/"$memory"
  [ "$actual" != "$want" ] && { echo "  SIZE MISMATCH: want $want got $actual"; continue; }

  # `fly scale vm` resizes but does not start a stopped machine, and the
  # previous cell may have left it stopped. Starting it here is what turns
  # "never healthy — skipping" back into a measurement.
  while read -r bid <&4; do fly machine start "$bid" -a "$BENCH_APP" >/dev/null 2>&1; done \
    4<<<"$(fly machine list -a "$BENCH_APP" --json 2>/dev/null | grep -oE '"id": *"[0-9a-f]{14}"' | cut -d'"' -f4)"

  ok=""
  for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$HEALTH" 2>/dev/null)" = "200" ] && { ok=1; break; }
    sleep 5
  done
  [ -z "$ok" ] && { echo "  never healthy — skipping"; continue; }
  echo "  verified $actual, healthy"

  while read -r id <&3; do
    ( fly ssh console -a "$K6_APP" --machine "$id" -C "sh -c 'cat > /tmp/gen5.sh'" </tmp/gen5.sh >/dev/null 2>&1
      fly ssh console -a "$K6_APP" --machine "$id" \
        -C "sh -c 'setsid sh /tmp/gen5.sh $per $accounts 40s ${ramp}s </dev/null >/tmp/gen.out 2>&1 &'" </dev/null >/dev/null 2>&1 ) &
  done 3</tmp/k6ids
  wait
  echo "  launched $per x $gens"

  csv="$STRESS_DIR/results/sockets-$cell.csv"
  echo "elapsed_s,port_count,mem_mb" >"$csv"
  start=$(date +%s); max=0; oom=0
  limit=$(( ramp + 120 ))
  while [ $(( $(date +%s) - start )) -lt "$limit" ]; do
    line=$(curl -s --max-time 8 "$METRICS" 2>/dev/null | awk -v t=$(( $(date +%s) - start )) '
      /^gamend_web_prom_ex_beam_stats_port_count /{pc=$2}
      /^gamend_web_prom_ex_beam_memory_processes_total_bytes /{mp=$2}
      /^gamend_web_prom_ex_beam_memory_binary_total_bytes /{mb=$2}
      END{if(pc!="")printf "%d,%d,%.1f", t, pc, (mp+mb)/1048576}')
    if [ -n "$line" ]; then
      echo "$line" >>"$csv"
      pc=$(echo "$line" | cut -d, -f2)
      [ "${pc:-0}" -gt "$max" ] && max=$pc
      if [ "$max" -gt 3000 ] && [ "${pc:-0}" -lt $(( max / 3 )) ]; then break; fi
    fi
    sleep 4
  done

  oom=$(fly logs -a "$BENCH_APP" --no-tail 2>/dev/null | tail -150 |
    grep -ciE "out of memory|oom-killer|oom_kill|killed process" || echo 0)
  hit=$([ "$max" -ge $(( target * 95 / 100 )) ] && echo yes || echo no)
  verdict=$([ "$oom" -gt 0 ] && echo CRASHED || { [ "$hit" = yes ] && echo "held (hit target)" || echo collapsed; })

  memat=$(awk -F, -v m="$max" '$2==m{print $3; exit}' "$csv")
  echo "  PEAK $max | ${memat:-?} MB | $verdict"
  lines=$(grep -v "^$cell	" "$TSV" || true)
  printf '%s\n' "$lines" >"$TSV"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$cell" "$actual" "$memory" "$target" "$max" "${memat:-0}" "$oom" "$verdict" >>"$TSV"
done

echo
echo "════════ done ════════"
column -t "$TSV" 2>/dev/null || cat "$TSV"
