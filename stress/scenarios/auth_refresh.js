/**
 * POST /api/v1/refresh — the cheap half of authentication.
 *
 * A real client logs in once and then refreshes every 15 minutes for the rest
 * of the session, so this runs far more often than either login path. It is
 * pure crypto: verify a JWT, load the user, sign a new access token. No
 * password hashing, no insert. The gap between this and auth_email.js is what
 * bcrypt costs, and the gap to me.js is what signing a token costs.
 *
 * Each VU logs in once (device login, cached by `auth.js`) and then only
 * refreshes, which is the shape of the client behaviour being measured.
 *
 * Rotation: this server does *not* rotate. `SessionController.refresh/2` echoes
 * the submitted refresh token back unchanged, and re-submitting the same token
 * keeps returning 200 — verified against the running server. The returned token
 * is adopted anyway, so the scenario keeps working the day rotation lands.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, THINK } from '../lib/config.js';
import { deviceLogin, refresh, resetSession } from '../lib/auth.js';
import { ok } from '../lib/checks.js';

const tRefresh = new Trend('t_refresh', true);

/** Per-VU: the refresh token in flight, and the access token to beat. */
let _refreshToken = null;
let _lastAccess = null;

export const options = constantVus();
export const handleSummary = summaryHandler('auth_refresh');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  if (!_refreshToken) {
    _refreshToken = session.refresh;
    _lastAccess = session.token;
  }

  const { res, session: refreshed } = refresh(_refreshToken);
  tRefresh.add(res.timings.duration);

  // A 401 here is this VU's refresh token going bad mid-run: drop the whole
  // session so the next iteration logs in again rather than failing forever.
  if (res.status === 401) {
    _refreshToken = null;
    resetSession();
    return;
  }

  ok(res, 'refresh');
  if (!check(refreshed, { 'refresh returns a new access token': (s) => s !== null })) return;
  check(refreshed, {
    'refresh issues a different access token': (s) => s.token !== _lastAccess,
  });

  _lastAccess = refreshed.token;
  _refreshToken = refreshed.refresh || _refreshToken;

  sleep(THINK);
}
