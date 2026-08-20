#!/usr/bin/env node
/**
 * Socket ceiling against machine memory — every size measured, with price.
 *
 * One line: how many connections a machine holds when they arrive at a normal
 * rate, which is the number you size from. It is linear in memory and flat in
 * CPU, so the picture is the argument — the two 2 GB boxes sit on top of each
 * other at 4x the price difference, and that overlap is the whole point.
 *
 * A reconnect storm is a different question with a different answer (the 3 GB
 * box dies at 40% memory used) and belongs in prose, not on this axis — the
 * two share an x-axis but not a mechanism.
 *
 *   node sockets_chart.mjs results/sockets.tsv --svg out.svg
 */

import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const lines = readFileSync(args[0] || 'results/sockets.tsv', 'utf8').trim().split('\n');
const head = lines[0].split('\t');
const rows = lines.slice(1).map((l) => {
  const c = l.split('\t');
  return Object.fromEntries(head.map((h, i) => [h, c[i]]));
});

// Mid-tone hues only: the docs render on both a light and a dark background,
// and a 600-level fill that reads well on white goes muddy on dark.
// Nakama's published figure for a single node, the one shape where they and we
// have measured the same thing. Drawn open rather than filled so it is legible
// as someone else's number: everything solid on this chart came out of the
// harness in this repo.
const NAKAMA = { gb: 3, sockets: 20277, label: 'Nakama', note: '1 vCPU · 3 GB · published' };

const COLOUR = {
  S1: '#94a3b8',
  S4: '#06b6d4',
  S8: '#22c55e',
  P1: '#f97316',
  N: '#ef4444',
  P2: '#a855f7',
};

// Placement is hand-tuned per point rather than solved: six points, and a
// solver would take longer to write than the labels it is placing. The line
// only ever rises, so below-right and above-left of a point are always clear
// of it — every label uses one or the other.
const PLACE = {
  S1: { dx: 12, dy: 18, anchor: 'start' },
  S4: { dx: -12, dy: -8, anchor: 'end' },
  S8: { dx: -12, dy: -10, anchor: 'end' },
  P1: { dx: 12, dy: 18, anchor: 'start' },
  N: { dx: -12, dy: -10, anchor: 'end' },
  P2: { dx: -12, dy: -10, anchor: 'end' },
};

const pts = rows
  .map((r) => ({
    cell: r.cell,
    gb: Number(r.memory_mb) / 1024,
    slow: r.slow_ramp_peak ? Number(r.slow_ramp_peak) : null,
    usd: Number(r.usd_month),
    size: r.size,
    colour: COLOUR[r.cell] || '#2563eb',
    approx: r.cell === 'S1', // throttled ramp, see the performance page
  }))
  .filter((p) => p.slow)
  .sort((a, b) => a.gb - b.gb || a.slow - b.slow);

const W = 940, H = 500;
const PAD = { l: 100, r: 215, t: 56, b: 62 };
const pw = W - PAD.l - PAD.r, ph = H - PAD.t - PAD.b;
const maxGb = 5;
const maxY = 62000;

const x = (gb) => PAD.l + (gb / maxGb) * pw;
const y = (v) => PAD.t + ph - (v / maxY) * ph;

// sockets ≈ 14,500 × GB − 6,500, the fit quoted on the performance page.
const fit = (gb) => 14500 * gb - 6500;

// This SVG is embedded with <img src>, not inlined, so it is an isolated
// document: `var(--ink)` would resolve to black regardless of the page, which
// is invisible on the dark docs theme. It therefore carries its own ink *and*
// its own surface, switched together — the site picks its theme from
// localStorage before falling back to the OS, so `prefers-color-scheme` here can
// legitimately disagree with the page, and only a self-consistent fg/bg pair
// stays legible when it does.
const o = [];
o.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" font-family="ui-sans-serif,system-ui,sans-serif" font-size="12">`);
o.push(`<style>:root{--ink:#0f172a;--bg:#ffffff}@media (prefers-color-scheme:dark){:root{--ink:#e2e8f0;--bg:#0f172a}}</style>`);
o.push(`<rect width="${W}" height="${H}" rx="10" fill="var(--bg)"/>`);
o.push(`<text x="${PAD.l}" y="26" fill="var(--ink)" font-size="15" font-weight="600">Concurrent idle players, by machine</text>`);

