/**
 * Shared configuration and k6 options builders.
 *
 * Every knob is an environment variable so one script can be a 10-second smoke
 * test or a 10-minute capacity run without editing it:
 *
 *     k6 run scenarios/me.js                                    # defaults
 *     VUS=200 DURATION=5m k6 run scenarios/me.js                # a real run
 *     BASE_URL=http://gamend-bench.internal:4000 k6 run …       # on Fly
 */

export const BASE_URL = (__ENV.BASE_URL || 'http://localhost:4000').replace(/\/$/, '');
export const VUS = Number.parseInt(__ENV.VUS || '10', 10);
export const DURATION = __ENV.DURATION || '30s';
export const PLUGIN = __ENV.PLUGIN || 'stress_hook';

/** Prefix for every user/lobby/key this harness creates, so runs are greppable. */
export const RUN_TAG = __ENV.RUN_TAG || 'stress';

/**
 * Seeded email users for auth_email.js.
 *
 * 50, not a few hundred: seeding now costs one bcrypt hash per user (the
 * password is set in a second step, because `register_user/1` does not cast
 * one), so 200 users is over a minute of server CPU before the run starts —
 * past k6's default 60s setup timeout on a small machine. VUs pick a user
 * round-robin, so a pool larger than the VU count buys nothing anyway.
 */
export const EMAIL_USERS = Number.parseInt(__ENV.EMAIL_USERS || '50', 10);
// Not simply "stress-": databases seeded before stress_seed_users learned to
// set a password hold passwordless rows under that prefix which answer 401
// forever, and inheriting them silently turns the bcrypt benchmark into a
// benchmark of the failure path.
export const EMAIL_PREFIX = __ENV.EMAIL_PREFIX || 'stressuser-';
export const EMAIL_PASSWORD = __ENV.EMAIL_PASSWORD || 'stress-password-123456';

/**
 * Think time between iterations of an isolated scenario, in seconds. Zero.
 *
 * These scenarios are microbenchmarks: their job is to find what an operation
 * costs and where it stops scaling, so they run flat out. Pacing them would
 * make the reported rate `VUs / (work + think)` — a restatement of the pacing,
 * not a property of the server.
 *
 * Player-like pacing belongs in `journeys/`, where the question is how many
 * *people* fit and a player who never pauses is not a player. Those read
 * `SESSION_THINK`, which is separate so that a saturation sweep here cannot
 * silently turn the capacity journey into a benchmark loop.
 */
export const THINK = Number.parseFloat(__ENV.THINK || '0');

/** Send `format=protobuf` on socket connects (server→client frames only). */
export const WS_PROTOBUF = __ENV.WS_PROTOBUF === 'true';

/**
 * The SLO. One definition, used by every scenario, so "passed" means the same
 * thing everywhere and the capacity number is comparable across machines.
 *
 * p95 < 300ms and <1% errors is the line the capacity test ramps until it
 * breaks. Channel event delivery gets a looser 500ms: it crosses PubSub and a
 * second process, and a player perceives it as "the lobby updated", not as a
 * request they are waiting on.
 */
export const SLO = {
  http_p95: Number.parseInt(__ENV.SLO_HTTP_P95 || '300', 10),
  http_error_rate: Number.parseFloat(__ENV.SLO_ERROR_RATE || '0.01'),
  event_p95: Number.parseInt(__ENV.SLO_EVENT_P95 || '500', 10),
};

/**
 * Standard thresholds. `checks` is in here deliberately: a scenario that
 * returns 200s fast while serving stale data has to fail, and the check rate
 * is the only thing that notices.
 */
export function thresholds(extra = {}) {
  return {
    http_req_failed: [`rate<${SLO.http_error_rate}`],
    http_req_duration: [`p(95)<${SLO.http_p95}`],
    checks: ['rate>0.99'],
    ...extra,
  };
}

/** Constant-VU options: the shape every isolated scenario uses. */
export function constantVus(extra = {}) {
  return {
    scenarios: {
      default: {
        executor: 'constant-vus',
        vus: VUS,
        duration: DURATION,
        gracefulStop: '10s',
      },
    },
    thresholds: thresholds(extra.thresholds),
    // Percentiles the report reads. Without p99 here k6 only emits avg/p90/p95.
    summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
    ...omit(extra, ['thresholds']),
  };
}

