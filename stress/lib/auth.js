/**
 * Authentication for load-test VUs.
 *
 * Device login is the default everywhere: it is one insert with no password
 * hashing, and a fresh `device_id` per VU means every socket belongs to its own
 * user. That is both what a real game client does on first launch and what
 * keeps per-user limits (max sockets, chat quotas, one-ticket-per-user
 * matchmaking) out of the measurement — those limits are correct, and a load
 * test that trips them is measuring the limiter, not the server.
 */

import http from 'k6/http';
import { check } from 'k6';
import { BASE_URL, EMAIL_PASSWORD, EMAIL_PREFIX, EMAIL_USERS, RUN_TAG } from './config.js';

/** Per-VU token cache. VU state is per-VU by construction in k6. */
let _session = null;

export function jsonHeaders(token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return { headers };
}

/** A device id unique to this VU and run. */
export function deviceId(suffix = '') {
  return `${RUN_TAG}-${__VU}-${suffix || __ITER}`;
}

/**
 * Log in with a device id, returning `{token, refresh, userId}` or null.
 *
 * `fresh: true` forces a brand-new user (the write path); the default reuses
 * this VU's session, which is what a steady-state player looks like.
 */
export function deviceLogin({ fresh = false, id = null } = {}) {
  if (!fresh && _session) return _session;

  const device_id = id || (fresh ? deviceId() : `${RUN_TAG}-vu-${__VU}`);
  const res = http.post(
    `${BASE_URL}/api/v1/login/device`,
    JSON.stringify({ device_id }),
    Object.assign(jsonHeaders(), { tags: { name: 'POST /login/device' } }),
  );

  const session = parseSession(res);
  if (!session) {
    check(res, { 'device login ok': () => false });
    return null;
  }

  if (!fresh) _session = session;
  return session;
}

/**
 * Log in as one of the seeded email users. Deliberately *not* cached: this
 * scenario exists to measure the cost of a login, so every iteration pays it.
 */
export function emailLogin(index = null) {
  const i = (index === null ? (__VU - 1) % EMAIL_USERS : index) + 1;
  const res = http.post(
    `${BASE_URL}/api/v1/login`,
    JSON.stringify({ email: `${EMAIL_PREFIX}${i}@stress.local`, password: EMAIL_PASSWORD }),
    Object.assign(jsonHeaders(), { tags: { name: 'POST /login' } }),
  );
  return { res, session: parseSession(res) };
}

/** Exchange a refresh token for a new access token. */
export function refresh(refreshToken) {
  const res = http.post(
    `${BASE_URL}/api/v1/refresh`,
    JSON.stringify({ refresh_token: refreshToken }),
    Object.assign(jsonHeaders(), { tags: { name: 'POST /refresh' } }),
  );
  return { res, session: parseSession(res) };
}

/** Drop this VU's cached session — call after a 401 to force a re-login. */
export function resetSession() {
  _session = null;
}

/**
 * The token responses share a shape but not their field names across
 * endpoints, so every caller goes through here rather than reaching into
 * `data.access_token` and silently getting undefined.
 */
function parseSession(res) {
  if (res.status !== 200 && res.status !== 201) return null;
  let body;
  try {
    body = res.json();
  } catch (_e) {
    return null;
  }
  const data = (body && body.data) || {};
  if (!data.access_token) return null;
  return {
    token: data.access_token,
    refresh: data.refresh_token || null,
    userId: (data.user && data.user.id) || data.user_id || null,
  };
}