for (let i = 0; i <= 6; i++) {
  const v = (maxY * i) / 6;
  o.push(`<line x1="${PAD.l}" y1="${y(v)}" x2="${PAD.l + pw}" y2="${y(v)}" stroke="var(--ink)" stroke-opacity="0.09"/>`);
  o.push(`<text x="${PAD.l - 16}" y="${y(v) + 4}" text-anchor="end" fill="var(--ink)" fill-opacity="0.55">${(v / 1000).toFixed(0)}k</text>`);
}
for (let gb = 1; gb <= maxGb; gb++) {
  o.push(`<text x="${x(gb)}" y="${PAD.t + ph + 22}" text-anchor="middle" fill="var(--ink)" fill-opacity="0.55">${gb} GB</text>`);
}
o.push(`<text x="${PAD.l + pw / 2}" y="${H - 14}" text-anchor="middle" fill="var(--ink)" fill-opacity="0.55">machine memory</text>`);
o.push(`<text x="20" y="${PAD.t + ph / 2}" transform="rotate(-90 20 ${PAD.t + ph / 2})" text-anchor="middle" fill="var(--ink)" fill-opacity="0.55">concurrent connections</text>`);

// Neutral trend line, coloured markers on top: the colour carries which machine,
// so spending it on the line too would say nothing.
o.push(`<path d="${pts.map((q, i) => `${i === 0 ? 'M' : 'L'}${x(q.gb)},${y(q.slow)}`).join(' ')}" fill="none" stroke="var(--ink)" stroke-opacity="0.45" stroke-width="2.5"/>`);

const nx = x(NAKAMA.gb), ny = y(NAKAMA.sockets);
o.push(`<rect x="${nx - 5}" y="${ny - 5}" width="10" height="10" fill="none" stroke="var(--ink)" stroke-opacity="0.7" stroke-width="1.8"/>`);
o.push(`<text x="${nx + 13}" y="${ny + 4}" fill="var(--ink)" fill-opacity="0.75" font-weight="600">${NAKAMA.label}</text>`);

// shared-cpu-8x and performance-1x/2 GB landed 26 apart — the same dot at this
// scale. Split it rather than letting one colour hide the other, since "these
// two are the same point" is exactly what the chart is there to show.
const groups = new Map();
for (const q of pts) {
  const k = `${Math.round(x(q.gb))},${Math.round(y(q.slow))}`;
  groups.set(k, [...(groups.get(k) || []), q]);
}
const R = 5.5;
for (const [, g] of groups) {
  const cx = x(g[0].gb), cy = y(g[0].slow);
  if (g.length === 1) {
    o.push(`<circle cx="${cx}" cy="${cy}" r="${R}" fill="${g[0].colour}"/>`);
  } else {
    g.forEach((q, i) => {
      const sweep = i === 0 ? 0 : 1; // 0 = left half, 1 = right half
      o.push(`<path d="M${cx},${cy - R} A${R},${R} 0 0 ${sweep} ${cx},${cy + R} Z" fill="${q.colour}"/>`);
    });
  }
}

for (const q of pts) {
  const p = PLACE[q.cell] || { dx: 12, dy: 18, anchor: 'start' };
  o.push(`<text x="${x(q.gb) + p.dx}" y="${y(q.slow) + p.dy}" text-anchor="${p.anchor}" fill="${q.colour}" font-weight="600">${q.size}</text>`);
}

const kx = PAD.l + pw + 30;
[...pts].sort((a, b) => a.usd - b.usd).forEach((q, i) => {
  const ky = PAD.t + 14 + i * 22;
  o.push(`<circle cx="${kx + 4}" cy="${ky - 4}" r="4.5" fill="${q.colour}"/>`);
  o.push(`<text x="${kx + 16}" y="${ky}" fill="var(--ink)" fill-opacity="0.85">${q.size} · ${q.gb} GB · $${q.usd}</text>`);
});
const nky = PAD.t + 14 + pts.length * 22 + 14;
o.push(`<rect x="${kx - 0.5}" y="${nky - 8.5}" width="9" height="9" fill="none" stroke="var(--ink)" stroke-opacity="0.7" stroke-width="1.6"/>`);
o.push(`<text x="${kx + 16}" y="${nky}" fill="var(--ink)" fill-opacity="0.8">${NAKAMA.label} · 1 vCPU · 3 GB</text>`);
o.push(`<text x="${kx + 16}" y="${nky + 14}" fill="var(--ink)" fill-opacity="0.5">published figure</text>`);

o.push('</svg>');

const i = args.indexOf('--svg');
if (i !== -1 && args[i + 1]) { writeFileSync(args[i + 1], o.join('\n')); console.log(`wrote ${args[i + 1]}`); }
for (const p of pts) {
  console.log(`  ${p.size.padEnd(15)} ${p.gb}GB $${String(p.usd).padStart(3)}  ${String(p.slow).padStart(7)}  fit ${String(Math.round(fit(p.gb))).padStart(7)}  ${((p.slow / fit(p.gb) - 1) * 100).toFixed(1)}%`);
}
