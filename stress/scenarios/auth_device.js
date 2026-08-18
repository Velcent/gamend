/**
 * POST /api/v1/login/device with a device id nobody has used before.
 *
 * The account-creation write path, and the write counterpart to me.js: every
 * iteration inserts a user, signs two JWTs and touches last_seen. A repeat
 * login for a known device finds an existing row instead, so reusing device
 * ids here would quietly turn the write benchmark into a read benchmark.
 *
 * The token is then spent on one GET /me, because a 201 carrying a token that
 * does not authenticate is a failure no status code reports.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { me } from '../lib/api.js';
import { ok, bodyMatches } from '../lib/checks.js';

const tLogin = new Trend('t_device_login', true);

export const options = constantVus();
export const handleSummary = summaryHandler('auth_device');

export default function () {
  // Wall clock rather than `res.timings.duration`: `deviceLogin` hands back a
  // session, not a response, and it makes exactly one request.
  const started = Date.now();
  const session = deviceLogin({ fresh: true });
  tLogin.add(Date.now() - started);

  // `parseSession` returns null unless the body carried an `access_token`, so
  // this is the "the response has a token" assertion, not a null guard.
  if (!check(session, { 'device login returns an access token': (s) => s !== null })) return;

  const res = me(session.token);
  ok(res, 'me with the new token');
  bodyMatches(res, (u) => typeof u.id === 'string' && u.id.length > 0, 'new token resolves a user');

  sleep(THINK);
}
