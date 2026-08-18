/**
 * POST /api/v1/login — email + password, the CPU-bound authentication path.
 *
 * Every other scenario is I/O; this one is arithmetic. A bcrypt verify is
 * hundreds of milliseconds of pure CPU per attempt, it cannot be cached, and it
 * occupies a scheduler for its whole duration — so a handful of VUs saturates
 * every core and latency climbs linearly with concurrency long before anything
 * else on the server is stressed. That is not a defect; it is what the work
 * costs, and it is the reason `auth_email` is the last scenario in the suite.
 *
 * Read **logins/s (`rps`), not p95**, out of this run. Latency here mostly
 * restates how many VUs were offered, whereas logins/s is the number that sizes
 * a login stampede after a restart. For the same reason the standard
 * p95 < 300ms threshold is replaced below: a threshold that can never pass
 * reports nothing, it only paints every run red.
 *
 * A real player pays this once per session and then refreshes (see
 * auth_refresh.js, which is ~50x cheaper), so this is a login-rate ceiling and
 * not a concurrency ceiling. If it ever becomes the binding constraint, the
 * lever is `config :bcrypt_elixir, :log_rounds` — 10 rounds is 4x cheaper than
 * the default 12 and still ~60ms.
 *
 * Deliberately not cached: `emailLogin()` pays for a login every iteration,
 * because the login is the measurement.
 *
 * The seeded users come from `stress_seed_users`, which sets the password in a
 * second step — `Accounts.register_user/1` never casts one, and a database
 * seeded before that fix holds passwordless rows that answer 401 forever. If
 * this scenario reports 401s, seed under a fresh `EMAIL_PREFIX` rather than
 * relaxing the check.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import {
  constantVus,
  summaryHandler,
  EMAIL_PASSWORD,
  EMAIL_PREFIX,
  EMAIL_USERS,
  RUN_TAG,
  THINK,
} from '../lib/config.js';
import { deviceLogin, emailLogin } from '../lib/auth.js';
import { ensureSeed } from '../lib/hooks.js';
import { ok } from '../lib/checks.js';

const tLogin = new Trend('t_email_login', true);

export const options = constantVus({
  thresholds: { http_req_duration: ['p(95)<3000'] },
  // Seeding pays one bcrypt hash per user, which is minutes of CPU on a cold
  // database and well past k6's 60s default.
  setupTimeout: '300s',
});

export const handleSummary = summaryHandler('auth_email');

export function setup() {
  const session = deviceLogin({ fresh: true, id: `${RUN_TAG}-setup-email` });
  if (!session) return {};

  // Called every run, not once: seeding is idempotent, and on SQLite a first
  // seed of a few hundred users can lose a write to "Database busy" while
  // another write scenario is still draining.
  ensureSeed(session.token, `${RUN_TAG}_email_seed`, {
    users: EMAIL_USERS,
    prefix: EMAIL_PREFIX,
    password: EMAIL_PASSWORD,
  });

  return {};
}

export default function () {
  const { res, session } = emailLogin();
  tLogin.add(res.timings.duration);

  ok(res, 'email login');
  check(session, { 'email login returns an access token': (s) => s !== null });

  sleep(THINK);
}
