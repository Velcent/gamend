#!/usr/bin/env node
/**
 * Plot the socket ceiling against machine RAM.
 *
 * The companion to `timeseries.mjs`, which shows one run over time. This shows
 * every run's peak against the thing that turned out to determine it — memory,
 * not cores. Two sizes with the same RAM and a 2x CPU difference land on the
 * same point, which is the whole argument in one picture.
 *
 *   node sockets_chart.mjs results/sockets.tsv --svg out.svg
 */

import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const file = args[0] || 'results/sockets.tsv';

const lines = readFileSync(file, 'utf8').trim().split('\n');
const head = lines[0].split('\t');
const rows = lines
  .slice(1)
  .map((l) => Object.fromEntries(head.map((h, i) => [h, l.split('\t')[i]])))
  .filter((r) => r.peak_sockets && Number(r.peak_sockets) > 0)
  // A cell that never broke is not a ceiling; drawing it on the same line as
  // one that did would overstate the small sizes and understate the big ones.
  .map((r) => ({
    cell: r.cell,
    gb: Number(r.memory_mb) / 1024,
    peak: Number(r.peak_sockets),
    label: r.size.replace('shared-', 'sh-').replace('performance-', 'perf-').split('/')[0],
    crashed: (r.verdict || '').startsWith('CRASH') || (r.verdict || '') === 'collapsed',
  }))
  .sort((a, b) => a.gb - b.gb);

const W = 800;
const H = 430;
const PAD = { l: 76, r: 40, t: 52, b: 58 };
const plotW = W - PAD.l - PAD.r;
const plotH = H - PAD.t - PAD.b;

const maxGb = Math.max(...rows.map((r) => r.gb));
const maxPeak = Math.max(...rows.map((r) => r.peak));

const x = (gb) => PAD.l + (gb / (maxGb * 1.08)) * plotW;
const y = (v) => PAD.t + plotH - (v / (maxPeak * 1.12)) * plotH;

const p = [];
p.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="ui-sans-serif,system-ui,sans-serif" font-size="12">`);
p.push(`<text x="${PAD.l}" y="24" fill="currentColor" font-weight="600">Concurrent idle sockets by machine memory</text>`);
p.push(`<text x="${PAD.l}" y="41" fill="currentColor" fill-opacity="0.6">gamend on Fly, SQLite — filled = ran to failure, hollow = ramp ended first</text>`);

for (let i = 0; i <= 4; i++) {
  const v = (maxPeak * 1.12 * i) / 4;
  p.push(`<line x1="${PAD.l}" y1="${y(v)}" x2="${PAD.l + plotW}" y2="${y(v)}" stroke="currentColor" stroke-opacity="0.1"/>`);
  p.push(`<text x="${PAD.l - 8}" y="${y(v) + 4}" text-anchor="end" fill="currentColor" fill-opacity="0.6">${Math.round(v).toLocaleString()}</text>`);
}
for (let gb = 0; gb <= maxGb; gb += maxGb > 4 ? 2 : 1) {
  p.push(`<text x="${x(gb)}" y="${PAD.t + plotH + 20}" text-anchor="middle" fill="currentColor" fill-opacity="0.6">${gb} GB</text>`);
}
p.push(`<text x="${PAD.l + plotW / 2}" y="${H - 10}" text-anchor="middle" fill="currentColor" fill-opacity="0.6">machine memory</text>`);

// The measured slope, drawn from the cells that actually broke — so the line
// is a fit to real ceilings rather than to whatever the test happened to ask for.
const solid = rows.filter((r) => r.crashed);
const fit = solid.length >= 2 ? solid.reduce((s, r) => s + r.peak / r.gb, 0) / solid.length : null;
if (fit) {
  p.push(`<path d="M${x(0)},${y(0)} L${x(maxGb)},${y(fit * maxGb)}" stroke="#94a3b8" stroke-width="1.5" stroke-dasharray="5 4" fill="none"/>`);
  p.push(`<text x="${x(maxGb) - 6}" y="${y(fit * maxGb) - 8}" text-anchor="end" fill="#64748b">~${Math.round(fit / 100) * 100}/GB</text>`);
}

p.push(`<path d="${rows.map((r, i) => `${i === 0 ? 'M' : 'L'}${x(r.gb)},${y(r.peak)}`).join(' ')}" fill="none" stroke="#2563eb" stroke-width="2.5"/>`);

for (const r of rows) {
  p.push(`<circle cx="${x(r.gb)}" cy="${y(r.peak)}" r="5" fill="${r.crashed ? '#2563eb' : 'none'}" stroke="#2563eb" stroke-width="2"/>`);
  p.push(`<text x="${x(r.gb)}" y="${y(r.peak) - 14}" text-anchor="middle" fill="#2563eb" font-weight="600">${r.peak.toLocaleString()}</text>`);
  p.push(`<text x="${x(r.gb)}" y="${y(r.peak) + 22}" text-anchor="middle" fill="currentColor" fill-opacity="0.55">${r.label}</text>`);
}

p.push('</svg>');

const svgIdx = args.indexOf('--svg');
if (svgIdx !== -1 && args[svgIdx + 1]) {
  writeFileSync(args[svgIdx + 1], p.join('\n'));
  console.log(`wrote ${args[svgIdx + 1]}`);
}
for (const r of rows) console.log(`  ${r.label.padEnd(16)} ${r.gb} GB  ${r.peak.toLocaleString().padStart(8)}  ${r.crashed ? 'ran to failure' : 'ramp ended first'}`);
