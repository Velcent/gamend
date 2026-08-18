/**
 * Render a run as a Markdown report and as a self-contained HTML page.
 *
 * Charts are hand-built SVG rather than a library: the page has to open from a
 * file:// path, from a repo, and from an Artifact with no network, and a CDN
 * script tag fails in all three. The shapes needed here are two — a horizontal
 * bar and a min/mid/max range row — which is far less code than a chart
 * library's config would be.
 *
 * Used by report.mjs; not run directly.
 */

// Colors live in the page's CSS custom properties (categorical slots 1-3 for
// median/p95/p99, plus a status pair) so the SVG marks inherit the light and
// dark values from the same tokens the tables use.

// ── Aggregates ────────────────────────────────────────────────────────

export function summarize(runs) {
  const sum = (f) => runs.reduce((a, r) => a + (f(r) || 0), 0);

  const requests = sum((r) => r.requests);
  const runSeconds = sum((r) => r.runMs) / 1000;
  const checksRun = sum((r) => r.checkPasses) + sum((r) => r.checkFails);

  return {
    scenarios: runs.length,
    requests,
    iterations: sum((r) => r.iterations),
    runSeconds,
    // Every scenario ran alone, so the meaningful rate is per scenario, not
    // requests divided by the whole suite's wall clock — that would average in
    // the seeding and settle time between them.
    peakRps: Math.max(...runs.map((r) => r.rps || 0)),
    meanRps: runSeconds > 0 ? requests / runSeconds : 0,
    vus: Math.max(...runs.map((r) => r.vus || 0)),
    checksRun,
    checkFails: sum((r) => r.checkFails),
    errors: sum((r) => r.requestFailures),
    errorRate: requests > 0 ? sum((r) => r.requestFailures) / requests : 0,
    bytes: sum((r) => r.bytesIn) + sum((r) => r.bytesOut),
    failedScenarios: runs.filter((r) => r.checkFails > 0 || r.errorRate > 0.01).map((r) => r.name),
    startedAt: runs.map((r) => r.startedAt).filter(Boolean).sort()[0] || null,
    baseUrl: runs.find((r) => r.baseUrl)?.baseUrl || null,
    cell: runs.find((r) => r.cell)?.cell || null,
  };
}

// ── Markdown ──────────────────────────────────────────────────────────

export function renderMarkdown(runs, agg) {
  const L = [];
  const steps = runs.flatMap((r) => r.trends.map((t) => ({ ...t, scenario: r.name })));

  L.push(`# Load test — ${agg.cell ? `cell ${agg.cell}` : 'local run'}`);
  L.push('');
  L.push(
    `${fmtInt(agg.requests)} requests across ${agg.scenarios} scenarios at ${agg.vus} concurrent ` +
      `users, ${fmtDuration(agg.runSeconds)} of measured time. ` +
      (agg.checkFails === 0 && agg.errors === 0
        ? 'Every check passed and nothing errored.'
        : `${fmtInt(agg.checkFails)} check failures, ${pct(agg.errorRate)} of requests failed.`),
  );
  L.push('');
  L.push(`- **Target** — \`${agg.baseUrl || 'unknown'}\``);
  L.push(`- **Started** — ${agg.startedAt || 'unknown'}`);
  L.push(`- **Peak throughput** — ${fmt(agg.peakRps, 1)} req/s (best single scenario)`);
  L.push(`- **Correctness** — ${fmtInt(agg.checksRun)} checks run, ${fmtInt(agg.checkFails)} failed`);
  L.push(`- **Transferred** — ${fmtBytes(agg.bytes)}`);
  L.push('');

  L.push('## Per scenario');
  L.push('');
  L.push('| scenario | req/s | requests | median | p95 | p99 | errors | checks |');
  L.push('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (const r of runs) {
    L.push(
      `| ${r.name} | ${fmt(r.rps, 1)} | ${fmtInt(r.requests)} | ${ms(r.med)} | ${ms(r.p95)} | ` +
        `${ms(r.p99)} | ${pct(r.errorRate)} | ${r.checkFails > 0 ? `${pct(r.checkRate)} (${r.checkFails} failed)` : pct(r.checkRate)} |`,
    );
  }
  L.push('');
  L.push(bars('Throughput (req/s)', runs.map((r) => ({ label: r.name, value: r.rps }))));
  L.push('');
  L.push(bars('Median latency (ms)', runs.map((r) => ({ label: r.name, value: r.med }))));

  if (steps.length > 0) {
    L.push('');
    L.push('## Per operation');
    L.push('');
    L.push('What each individual call costs, timed inside the scenario that exercises it.');
    L.push('');
    L.push('| scenario | operation | median | p95 |');
    L.push('|---|---|---:|---:|');
    for (const s of steps) {
      L.push(
        `| ${s.scenario} | ${s.name} | ${s.empty ? 'no samples' : ms(s.med)} | ${s.empty ? 'no samples' : ms(s.p95)} |`,
      );
    }
    L.push('');
    L.push(
      bars(
        'Median per operation (ms)',
        steps.filter((s) => !s.empty).map((s) => ({ label: s.name, value: s.med })),
      ),
    );
  }

  L.push('');
  L.push('## How to reproduce');
  L.push('');
  L.push('```bash');
  L.push('cd stress');
  L.push(`BASE_URL=${agg.baseUrl || 'http://localhost:4000'} VUS=${agg.vus} DURATION=15s ./suite.sh`);
  L.push('node report.mjs results/ --md results/report.md --page results/report.html');
  L.push('```');
  L.push('');
  L.push('See [README.md](../README.md) for what has to be true of the server first.');

  return L.join('\n') + '\n';
}

