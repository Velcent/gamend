/**
 * Time-to-match: queue a fresh player, wait for `match_found` on `user:<id>`.
 *
 * A VU cannot play both sides of a match: `ws.connect` blocks the VU for the
 * life of the socket, so one iteration cannot hold two sockets. Every VU
 * instead queues one fresh device user and waits, and the VUs pair up with each
 * other — which is what real players do anyway. Run it with an even `VUS`; an
 * odd one leaves a player with nobody to match, and that iteration correctly
 * fails its check.
 *
 * Matches are formed by a periodic sweep (`Gamend.Matchmaking.Worker`, every
 * `matchmaking_tick_ms` — 3s by default), so `t_match_found` is mostly a
 * uniform draw over one tick and is *not* a latency figure to tune against. It
 * is here to catch the tail: a sweep that stops keeping up under load shows as
 * a value drifting past a single tick, long before it shows as a timeout. The
 * wait is many ticks wide for exactly that reason — a slow sweep must not be
 * reported as a lost event.
 *
 * The queue cannot be namespaced per run: `before_matchmaking_join` is server
 * authority over `match_params` and rewrites whatever the client sends into
 * `{mode, band}` (example_hook), rejecting any mode outside casual/ranked. So
 * concurrent runs share a bucket and may seat each other's players — harmless
 * here, because the assertion is per-caller: the payload is checked against
 * `GET /me`, and a `match_found` naming a lobby the caller is not actually in
 * is the failure that matters. `casual` is the default because `ranked` swaps
 * in the plugin's own matcher, which is a different thing to measure.
 */

import { constantVus, summaryHandler } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { joinQueue, leaveQueue, leaveLobby, me } from '../lib/api.js';
import { session, eventMetric } from '../lib/phx.js';
import { ok, readsBack } from '../lib/checks.js';

const MATCH_TIMEOUT = Number.parseInt(__ENV.MATCH_TIMEOUT_MS || '20000', 10);
const PARAMS = { mode: __ENV.MATCH_MODE || 'casual' };

eventMetric('match_found');

export const options = constantVus();
export const handleSummary = summaryHandler('matchmaking');

export default function () {
  // Fresh every iteration: a player already in a lobby cannot be seated, and
  // the sweep would drop the whole match rather than just that ticket.
  const s = deviceLogin({ fresh: true });
  if (!s) return;

  const topic = `user:${s.userId}`;
  let lobbyId = null;

  session(
    s.token,
    (c, done) => {
      c.join(topic, {}, (joined) => {
        if (!joined) return done();

        c.once(
          topic,
          'match_found',
          'match_found',
          (p) => {
            lobbyId = (p && p.lobby_id) || null;
            done();
          },
          { timeout: MATCH_TIMEOUT },
        );

        // Queued only after the channel is up: the queue drops players the
        // database considers offline, and joining `user:<id>` is what marks
        // this one online.
        const ticket = { match_params: PARAMS, min_players: 2, max_players: 2 };
        ok(joinQueue(s.token, ticket), 'queue join');
      });
    },
    { timeout: MATCH_TIMEOUT + 2000 },
  );

  if (lobbyId) {
    readsBack(me(s.token), (u) => u.lobby_id, lobbyId, 'match_found lobby');
    ok(leaveLobby(s.token), 'lobby leave');
  } else {
    ok(leaveQueue(s.token), 'queue leave');
  }
}
