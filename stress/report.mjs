#!/usr/bin/env node
/**
 * Turn a folder of k6 summaries into one Markdown table, or diff two runs.
 *
 * The numbers only mean something next to each other: "lobby create p95 was
 * 40ms" is not a finding, "lobby create p95 went from 40ms to 95ms on the same
 * machine after this commit" is. So this does two things and nothing else —
 * render a run, and subtract two runs.
 *
 *   node report.mjs results/                      # one run, one table
 *   node report.mjs results/ --json               # machine-readable
 *   node report.mjs --diff baselines/B/ results/  # before → after
 *
 * Deliberately zero dependencies: it runs on the k6 machine, in CI, and on a
 * laptop with nothing installed.
 */

import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { renderMarkdown, renderPage, summarize } from './page.mjs';

const args = process.argv.slice(2);

if (args.includes('--help') || args.length === 0) {
  console.log(
    [
      'Usage:',
      '  node report.mjs <dir|file>...           render summaries as a Markdown table',
      '  node report.mjs --diff <before> <after> compare two runs',
      '  node report.mjs <dir> --json            emit JSON instead of Markdown',
      '  node report.mjs <dir> --md <file>       write a full Markdown report',
      '  node report.mjs <dir> --page <file>     write a self-contained HTML report',
      '  node report.mjs <dir> --sweep <dir>     include sweep.sh curves in the page',
      '  node report.mjs <dir> --summary <md>    lead the page with an authored summary',
    ].join('\n'),
  );
  process.exit(0);
}

if (args[0] === '--diff') {
  const [, before, after] = args;
  if (!before || !after) fail('--diff needs a before and an after path');
  printDiff(load(before), load(after));
} else {
  // Flag values are consumed here so they are not mistaken for input paths.
  const mdOut = flagValue('--md');
  const pageOut = flagValue('--page');
  // `--sweep` may be given more than once, optionally as `label=dir`, so two
  // adapters (or two commits) land on the same axes instead of two pages.
  const sweepArgs = allFlagValues('--sweep');
  const summaryPath = flagValue('--summary');
  const paths = args.filter((a, i) => !a.startsWith('--') && !isFlagValue(i));

  const rows = paths.flatMap(load);

  if (mdOut || pageOut) {
    const agg = summarize(rows);
    if (mdOut) {
      writeFileSync(mdOut, renderMarkdown(rows, agg));
      console.log(`wrote ${mdOut}`);
    }
    if (pageOut) {
      const summaryMd = summaryPath ? readFileSync(summaryPath, 'utf8') : null;
      writeFileSync(pageOut, renderPage(rows, agg, sweepArgs.flatMap(loadSweepArg), summaryMd));
      console.log(`wrote ${pageOut}`);
    }
  } else if (args.includes('--json')) {
    console.log(JSON.stringify(rows, null, 2));
  } else {
    printTable(rows);
  }
}

/**
 * Sweep summaries are named `vu<N>-<scenario>.json` by sweep.sh, which is the
 * only place the VU level survives — k6 writes one summary per level and they
 * would otherwise overwrite each other.
 */
function loadSweepArg(arg) {
  const eq = arg.indexOf('=');
  const label = eq === -1 ? null : arg.slice(0, eq);
  const dir = eq === -1 ? arg : arg.slice(eq + 1);
  return loadSweeps(dir).map((s) => ({ ...s, name: label ? `${s.name} · ${label}` : s.name }));
}

function loadSweeps(dir) {
  const byScenario = new Map();

  for (const file of readdirSync(dir).filter((f) => /^vu\d+-.+\.json$/.test(f))) {
    const m = file.match(/^vu(\d+)-(.+)\.json$/);
    const run = readSummary(join(dir, file));
    if (!run) continue;

    const name = m[2];
    if (!byScenario.has(name)) byScenario.set(name, { name, points: [] });
    byScenario.get(name).points.push({
      vus: Number.parseInt(m[1], 10),
      rps: run.rps,
      med: run.med,
      p95: run.p95,
      p99: run.p99,
      errorRate: run.errorRate,
    });
  }

  return [...byScenario.values()].map((s) => ({
    ...s,
    points: s.points.sort((a, b) => a.vus - b.vus),
  }));
}

function flagValue(flag) {
  const i = args.indexOf(flag);
  return i === -1 ? null : args[i + 1];
}

function allFlagValues(flag) {
  return args.map((a, i) => (a === flag ? args[i + 1] : null)).filter(Boolean);
}

function isFlagValue(index) {
  return index > 0 && args[index - 1].startsWith('--') && args[index - 1] !== '--json';
}

// ── Loading ───────────────────────────────────────────────────────────

function load(path) {
  const files = statSync(path).isDirectory()
    ? readdirSync(path)
        .filter((f) => f.endsWith('.json'))
        .map((f) => join(path, f))
    : [path];

  return files.map(readSummary).filter(Boolean).sort(byName);
}