/** A unicode bar chart, so a Markdown file needs no image assets. */
function bars(title, rows) {
  if (rows.length === 0) return '';
  const max = Math.max(...rows.map((r) => r.value || 0));
  const width = 34;
  const pad = Math.max(...rows.map((r) => r.label.length));

  const L = [`**${title}**`, '', '```'];
  for (const r of rows) {
    const n = max > 0 ? Math.round(((r.value || 0) / max) * width) : 0;
    L.push(`${r.label.padEnd(pad)}  ${'█'.repeat(n).padEnd(width)}  ${fmt(r.value, 1)}`);
  }
  L.push('```');
  return L.join('\n');
}

// ── HTML ──────────────────────────────────────────────────────────────

export function renderPage(runs, agg, sweeps = []) {
  const sweepsHtml = renderSweeps(sweeps);
  const steps = runs
    .flatMap((r) => r.trends.filter((t) => !t.empty).map((t) => ({ ...t, scenario: r.name })))
    .sort((a, b) => b.med - a.med);

  const clean = agg.checkFails === 0 && agg.errors === 0;

  return `<title>Gamend Load Test</title>
<style>
  :root {
    --sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, "Cascadia Mono", monospace;
    color-scheme: light;
    --surface: #fcfcfb;
    --surface-2: #f4f3f0;
    --line: #e2e0da;
    --ink: #0b0b0b;
    --ink-2: #52514e;
    --ink-3: #77756e;
    --s1: #2a78d6;
    --s2: #eb6834;
    --s3: #1baf7a;
    --good: #0ca30c;
    --bad: #d03b3b;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --surface: #1a1a19;
      --surface-2: #232322;
      --line: #383835;
      --ink: #ffffff;
      --ink-2: #c3c2b7;
      --ink-3: #93918a;
      --s1: #3987e5;
      --s2: #d95926;
      --s3: #199e70;
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --surface: #1a1a19;
    --surface-2: #232322;
    --line: #383835;
    --ink: #ffffff;
    --ink-2: #c3c2b7;
    --ink-3: #93918a;
    --s1: #3987e5;
    --s2: #d95926;
    --s3: #199e70;
  }

  body {
    background: var(--surface);
    color: var(--ink);
    font: 16px/1.55 var(--sans);
    margin: 0;
    padding: 48px 24px 96px;
  }
  /* Scenario names are identifiers and the figures are measurements, so both
     wear the mono face; prose wears the sans. Nothing else switches. */
  .mono, td.num, .tile .v, pre, code, text { font-family: var(--mono); }
  main { max-width: 1000px; margin: 0 auto; }
  h1 { font-size: 30px; letter-spacing: -0.02em; margin: 0 0 8px; }
  h2 { font-size: 20px; letter-spacing: -0.01em; margin: 48px 0 4px; }
  p.sub { color: var(--ink-2); margin: 0 0 32px; max-width: 62ch; }
  p.note { color: var(--ink-2); margin: 0 0 20px; max-width: 68ch; font-size: 14px; }

  .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin: 24px 0 8px; }
  .tile { background: var(--surface-2); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; }
  .tile .k { font-size: 12px; color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.06em; }
  .tile .v { font-size: 26px; margin-top: 2px; letter-spacing: -0.02em; }
  .tile .v.good { color: var(--good); }
  .tile .v.bad { color: var(--bad); }

  .meta { display: flex; flex-wrap: wrap; gap: 8px 24px; color: var(--ink-2); font-size: 14px; margin-top: 20px; }
  .meta code { background: var(--surface-2); border: 1px solid var(--line); border-radius: 4px; padding: 1px 6px; font-size: 13px; }

  .scroll { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; font-size: 14px; margin-top: 14px; }
  th, td { text-align: right; padding: 7px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; }
  th:first-child, td:first-child { text-align: left; }
  thead th { color: var(--ink-3); font-weight: 500; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
  td.num { font-variant-numeric: tabular-nums; font-size: 13px; }
  td.fail { color: var(--bad); }
  /* State reads before the number does: a green or red edge on the row's first
     cell, so a scan finds the failures without comparing eight columns. */
  tbody td:first-child { border-left: 3px solid var(--good); padding-left: 10px; }
  tbody tr.bad td:first-child { border-left-color: var(--bad); }
  /* Sweep rows are levels of one run, not pass/fail subjects. */
  tbody tr.plain td:first-child { border-left-color: transparent; }
  h3 { font-size: 15px; margin: 28px 0 0; display: flex; align-items: center; gap: 8px; }

  figure { margin: 20px 0 0; }
  figcaption { color: var(--ink-3); font-size: 13px; margin-bottom: 8px; }
  svg { display: block; max-width: 100%; height: auto; }
  .legend { display: flex; gap: 16px; font-size: 13px; color: var(--ink-2); margin: 4px 0 10px; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }

  pre { background: var(--surface-2); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; overflow-x: auto; font-size: 13px; }
  footer { margin-top: 56px; padding-top: 20px; border-top: 1px solid var(--line); color: var(--ink-3); font-size: 13px; }
</style>

<main>
  <h1>Gamend load test${agg.cell ? ` — cell ${agg.cell}` : ''}</h1>
  <p class="sub">
    ${fmtInt(agg.requests)} requests across ${agg.scenarios} isolated scenarios at
    ${agg.vus} concurrent users, ${fmtDuration(agg.runSeconds)} of measured time.
    ${clean
      ? 'Every check passed and no request failed.'
      : `${fmtInt(agg.checkFails)} check failures and ${pct(agg.errorRate)} failed requests — the numbers below describe a run that was also <em>wrong</em>, not just slow.`}
  </p>

  <div class="tiles">
    ${tile('Requests', fmtInt(agg.requests))}
    ${tile('Peak req/s', fmt(agg.peakRps, 0))}
    ${tile('Concurrent users', String(agg.vus))}
    ${tile('Measured time', fmtDuration(agg.runSeconds))}
    ${tile('Checks run', fmtInt(agg.checksRun))}
    ${tile('Failed checks', fmtInt(agg.checkFails), agg.checkFails === 0 ? 'good' : 'bad')}
    ${tile('Error rate', pct(agg.errorRate), agg.errorRate === 0 ? 'good' : 'bad')}
    ${tile('Transferred', fmtBytes(agg.bytes))}
  </div>

  <div class="meta">
    <span>Target <code>${esc(agg.baseUrl || 'unknown')}</code></span>
    <span>Started ${esc(agg.startedAt || 'unknown')}</span>
    <span>Iterations ${fmtInt(agg.iterations)}</span>
  </div>

  <h2>Throughput</h2>
  <p class="note">
    Scenarios run one at a time, each with the whole machine, so these are
    comparable to each other rather than to a production mix. A low bar is not
    always slow work — <code>matchmaking</code> waits on a periodic sweep, and
    <code>auth_email</code> pays for a bcrypt verify on every iteration.
  </p>
  ${hbars(runs.map((r) => ({ label: r.name, value: r.rps })), 'req/s', 'var(--s1)')}

  <h2>Latency</h2>
  <p class="note">
    Median to p99 per scenario. The distance between the dots is the tail: a
    short row is a predictable operation, a long one has a slow minority worth
    explaining.
  </p>
  <div class="legend">
    <span><i class="dot" style="background:var(--s1)"></i>median</span>
    <span><i class="dot" style="background:var(--s2)"></i>p95</span>
    <span><i class="dot" style="background:var(--s3)"></i>p99</span>
  </div>
  ${rangeRows(runs.map((r) => ({ label: r.name, a: r.med, b: r.p95, c: r.p99 })))}

  <h2>Per scenario</h2>
  <div class="scroll">
    <table>
      <thead><tr>
        <th>scenario</th><th>req/s</th><th>requests</th><th>median</th><th>p95</th><th>p99</th><th>errors</th><th>checks</th>
      </tr></thead>
      <tbody>
        ${runs
          .map(
            (r) => `<tr class="${r.checkFails > 0 || r.errorRate > 0.01 ? 'bad' : 'ok'}">
          <td class="mono">${esc(r.name)}</td>
          <td class="num">${fmt(r.rps, 1)}</td>
          <td class="num">${fmtInt(r.requests)}</td>
          <td class="num">${ms(r.med)}</td>
          <td class="num">${ms(r.p95)}</td>
          <td class="num">${ms(r.p99)}</td>
          <td class="num${r.errorRate > 0 ? ' fail' : ''}">${pct(r.errorRate)}</td>
          <td class="num${r.checkFails > 0 ? ' fail' : ''}">${r.checkFails > 0 ? `${pct(r.checkRate)} (${r.checkFails} failed)` : pct(r.checkRate)}</td>
        </tr>`,
          )
          .join('\n')}
      </tbody>
    </table>
  </div>

  ${steps.length === 0 ? '' : `
  <h2>Per operation</h2>
  <p class="note">
    Each call timed inside the scenario that exercises it, slowest first. This is
    the table a change gets compared against: subtracting neighbours attributes
    cost to a layer rather than to a feature.
  </p>
  ${hbars(steps.map((s) => ({ label: s.name, value: s.med })), 'ms (median)', 'var(--s1)')}
  <div class="scroll">
    <table>
      <thead><tr><th>operation</th><th>scenario</th><th>median</th><th>p95</th></tr></thead>
      <tbody>
        ${steps
          .map(
            (s) => `<tr>
          <td class="mono">${esc(s.name)}</td>
          <td class="mono">${esc(s.scenario)}</td>
          <td class="num">${ms(s.med)}</td>
          <td class="num">${ms(s.p95)}</td>
        </tr>`,
          )
          .join('\n')}
      </tbody>
    </table>
  </div>`}

  ${sweepsHtml}

  <h2>Reproducing this</h2>
  <pre>cd stress
BASE_URL=${esc(agg.baseUrl || 'http://localhost:4000')} VUS=${agg.vus} DURATION=15s ./suite.sh
node report.mjs results/ --md results/report.md --page results/report.html</pre>

  <footer>
    Generated by <code>stress/report.mjs</code> from k6 summaries in
    <code>stress/results/</code>. Latency is milliseconds; a run with failed
    checks is a wrong run, not a slow one.
  </footer>
</main>
`;
}

