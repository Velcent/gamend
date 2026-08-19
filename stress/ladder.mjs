#!/usr/bin/env node
/**
 * Render a hardware ladder: the same scenarios across machine sizes.
 *
 * `report.mjs` answers "what did this run cost per operation" for one machine.
 * This answers the other question — "what does the next size up buy me" — which
 * is the one you ask before choosing what to rent. Rows are operations, columns
 * are machine sizes, and the plot is throughput against size.
 *
 *   node ladder.mjs results/                     # table
 *   node ladder.mjs results/ --svg out.svg       # + scaling plot
 *   node ladder.mjs results/ --md out.md         # + markdown file
 *
 * Cells come from the filename (`P2-me.json` is cell P2), and their hardware
 * and price come from the table below rather than from the summaries, because
 * a k6 summary knows what it measured and not what it ran on.
 *
 * Zero dependencies, same as the rest of the harness.
 */

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// cell -> hardware. `cores` is the sustained share of a core, not the marketing
// number: a shared CPU gets 5ms per 80ms, so shared-cpu-1x is 1/16th of a core
// once its burst credits are gone. Plotting the marketing number would draw a
// scaling curve that is mostly Fly's billing model.
const HARDWARE = {
  S1: { size: 'shared-cpu-1x', ram: '1 GB', cores: 0.0625, usd: 6, shared: true },
  S4: { size: 'shared-cpu-4x', ram: '1 GB', cores: 0.25, usd: 8, shared: true },
  S8: { size: 'shared-cpu-8x', ram: '2 GB', cores: 0.5, usd: 16, shared: true },
  P1: { size: 'performance-1x', ram: '2 GB', cores: 1, usd: 32 },
  N: { size: 'performance-1x', ram: '3 GB', cores: 1, usd: 37 },
  P2: { size: 'performance-2x', ram: '4 GB', cores: 2, usd: 64 },
  P4: { size: 'performance-4x', ram: '8 GB', cores: 4, usd: 129 },
  P8: { size: 'performance-8x', ram: '16 GB', cores: 8, usd: 258 },
};

const ORDER = ['S1', 'S4', 'S8', 'P1', 'N', 'P2', 'P4', 'P8'];

// The six core scenarios, in the order that makes them subtract: each line adds
// one layer to the one above it.
const SCENARIOS = [
  ['me', 'cached read'],
  ['hook_noop', 'plugin call, no database'],
  ['kv_write', 'write'],
  ['kv_write_locked', 'write inside a lock'],
  ['auth_device', 'registration'],
  ['auth_email', 'email login (bcrypt)'],
];

function load(dir) {
  const data = {};

  for (const file of readdirSync(dir)) {
    const match = file.match(/^([A-Z]\d?)-(.+)\.json$/);
    if (!match) continue;

    const [, cell, scenario] = match;
    if (!HARDWARE[cell]) continue;

    let raw;
    try {
      raw = JSON.parse(readFileSync(join(dir, file), 'utf8'));
    } catch {
      continue;
    }

    const m = raw.metrics || {};
    const v = (name, key) => m[name]?.values?.[key] ?? null;

    (data[cell] ??= {})[scenario] = {
      rps: v('http_reqs', 'rate'),
      med: v('http_req_duration', 'med'),
      p95: v('http_req_duration', 'p(95)'),
      checks: v('checks', 'rate'),
      errors: v('http_req_failed', 'rate'),
      vus: raw.vus,
    };
  }

  return data;
}

const fmt = (n) => (n === null || n === undefined ? '—' : n >= 100 ? Math.round(n).toLocaleString() : n.toFixed(1));

function table(data, cells) {
  const out = [];
  const head = ['operation', ...cells.map((c) => `${HARDWARE[c].size.replace('shared-cpu', 'shared').replace('performance', 'perf')}<br>${HARDWARE[c].ram}`)];

  out.push(`| ${head.join(' | ')} |`);
  out.push(`|${head.map((_, i) => (i === 0 ? '---' : '---:')).join('|')}|`);

  for (const [key, label] of SCENARIOS) {
    const row = [label];
    for (const c of cells) row.push(fmt(data[c]?.[key]?.rps));
    out.push(`| ${row.join(' | ')} |`);
  }

  out.push(`| **$/month** | ${cells.map((c) => `**$${HARDWARE[c].usd}**`).join(' | ')} |`);
  return out.join('\n');
}