/**
 * Ramping *arrival rate* options, for the capacity journey.
 *
 * Arrival rate, not VUs: with constant-VUs a slowing server produces fewer
 * requests, which hides the very saturation we are looking for. A fixed
 * arrival rate keeps offering load and lets the queue grow, which is what a
 * real player population does.
 */
export function rampingArrivalRate(stages, extra = {}) {
  return {
    scenarios: {
      default: {
        executor: 'ramping-arrival-rate',
        startRate: Number.parseInt(__ENV.START_RATE || '10', 10),
        timeUnit: '1s',
        preAllocatedVUs: Number.parseInt(__ENV.PRE_VUS || '200', 10),
        maxVUs: Number.parseInt(__ENV.MAX_VUS || '5000', 10),
        stages,
        gracefulStop: '15s',
      },
    },
    thresholds: thresholds(extra.thresholds),
    summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
    ...omit(extra, ['thresholds']),
  };
}

/** Write the k6 summary as JSON next to the human one, for report.mjs. */
export function summaryHandler(name) {
  return function handleSummary(data) {
    const dir = __ENV.RESULTS_DIR || 'results';
    const cell = __ENV.CELL ? `${__ENV.CELL}-` : '';
    const out = {};
    // The VU count comes from the metrics, not from `VUS`: a run started with
    // `k6 run --vus` overrides the scenario config, and recording the config
    // value would label the row with a concurrency it never ran at.
    const vus = (data.metrics.vus_max && data.metrics.vus_max.values.max) || VUS;

    out[`${dir}/${cell}${name}.json`] = JSON.stringify(
      {
        name,
        cell: __ENV.CELL || null,
        base_url: BASE_URL,
        vus,
        duration: DURATION,
        // The wall-clock k6 actually ran for, not the configured duration:
        // setup(), ramping and gracefulStop all land outside `DURATION`, and a
        // throughput computed against the configured value would be wrong by
        // however long seeding took.
        run_ms: (data.state && data.state.testRunDurationMs) || null,
        started_at: new Date().toISOString(),
        // What the run was pointed at, so a report can say whether the numbers
        // came from a laptop or a bench machine without anyone remembering.
        env: {
          run_tag: RUN_TAG,
          plugin: PLUGIN,
          protobuf: WS_PROTOBUF,
          slo: SLO,
        },
        metrics: data.metrics,
      },
      null,
      2,
    );
    out.stdout = textSummary(data, name);
    return out;
  };
}

/**
 * A compact stdout summary. k6's own `textSummary` lives in a jslib on a CDN;
 * the generator machine has no egress to it, so this prints the few lines that
 * matter instead of pulling a remote dependency into every script.
 */
function textSummary(data, name) {
  const lines = [`\n── ${name} ──`];
  const m = data.metrics;

  const req = m.http_reqs ? m.http_reqs.values.rate : 0;
  const dur = m.http_req_duration ? m.http_req_duration.values : {};
  const failed = m.http_req_failed ? m.http_req_failed.values.rate : 0;
  const checks = m.checks ? m.checks.values : null;

  lines.push(`  rps           ${req.toFixed(1)}`);
  lines.push(
    `  http (ms)     med ${fmt(dur.med)}  p95 ${fmt(dur['p(95)'])}  p99 ${fmt(dur['p(99)'])}  max ${fmt(dur.max)}`,
  );
  lines.push(`  errors        ${(failed * 100).toFixed(2)}%`);
  if (checks) {
    lines.push(`  checks        ${(checks.rate * 100).toFixed(2)}% passed (${checks.fails} failed)`);
  }

  // Every custom Trend (event delivery, time-to-match, per-endpoint splits).
  // An empty Trend summarises as all-zeros, so a step that never ran would
  // print as the fastest number here; `n_<name>` says how many samples there
  // actually were.
  for (const key of Object.keys(m)) {
    if (key.startsWith('t_') && m[key].values) {
      const v = m[key].values;
      const counter = m[`n_${key.slice(2)}`];
      if (counter && counter.values.count === 0) {
        lines.push(`  ${key.padEnd(13)} no samples`);
      } else {
        lines.push(`  ${key.padEnd(13)} med ${fmt(v.med)}  p95 ${fmt(v['p(95)'])}  p99 ${fmt(v['p(99)'])}`);
      }
    }
  }

  return lines.join('\n') + '\n';
}

function fmt(v) {
  return v === undefined || v === null ? '—' : v.toFixed(1);
}

function omit(obj, keys) {
  const out = {};
  for (const k of Object.keys(obj || {})) if (!keys.includes(k)) out[k] = obj[k];
  return out;
}
