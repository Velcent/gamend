/**
 * Chat broadcast latency: POST a message, wait for it on `lobby:<id>`.
 *
 * The message the sender gets back is the same frame every other member of the
 * lobby gets, so the round trip measured here — HTTP write, persist, PubSub,
 * per-channel serialize, frame out — is the number that decides whether chat
 * feels live. Nothing about it is visible in the POST's own duration, which
 * returns as soon as the row is written.
 *
 * The arriving payload is compared against what was sent: a `chat_message_created`
 * that fans out fast while carrying the wrong (or an older) message is the
 * failure that a pure latency number would report as a success.
 */

import { check } from 'k6';
import { constantVus, summaryHandler, RUN_TAG, SLO } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { createLobby, sendChat, leaveLobby, data } from '../lib/api.js';
import { session, eventMetric } from '../lib/phx.js';
import { ok, okOr } from '../lib/checks.js';

const EVENT_TIMEOUT = Number.parseInt(__ENV.EVENT_TIMEOUT_MS || '5000', 10);

eventMetric('chat_event');

export const options = constantVus({
  thresholds: { t_chat_event: [`p(95)<${SLO.event_p95}`] },
});
export const handleSummary = summaryHandler('chat');

export default function () {
  const s = deviceLogin();
  if (!s) return;

  const title = `${RUN_TAG}-chat-${__VU}-${__ITER}`;
  const created = createLobby(s.token, { title, max_users: 8 });

  // See lobby_ws.js: still in a lobby from a previous iteration, so leave and
  // start clean next time.
  if (!okOr(created, 'lobby create', [409, 422])) return;
  if (created.status !== 201) {
    leaveLobby(s.token);
    return;
  }

  const lobby = data(created);
  if (!lobby || !lobby.id) return;

  const topic = `lobby:${lobby.id}`;
  const content = `${RUN_TAG} hello from ${__VU} iter ${__ITER}`;

  session(
    s.token,
    (c, done) => {
      c.join(topic, {}, (joined) => {
        if (!joined) return done();

        c.once(
          topic,
          'chat_message_created',
          'chat_event',
          (p) => {
            check(p, {
              'chat_message_created carries the sent content': (x) => !!x && x.content === content,
            });
            done();
          },
          { timeout: EVENT_TIMEOUT },
        );

        ok(sendChat(s.token, 'lobby', lobby.id, content), 'chat send');
      });
    },
    { timeout: EVENT_TIMEOUT + 2000 },
  );

  ok(leaveLobby(s.token), 'lobby leave');
}