/**
 * The saturation section: throughput and p95 against concurrency, per scenario.
 *
 * This is the part of a run that says where the machine stops. Three shapes are
 * worth telling apart, and the chart makes them visible: throughput still
 * climbing (headroom), throughput flat while latency climbs (queueing — the
 * knee), and throughput *falling* while latency climbs (contention, where added
 * concurrency makes the server do less work in total).
 */
export function renderSweeps(sweeps) {
  if (sweeps.length === 0) return '';

  // Two dimensions, two encodings: hue is the scenario, line style is the
  // variant (`--sweep Postgres=dir` appends ` · Postgres`). Cycling hues for a
  // sixth series would make two adapters of the same scenario look unrelated
  // and two unrelated scenarios look like a pair.
  const palette = ['var(--s1)', 'var(--s2)', 'var(--s3)'];
  const bases = [...new Set(sweeps.map((s) => s.name.split(' · ')[0]))];
  const variants = [...new Set(sweeps.map((s) => s.name.split(' · ')[1] || ''))];

  const styleOf = (name) => {
    const [base, variant = ''] = name.split(' · ');
    return {
      color: palette[bases.indexOf(base) % palette.length],
      dashed: variants.indexOf(variant) > 0,
    };
  };

  const colors = sweeps.map((s) => styleOf(s.name).color);

  const tables = sweeps
    .map(
      (s, i) => `
  <h3><span class="dot" style="background:${colors[i]}"></span> ${esc(s.name)}</h3>
  <div class="scroll">
    <table>
      <thead><tr><th>VUs</th><th>req/s</th><th>median</th><th>p95</th><th>p99</th><th>errors</th></tr></thead>
      <tbody>
        ${s.points
          .map(
            (p) => `<tr class="plain"><td class="mono">${p.vus}</td><td class="num">${fmtInt(p.rps)}</td>` +
              `<td class="num">${ms(p.med)}</td><td class="num">${ms(p.p95)}</td>` +
              `<td class="num">${ms(p.p99)}</td><td class="num">${pct(p.errorRate)}</td></tr>`,
          )
          .join('\n')}
      </tbody>
    </table>
  </div>`,
    )
    .join('\n');

  return `
  <h2>Where it stops scaling</h2>
  <p class="note">
    Throughput against concurrency. A line that keeps climbing has headroom; one
    that flattens while latency grows is queueing; one that <em>falls</em> is
    contending — added concurrency is making the server do less total work,
    which is the signature of a lock rather than a queue.
  </p>
  <div class="legend">
    ${sweeps
      .map((s, i) => {
        const st = styleOf(s.name);
        return `<span><i class="dot" style="background:${st.color};${st.dashed ? 'opacity:.55;' : ''}"></i>${esc(s.name)}</span>`;
      })
      .join('')}
  </div>
  ${variants.length > 1 ? '<p class="note">Solid is ' + esc(variants[0] || 'the first set') + '; dashed is ' + esc(variants[1]) + '.</p>' : ''}
  ${lines(sweeps, colors, sweeps.map((s) => styleOf(s.name).dashed))}
  ${tables}`;
}

