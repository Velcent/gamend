/**
 * The friendship handshake: A requests, B accepts, both sides read it back.
 *
 * Two brand-new device users every iteration, which is unusual here and
 * necessary: a friendship between a given pair exists at most once, and
 * `POST /friends` on a pair that is already friends answers 201 with an empty
 * body and does nothing -- no 409, no new row. Reusing players would therefore
 * not even fail loudly; it would quietly turn every iteration after the first
 * into a no-op that still looks like a write. The two logins are charged to
 * this scenario and show up in `http_reqs`; `auth_device.js` is where the cost
 * of a login on its own is isolated.
 *
 * "Fresh" has to mean fresh across *runs*, not just across iterations, because
 * device ids are derived from RUN_TAG, VU and iteration and would otherwise
 * repeat exactly. Hence the per-run nonce from `setup()`.
 *
 * Two registrations an iteration also makes this the scenario most exposed to
 * the SQLite "database busy" 500 that `Gamend.Analytics.insert_day/2` raises
 * out of the login path under concurrent registration; a red run whose failures
 * are all `device login ok` is that, not a friendship bug.
 *
 * `POST /friends` does not return the friendship id, so the acceptor has to go
 * and find its own request in `GET /me/friend_requests` (under `data.incoming`,
 * matched on `requester.id`). That lookup is not overhead the harness invented;
 * it is a round trip every real client makes, so it is timed as its own step.
 *
 * Both lists are read, not just the acceptor's. One friendship row serves two
 * users from two differently-keyed caches, and "B sees A but A does not see B"
 * is precisely the asymmetry a single-sided check misses -- and the one that
 * gets worse, not better, once the read can land on a different node than the
 * write.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { addFriend, acceptFriend, friendRequests, myFriends, data } from '../lib/api.js';
import { ok, bodyMatches } from '../lib/checks.js';

const tRequest = new Trend('t_friend_request', true);
const tInbox = new Trend('t_friend_inbox', true);
const tAccept = new Trend('t_friend_accept', true);
const tList = new Trend('t_friend_list', true);

export const options = constantVus();
export const handleSummary = summaryHandler('friends');

export function setup() {
  return { run: Date.now().toString(36) };
}

export default function (ctx) {
  const pair = `${RUN_TAG}-f${ctx.run}-${__VU}-${__ITER}`;
  const a = deviceLogin({ fresh: true, id: `${pair}-a` });
  const b = deviceLogin({ fresh: true, id: `${pair}-b` });
  if (!a || !b) return;

  const requested = addFriend(a.token, b.userId);
  tRequest.add(requested.timings.duration);
  if (!ok(requested, 'friend request')) return;

  const inbox = friendRequests(b.token);
  tInbox.add(inbox.timings.duration);
  ok(inbox, 'friend requests');

  const box = data(inbox);
  const pending = box && box.incoming.find((r) => r.requester && r.requester.id === a.userId);
  if (!check(pending, { 'request reaches the recipient': (p) => !!p })) return;

  const accepted = acceptFriend(b.token, pending.id);
  tAccept.add(accepted.timings.duration);
  ok(accepted, 'friend accept');

  const aList = myFriends(a.token);
  const bList = myFriends(b.token);
  tList.add(aList.timings.duration);
  tList.add(bList.timings.duration);
  ok(aList, 'requester friends');
  ok(bList, 'acceptor friends');
  bodyMatches(aList, (fs) => fs.some((f) => f.id === b.userId), 'requester sees the acceptor');
  bodyMatches(bList, (fs) => fs.some((f) => f.id === a.userId), 'acceptor sees the requester');

  sleep(THINK);
}
