"""Peak concurrent sockets from a sampler CSV, and whether the server broke.

Separate from the shell that calls it because an inline heredoc inside a script
that also does shell substitution is one edit away from being executed as
shell — which is exactly what happened to the previous version.
"""

import csv
import sys

path, cell, size, memory, target, oom, out = sys.argv[1:8]

rows = [r for r in csv.DictReader(open(path)) if r.get("port_count")]
if not rows:
    print("  no samples")
    raise SystemExit

peak = max(rows, key=lambda r: int(r["port_count"]))
peak_n = int(peak["port_count"])
mem = float(peak["mem_processes_mb"]) + float(peak["mem_binary_mb"])

# A collapse is the count falling by more than half after the peak — the shape
# a crash makes. A run that simply ran out of ramp declines gently instead.
after = [int(r["port_count"]) for r in rows if int(r["elapsed_s"]) > int(peak["elapsed_s"])]
collapsed = bool(after) and min(after) < peak_n * 0.5
verdict = "CRASHED" if int(oom) > 0 else ("collapsed" if collapsed else "held (ramp ended)")

print(f"  PEAK {peak_n:,} | {mem:.0f} MB | {mem * 1024 / peak_n:.0f} KB/socket | {verdict}")

lines = [l for l in open(out) if not l.startswith(cell + "\t")]
lines.append(
    f"{cell}\t{size}\t{memory}\t{target}\t{peak_n}\t"
    f"{peak['mem_processes_mb']}\t{peak['mem_binary_mb']}\t{oom}\t{verdict}\n"
)
open(out, "w").writelines(lines)