function readSummary(file) {
  let raw;
  try {
    raw = JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    console.error(`skipping ${file}: ${e.message}`);
    return null;
  }

  const m = raw.metrics || {};
  const dur = val(m.http_req_duration);
  const checks = val(m.checks);

  const reqs = val(m.http_reqs);
  const failedRate = val(m.http_req_failed).rate ?? 0;

  return {
    name: raw.name || basename(file, '.json'),
    cell: raw.cell || null,
    baseUrl: raw.base_url || null,
    startedAt: raw.started_at || null,
    runMs: raw.run_ms ?? null,
    vus: raw.vus ?? null,
    requests: reqs.count ?? 0,
    requestFailures: Math.round((reqs.count ?? 0) * failedRate),
    iterations: val(m.iterations).count ?? 0,
    bytesIn: val(m.data_received).count ?? 0,
    bytesOut: val(m.data_sent).count ?? 0,
    checkPasses: val(m.checks).passes ?? 0,
    rps: reqs.rate ?? 0,
    med: dur.med ?? null,
    p95: dur['p(95)'] ?? null,
    p99: dur['p(99)'] ?? null,
    errorRate: val(m.http_req_failed).rate ?? 0,
    checkRate: checks.rate ?? null,
    checkFails: checks.fails ?? 0,
    // Every scenario-specific Trend, so per-step numbers (lobby create vs
    // lobby state, hook noop vs hook locked write) survive into the table.
    trends: Object.keys(m)
      .filter((k) => k.startsWith('t_'))
      .sort()
      .map((k) => {
        const name = k.slice(2);
        // An empty k6 Trend summarises as all-zeros, so a step that never ran
        // would print as the fastest one in the table. `n_<name>` (emitted
        // alongside every channel-event metric) is what tells the two apart.
        const counter = m[`n_${name}`];
        const samples = counter ? counter.values.count : null;
        return {
          name,
          med: val(m[k]).med,
          p95: val(m[k])['p(95)'],
          samples,
          empty: samples === 0,
        };
      }),
  };
}

function val(metric) {
  return (metric && metric.values) || {};
}

function byName(a, b) {
  return a.name.localeCompare(b.name);
}

// ── Rendering ─────────────────────────────────────────────────────────

function printTable(rows) {
  if (rows.length === 0) fail('no summaries found');

  const cell = rows.find((r) => r.cell)?.cell;
  if (cell) console.log(`\n**Cell ${cell}**\n`);

  console.log('| scenario | VUs | rps | med | p95 | p99 | errors | checks |');
  console.log('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (const r of rows) {
    console.log(
      `| ${r.name} | ${r.vus ?? '—'} | ${num(r.rps, 1)} | ${ms(r.med)} | ${ms(r.p95)} | ${ms(
        r.p99,
      )} | ${pct(r.errorRate)} | ${checkCell(r)} |`,
    );
  }

  const withTrends = rows.filter((r) => r.trends.length > 0);
  if (withTrends.length > 0) {
    console.log('\n| scenario | step | med | p95 |');
    console.log('|---|---|---:|---:|');
    for (const r of withTrends) {
      for (const t of r.trends) {
        const cells = t.empty ? 'no samples | no samples' : `${ms(t.med)} | ${ms(t.p95)}`;
        console.log(`| ${r.name} | ${t.name} | ${cells} |`);
      }
    }
  }

  // A run with failed checks is not a slower run, it is a wrong one. Say so
  // loudly rather than leaving it as one column among eight.
  const broken = rows.filter((r) => r.checkFails > 0 || r.errorRate > 0.01);
  if (broken.length > 0) {
    console.log('\n**Failed:**');
    for (const r of broken) {
      console.log(`- ${r.name}: ${r.checkFails} check failures, ${pct(r.errorRate)} errors`);
    }
  }
}

function printDiff(before, after) {
  const byNameMap = new Map(before.map((r) => [r.name, r]));

  console.log('| scenario | p95 before | p95 after | change | rps before | rps after | change |');
  console.log('|---|---:|---:|---:|---:|---:|---:|');

  for (const a of after) {
    const b = byNameMap.get(a.name);
    if (!b) {
      console.log(`| ${a.name} | — | ${ms(a.p95)} | new | — | ${num(a.rps, 1)} | new |`);
      continue;
    }
    console.log(
      `| ${a.name} | ${ms(b.p95)} | ${ms(a.p95)} | ${delta(b.p95, a.p95, true)} | ${num(
        b.rps,
        1,
      )} | ${num(a.rps, 1)} | ${delta(b.rps, a.rps, false)} |`,
    );
  }

  const gone = before.filter((b) => !after.some((a) => a.name === b.name));
  if (gone.length > 0) console.log(`\nMissing from the after run: ${gone.map((g) => g.name).join(', ')}`);
}

/** Percent change, signed so the direction is unambiguous. */
function delta(before, after, lowerIsBetter) {
  if (before == null || after == null || before === 0) return '—';
  const pctChange = ((after - before) / before) * 100;
  const sign = pctChange >= 0 ? '+' : '';
  const worse = lowerIsBetter ? pctChange > 5 : pctChange < -5;
  const better = lowerIsBetter ? pctChange < -5 : pctChange > 5;
  const mark = worse ? ' ⚠️' : better ? ' ✅' : '';
  return `${sign}${pctChange.toFixed(1)}%${mark}`;
}

function checkCell(r) {
  if (r.checkRate === null) return '—';
  return r.checkFails > 0 ? `${pct(r.checkRate)} (${r.checkFails} failed)` : pct(r.checkRate);
}

// Declarations, not `const` arrows: these are called from printTable above,
// which runs before this point in the module body.
function ms(v) {
  return v == null ? '—' : v.toFixed(1);
}

function num(v, d) {
  return v == null ? '—' : v.toFixed(d);
}

function pct(v) {
  return v == null ? '—' : `${(v * 100).toFixed(2)}%`;
}

function fail(msg) {
  console.error(`report.mjs: ${msg}`);
  process.exit(1);
}
