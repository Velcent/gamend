/**
 * One socket that joins `user:<id>` and then does nothing.
 *
 * The building block for the connection-ceiling run: N of these is N idle
 * players, which is what a live server mostly holds — a socket process, a
 * channel process, its PubSub subscriptions and its join-time state, per
 * connection. Everything that is not that cost is deliberately absent, so a
 * memory or scheduler figure taken here divides cleanly by the socket count.
 *
 * The dwell, not the flow, ends the iteration: there is nothing to wait for, so
 * the socket is simply held until `session`'s timeout closes it. `join user`
 * still has to pass — a run of sockets that connected but never joined would
 * hold none of the per-channel state this is here to measure.
 */

import { constantVus, summaryHandler } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { session } from '../lib/phx.js';

const DWELL = Number.parseInt(__ENV.DWELL_MS || '5000', 10);

// Phoenix reaps a socket that has been silent for 5 minutes, so the heartbeat
// is what makes a *long* dwell measure a held connection rather than a
// reconnect loop. At the default dwell none is ever sent.
const HEARTBEAT = Number.parseInt(__ENV.HEARTBEAT_MS || '15000', 10);

export const options = constantVus();
export const handleSummary = summaryHandler('ws_join_idle');

export default function () {
  const s = deviceLogin();
  if (!s) return;

  session(s.token, (c) => c.join(`user:${s.userId}`, {}), {
    timeout: DWELL,
    heartbeat: HEARTBEAT,
  });
}
