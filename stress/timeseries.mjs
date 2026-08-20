#!/usr/bin/env node
/**
 * Plot a socket run against time.
 *
 * `ladder.mjs` puts machine size on the X axis, which answers "what does the
 * next tier buy". This answers the other question — "what happened during the
 * run" — which is the one a ramp-and-hold test is actually about: where the
 * connections plateaued, what memory did while they did, and whether the
 * plateau was a ceiling or a cliff.
 *
 *   node timeseries.mjs results/sockets-perf1x-3gb-timeseries.csv --svg out.svg
 *
 * Input is the CSV the sampler writes: elapsed_s, port_count, process_count,
 * mem_processes_mb, mem_binary_mb.
 */

import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const file = args[0];

if (!file) {
  console.error('usage: node timeseries.mjs <csv> [--svg out.svg] [--title "..."]');
  process.exit(1);
}

const titleIdx = args.indexOf('--title');
const title = titleIdx !== -1 ? args[titleIdx + 1] : 'Idle sockets over time';

const lines = readFileSync(file, 'utf8').trim().split('\n');
const head = lines[0].split(',');
const rows = lines.slice(1).map((l) => {
  const cells = l.split(',');
  return Object.fromEntries(head.map((h, i) => [h, Number(cells[i])]));
});

const W = 820;
const H = 420;
const PAD = { l: 66, r: 74, t: 46, b: 52 };
const plotW = W - PAD.l - PAD.r;
const plotH = H - PAD.t - PAD.b;

const maxT = Math.max(...rows.map((r) => r.elapsed_s));
const maxPorts = Math.max(...rows.map((r) => r.port_count));
const maxMem = Math.max(...rows.map((r) => r.mem_processes_mb + r.mem_binary_mb));

const x = (t) => PAD.l + (t / maxT) * plotW;
const yPorts = (v) => PAD.t + plotH - (v / (maxPorts * 1.1)) * plotH;
const yMem = (v) => PAD.t + plotH - (v / (maxMem * 1.1)) * plotH;

const p = [];
p.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="ui-sans-serif,system-ui,sans-serif" font-size="12">`);
p.push(`<text x="${PAD.l}" y="24" fill="currentColor" font-weight="600">${title}</text>`);

// Gridlines and the left axis, which is connections — the number the run is for.
for (let i = 0; i <= 4; i++) {
  const v = (maxPorts * 1.1 * i) / 4;
  p.push(`<line x1="${PAD.l}" y1="${yPorts(v)}" x2="${PAD.l + plotW}" y2="${yPorts(v)}" stroke="currentColor" stroke-opacity="0.1"/>`);
  p.push(`<text x="${PAD.l - 8}" y="${yPorts(v) + 4}" text-anchor="end" fill="#2563eb" fill-opacity="0.85">${Math.round(v).toLocaleString()}</text>`);
}

// Right axis: memory, so the two can be read against each other without
// pretending they share a scale.
for (let i = 0; i <= 4; i++) {
  const v = (maxMem * 1.1 * i) / 4;
  p.push(`<text x="${PAD.l + plotW + 8}" y="${yMem(v) + 4}" fill="#ea580c" fill-opacity="0.85">${Math.round(v)} MB</text>`);
}

for (let t = 0; t <= maxT; t += Math.max(30, Math.round(maxT / 8 / 30) * 30)) {
  p.push(`<text x="${x(t)}" y="${PAD.t + plotH + 20}" text-anchor="middle" fill="currentColor" fill-opacity="0.6">${t}s</text>`);
}
p.push(`<text x="${PAD.l + plotW / 2}" y="${H - 8}" text-anchor="middle" fill="currentColor" fill-opacity="0.6">elapsed</text>`);

const path = (accessor, scale) =>
  rows.map((r, i) => `${i === 0 ? 'M' : 'L'}${x(r.elapsed_s)},${scale(accessor(r))}`).join(' ');

p.push(`<path d="${path((r) => r.mem_processes_mb + r.mem_binary_mb, yMem)}" fill="none" stroke="#ea580c" stroke-width="2" stroke-opacity="0.85"/>`);
p.push(`<path d="${path((r) => r.port_count, yPorts)}" fill="none" stroke="#2563eb" stroke-width="2.5"/>`);

const peak = rows.reduce((a, b) => (b.port_count > a.port_count ? b : a));
p.push(`<circle cx="${x(peak.elapsed_s)}" cy="${yPorts(peak.port_count)}" r="4" fill="#2563eb"/>`);
p.push(`<text x="${x(peak.elapsed_s) + 8}" y="${yPorts(peak.port_count) - 8}" fill="#2563eb" font-weight="600">peak ${peak.port_count.toLocaleString()}</text>`);

p.push(`<text x="${PAD.l}" y="${PAD.t - 8}" fill="#2563eb">— open sockets (left)</text>`);
p.push(`<text x="${PAD.l + 170}" y="${PAD.t - 8}" fill="#ea580c">— server memory (right)</text>`);
p.push('</svg>');

const svgIdx = args.indexOf('--svg');
if (svgIdx !== -1 && args[svgIdx + 1]) {
  writeFileSync(args[svgIdx + 1], p.join('\n'));
  console.log(`wrote ${args[svgIdx + 1]}`);
} else {
  console.log(p.join('\n'));
}

console.log(`peak ${peak.port_count.toLocaleString()} sockets at t=${peak.elapsed_s}s, ${Math.round(peak.mem_processes_mb + peak.mem_binary_mb)} MB`);