/** Small multiples would need axes per panel; one panel with a shared log-ish
 *  x (VU levels are equally spaced as categories) keeps the comparison direct. */
function lines(sweeps, colors, dashes = []) {
  const w = 760;
  const h = 260;
  const padL = 62;
  const padR = 16;
  const padT = 12;
  const padB = 34;

  const levels = [...new Set(sweeps.flatMap((s) => s.points.map((p) => p.vus)))].sort((a, b) => a - b);
  const maxRps = Math.max(...sweeps.flatMap((s) => s.points.map((p) => p.rps || 0)), 1);

  const x = (vus) => padL + (levels.indexOf(vus) / Math.max(1, levels.length - 1)) * (w - padL - padR);
  const y = (rps) => h - padB - ((rps || 0) / maxRps) * (h - padT - padB);

  const grid = [0, 0.25, 0.5, 0.75, 1]
    .map((f) => {
      const yy = h - padB - f * (h - padT - padB);
      return `<line x1="${padL}" y1="${yy}" x2="${w - padR}" y2="${yy}" stroke="var(--line)" stroke-width="1" />
      <text x="${padL - 8}" y="${yy}" text-anchor="end" dominant-baseline="middle" font-size="11" fill="var(--ink-3)">${fmtInt(maxRps * f)}</text>`;
    })
    .join('');

  const ticks = levels
    .map(
      (v) => `<text x="${x(v)}" y="${h - padB + 16}" text-anchor="middle" font-size="11" fill="var(--ink-3)">${v}</text>`,
    )
    .join('');

  const series = sweeps
    .map((s, i) => {
      const pts = s.points.map((p) => `${x(p.vus)},${y(p.rps)}`).join(' ');
      const dots = s.points
        .map((p) => `<circle cx="${x(p.vus)}" cy="${y(p.rps)}" r="3.5" fill="${colors[i]}" />`)
        .join('');
      const dash = dashes[i] ? ' stroke-dasharray="5 4"' : '';
      return `<polyline points="${pts}" fill="none" stroke="${colors[i]}" stroke-width="2"${dash} />${dots}`;
    })
    .join('');

  return `<figure>
  <figcaption>req/s by concurrent users</figcaption>
  <svg viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" role="img" aria-label="Throughput against concurrency">
    ${grid}${ticks}${series}
  </svg>
</figure>`;
}

