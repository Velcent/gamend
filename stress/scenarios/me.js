/**
 * GET /api/v1/me — the cached-read baseline.
 *
 * Every other scenario is read against this one: it is an authenticated
 * request that resolves a JWT and returns a cached user, so whatever it costs
 * is the floor for "an authenticated request on this machine". A number that
 * drifts up here moves every other number with it.
 */

import { sleep } from 'k6';
import { constantVus, summaryHandler, THINK } from '../lib/config.js';
import { deviceLogin, resetSession } from '../lib/auth.js';
import { me } from '../lib/api.js';
import { ok, bodyMatches } from '../lib/checks.js';

export const options = constantVus();
export const handleSummary = summaryHandler('me');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  const res = me(session.token);

  // A 401 means this VU's token expired mid-run; drop it and re-login next
  // iteration rather than failing every remaining iteration.
  if (res.status === 401) {
    resetSession();
    return;
  }

  ok(res, 'me');
  bodyMatches(res, (u) => typeof u.id === 'string' && u.id.length > 0, 'me returns a user');

  sleep(THINK);
}
