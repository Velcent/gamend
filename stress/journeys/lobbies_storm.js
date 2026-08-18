/**
 * What a lobby browser costs when a lot of people have it open.
 *
 * `lobbies` is a single global topic: every lobby created, updated or deleted
 * anywhere is broadcast to everyone subscribed to it. That makes its cost
 * O(subscribers x mutations) rather than O(players), which is a different
 * shape from everything else in the suite — and the one place where a modest
 * number of writes can saturate the machine on its own.
 *
 * The hypothesis being tested is not "is it slow" but *where* the work is:
 * `Gamend.Lobbies` broadcasts a plain tuple over PubSub, so every subscribed
 * channel process serializes the same payload independently — N encodes per
 * event. If the numbers show that, the fix is known and local (encode once and
 * push a pre-serialized broadcast down the fastlane, and/or coalesce list
 * updates on a short tick). Measure first.
 *
 *   SUBSCRIBERS=2000 WRITERS=20 DURATION=2m k6 run journeys/lobbies_storm.js
 *
 * Two roles run concurrently: subscribers hold a socket joined to `lobbies`
 * and count what arrives, writers churn lobbies over HTTP. Read the server's
 * CPU and run-queue next to `t_lobby_broadcast` — the latency is the symptom,
 * the scheduler is the cause.
 *
 * Requires `GAMEND_FEATURES_LIST_LOBBIES_ENABLED=true`: both the API route and
 * this channel sit behind that flag, and joins are rejected with
 * `listing_disabled` without it. Off by default, which is also why this cost
 * does not exist for most deployments.
 */

import { sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { summaryHandler, RUN_TAG, DURATION } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { createLobby, lobbyState, leaveLobby, data } from '../lib/api.js';
import { session, eventMetric } from '../lib/phx.js';
import { okOr } from '../lib/checks.js';

const SUBSCRIBERS = Number.parseInt(__ENV.SUBSCRIBERS || '200', 10);
const WRITERS = Number.parseInt(__ENV.WRITERS || '10', 10);

eventMetric('lobby_broadcast');
const received = new Counter('lobby_broadcasts_received');

export const options = {
  scenarios: {
    subscribers: {
      executor: 'per-vu-iterations',
      vus: SUBSCRIBERS,
      iterations: 1,
      exec: 'subscribe',
      maxDuration: DURATION,
      gracefulStop: '15s',
    },
    writers: {
      executor: 'constant-vus',
      vus: WRITERS,
      duration: DURATION,
      exec: 'churn',
      // Let the subscribers connect first: a broadcast sent before anyone is
      // listening measures nothing, and the join storm would land in the same
      // window as the writes and be indistinguishable from them.
      startTime: '10s',
      gracefulStop: '10s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

export const handleSummary = summaryHandler('lobbies_storm');

export function subscribe() {
  const auth = deviceLogin({ fresh: true, id: `${RUN_TAG}-sub-${__VU}` });
  if (!auth) return;

  session(
    auth.token,
    (client) => {
      client.join('lobbies', {}, (joined) => {
        if (!joined) return;

        // Persistent, not `once`: the point is the sustained rate of events a
        // single subscriber has to decode, so every arrival counts.
        client.on('lobbies', 'lobby_created', () => received.add(1));
        client.on('lobbies', 'lobby_updated', () => received.add(1));
        client.on('lobbies', 'lobby_deleted', () => received.add(1));
      });
    },
    { timeout: durationMs() },
  );
}

export function churn() {
  const auth = deviceLogin();
  if (!auth) return;

  const created = createLobby(auth.token, {
    title: `${RUN_TAG}-storm-${__VU}-${__ITER}`,
    max_users: 8,
  });

  // 422 as well as 409 — see the note in scenarios/lobbies_http.js.
  if (!okOr(created, 'storm lobby create', [409, 422])) return;

  const lobby = data(created);
  if (lobby && lobby.id) {
    // One create plus one update plus one delete is three fan-outs per
    // iteration, which is what a busy browse screen actually sees.
    lobbyState(auth.token, 'playing');
  }

  leaveLobby(auth.token);
  sleep(Number.parseFloat(__ENV.WRITE_PAUSE || '0.5'));
}

function durationMs() {
  const m = String(DURATION).match(/^(\d+)(s|m|h)?$/);
  if (!m) return 60000;
  const n = Number.parseInt(m[1], 10);
  const seconds = m[2] === 'm' ? n * 60 : m[2] === 'h' ? n * 3600 : n;
  return (seconds + 15) * 1000;
}