// ── SVG builders ──────────────────────────────────────────────────────

/** Horizontal bars. Labels sit outside the plot so nothing is ever clipped. */
function hbars(rows, unit, color) {
  if (rows.length === 0) return '';

  const rowH = 26;
  const gap = 6;
  const labelW = 150;
  const valueW = 64;
  const plotW = 640;
  const width = labelW + plotW + valueW;
  const height = rows.length * (rowH + gap);
  const max = Math.max(...rows.map((r) => r.value || 0), 1);

  const marks = rows
    .map((r, i) => {
      const y = i * (rowH + gap);
      const w = Math.max(2, ((r.value || 0) / max) * plotW);
      return `
    <text x="${labelW - 10}" y="${y + rowH / 2}" text-anchor="end" dominant-baseline="middle"
          font-size="13" fill="var(--ink-2)">${esc(r.label)}</text>
    <rect x="${labelW}" y="${y + 4}" width="${w}" height="${rowH - 8}" rx="4" fill="${color}" />
    <text x="${labelW + w + 8}" y="${y + rowH / 2}" dominant-baseline="middle"
          font-size="12" fill="var(--ink-3)" style="font-variant-numeric:tabular-nums">${fmt(r.value, 1)}</text>`;
    })
    .join('');

  return `<figure>
  <figcaption>${esc(unit)}</figcaption>
  <svg viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="${esc(unit)} by scenario">
    ${marks}
  </svg>
</figure>`;
}

