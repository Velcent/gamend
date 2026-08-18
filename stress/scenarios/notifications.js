/**
 * Send a notification, read the inbox, clear it.
 *
 * The inbox read is a per-user list that a client opens constantly, and the
 * send is the write behind every "X invited you" in the product. They are timed
 * apart because only one of them scales with the recipient's history: the list
 * is paginated and cached, the send is an insert plus a push fan-out on the
 * recipient's channel.
 *
 * A friended pair per VU, made once and reused for the whole run. Sending
 * requires it — `Notifications.send_notification/2` refuses `:not_friends` and
 * `:cannot_notify_self`, so a lone device user cannot exercise this path at
 * all. Building the pair per *iteration* (as friends.js must) would make every
 * iteration four logins plus a handshake, and this scenario would end up
 * measuring friendship rather than notifications.
 *
 * The delete is not cleanup for its own sake: `max_notifications_per_user` is
 * 500, and a VU that sends without clearing would drift into the pruning path
 * partway through a long run and silently start timing something else.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import {
  addFriend,
  acceptFriend,
  friendRequests,
  notifications,
  sendNotification,
  deleteNotifications,
  data,
} from '../lib/api.js';
import { ok, bodyMatches } from '../lib/checks.js';

const tSend = new Trend('t_notify_send', true);
const tList = new Trend('t_notify_list', true);
const tDelete = new Trend('t_notify_delete', true);

export const options = constantVus();
export const handleSummary = summaryHandler('notifications');

export function setup() {
  // Device ids are derived from RUN_TAG and VU, so without a per-run nonce a
  // second run reuses the first run's users — who are already friends, and
  // whose repeat request answers 201 while doing nothing.
  return { run: Date.now().toString(36) };
}

/** The VU's friended pair, made on first use. */
let _pair = null;

export default function (ctx) {
  const pair = befriendedPair(ctx.run);
  if (!pair) return;

  const { sender, recipient } = pair;

  const sent = sendNotification(sender.token, recipient.userId, `${RUN_TAG} ping`, 'hello');
  tSend.add(sent.timings.duration);
  if (!ok(sent, 'notification send')) return;

  const inbox = notifications(recipient.token);
  tList.add(inbox.timings.duration);
  ok(inbox, 'notification list');

  const list = data(inbox);
  const items = Array.isArray(list) ? list : (list && list.notifications) || [];
  bodyMatches(inbox, () => items.length > 0, 'sent notification reaches the inbox');

  if (items.length > 0) {
    const cleared = deleteNotifications(
      recipient.token,
      items.map((n) => n.id),
    );
    tDelete.add(cleared.timings.duration);
    ok(cleared, 'notification delete');
  }

  sleep(THINK);
}

function befriendedPair(run) {
  if (_pair) return _pair;

  const base = `${RUN_TAG}-n${run}-${__VU}`;
  const sender = deviceLogin({ fresh: true, id: `${base}-a` });
  const recipient = deviceLogin({ fresh: true, id: `${base}-b` });
  if (!sender || !recipient) return null;

  if (!ok(addFriend(sender.token, recipient.userId), 'pair request')) return null;

  const box = data(friendRequests(recipient.token));
  const pending =
    box && box.incoming.find((r) => r.requester && r.requester.id === sender.userId);

  if (!check(pending, { 'pair request arrives': (p) => !!p })) return null;
  if (!ok(acceptFriend(recipient.token, pending.id), 'pair accept')) return null;

  _pair = { sender, recipient };
  return _pair;
}