// Health is reported separately and never folded into the throughput table: a
// cell that failed its checks has numbers, and they are worse than no numbers
// because they look like data.
function health(data, cells) {
  const bad = [];

  for (const c of cells) {
    for (const [key] of SCENARIOS) {
      const r = data[c]?.[key];
      if (!r) continue;
      if (r.checks !== null && r.checks < 0.99) bad.push(`${c}/${key}: checks ${(r.checks * 100).toFixed(1)}%`);
      if (r.errors !== null && r.errors > 0.01) bad.push(`${c}/${key}: errors ${(r.errors * 100).toFixed(1)}%`);
    }
  }

  return bad;
}

function svg(data, cells) {
  const W = 760;
  const H = 420;
  const PAD = { l: 70, r: 150, t: 40, b: 60 };
  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;

  const series = SCENARIOS.map(([key, label]) => ({
    label,
    points: cells.map((c, i) => ({ x: i, y: data[c]?.[key]?.rps ?? null })).filter((p) => p.y !== null),
  })).filter((s) => s.points.length > 1);

  const max = Math.max(...series.flatMap((s) => s.points.map((p) => p.y)));

  // Log scale: `me` and `auth_email` are four orders of magnitude apart, and on
  // a linear axis every line except the top one is flat against zero.
  const lo = 1;
  const y = (v) => PAD.t + plotH - (Math.log10(Math.max(v, lo)) / Math.log10(max)) * plotH;
  const x = (i) => PAD.l + (cells.length === 1 ? plotW / 2 : (i / (cells.length - 1)) * plotW);

  const colors = ['#2563eb', '#16a34a', '#ea580c', '#dc2626', '#7c3aed', '#0891b2'];
  const parts = [];

  parts.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="ui-sans-serif,system-ui,sans-serif" font-size="12">`);
  parts.push(`<rect width="${W}" height="${H}" fill="none"/>`);

  for (const tick of [1, 10, 100, 1000, 10000]) {
    if (tick > max) break;
    parts.push(`<line x1="${PAD.l}" y1="${y(tick)}" x2="${PAD.l + plotW}" y2="${y(tick)}" stroke="currentColor" stroke-opacity="0.12"/>`);
    parts.push(`<text x="${PAD.l - 8}" y="${y(tick) + 4}" text-anchor="end" fill="currentColor" fill-opacity="0.55">${tick.toLocaleString()}</text>`);
  }

  cells.forEach((c, i) => {
    parts.push(`<text x="${x(i)}" y="${PAD.t + plotH + 20}" text-anchor="middle" fill="currentColor" fill-opacity="0.75">${HARDWARE[c].size.replace('shared-cpu-', 'sh-').replace('performance-', 'perf-')}</text>`);
    parts.push(`<text x="${x(i)}" y="${PAD.t + plotH + 36}" text-anchor="middle" fill="currentColor" fill-opacity="0.45">$${HARDWARE[c].usd}</text>`);
  });

  series.forEach((s, si) => {
    const d = s.points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(p.x)},${y(p.y)}`).join(' ');
    parts.push(`<path d="${d}" fill="none" stroke="${colors[si % colors.length]}" stroke-width="2"/>`);
    for (const p of s.points) {
      parts.push(`<circle cx="${x(p.x)}" cy="${y(p.y)}" r="3" fill="${colors[si % colors.length]}"/>`);
    }
    const last = s.points[s.points.length - 1];
    parts.push(`<text x="${x(last.x) + 8}" y="${y(last.y) + 4}" fill="${colors[si % colors.length]}">${s.label}</text>`);
  });

  parts.push(`<text x="${PAD.l}" y="22" fill="currentColor" font-weight="600">Requests per second by machine size (log scale)</text>`);
  parts.push('</svg>');
  return parts.join('\n');
}

const args = process.argv.slice(2);
const dir = args[0] || 'results';
const data = load(dir);
const cells = ORDER.filter((c) => data[c]);

if (cells.length === 0) {
  console.error(`no ladder cells found in ${dir}/ (expected files like P2-me.json)`);
  process.exit(1);
}

const md = table(data, cells);
console.log(md);

const problems = health(data, cells);
if (problems.length) {
  console.log('\n**Cells with failed checks or errors — do not quote these:**\n');
  for (const p of problems) console.log(`- ${p}`);
}

const svgIdx = args.indexOf('--svg');
if (svgIdx !== -1 && args[svgIdx + 1]) {
  writeFileSync(args[svgIdx + 1], svg(data, cells));
  console.error(`wrote ${args[svgIdx + 1]}`);
}

const mdIdx = args.indexOf('--md');
if (mdIdx !== -1 && args[mdIdx + 1]) {
  writeFileSync(args[mdIdx + 1], md + '\n');
  console.error(`wrote ${args[mdIdx + 1]}`);
}