/** One row per label: a hairline from median to p99 with a dot at each stat. */
function rangeRows(rows) {
  if (rows.length === 0) return '';

  const rowH = 26;
  const gap = 6;
  const labelW = 150;
  const valueW = 76;
  const plotW = 620;
  const width = labelW + plotW + valueW;
  const height = rows.length * (rowH + gap);
  const max = Math.max(...rows.map((r) => r.c || r.b || r.a || 0), 1);
  const x = (v) => labelW + ((v || 0) / max) * plotW;

  const marks = rows
    .map((r, i) => {
      const y = i * (rowH + gap) + rowH / 2;
      return `
    <text x="${labelW - 10}" y="${y}" text-anchor="end" dominant-baseline="middle"
          font-size="13" fill="var(--ink-2)">${esc(r.label)}</text>
    <line x1="${x(r.a)}" y1="${y}" x2="${x(r.c)}" y2="${y}" stroke="var(--line)" stroke-width="2" />
    <circle cx="${x(r.c)}" cy="${y}" r="4.5" fill="var(--s3)" />
    <circle cx="${x(r.b)}" cy="${y}" r="4.5" fill="var(--s2)" />
    <circle cx="${x(r.a)}" cy="${y}" r="4.5" fill="var(--s1)" />
    <text x="${labelW + plotW + 8}" y="${y}" dominant-baseline="middle"
          font-size="12" fill="var(--ink-3)" style="font-variant-numeric:tabular-nums">${ms(r.c)}</text>`;
    })
    .join('');

  return `<figure>
  <svg viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img"
       aria-label="Median, p95 and p99 latency by scenario">
    ${marks}
  </svg>
</figure>`;
}

function tile(k, v, tone) {
  return `<div class="tile"><div class="k">${esc(k)}</div><div class="v${tone ? ` ${tone}` : ''}">${esc(v)}</div></div>`;
}

// ── Formatting ────────────────────────────────────────────────────────

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

function fmt(v, d) {
  return v == null ? '—' : Number(v).toFixed(d);
}

function fmtInt(v) {
  return v == null ? '—' : Math.round(v).toLocaleString('en-US');
}

function ms(v) {
  return v == null ? '—' : `${Number(v).toFixed(1)}`;
}

function pct(v) {
  return v == null ? '—' : `${(v * 100).toFixed(2)}%`;
}

function fmtBytes(n) {
  if (!n) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v.toFixed(v >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
}

function fmtDuration(seconds) {
  if (!seconds) return '—';
  if (seconds < 90) return `${Math.round(seconds)}s`;
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60);
  return `${m}m ${s.toString().padStart(2, '0')}s`;
}
