/**
 * The group write path: create -> read back -> list members -> leave.
 *
 * Deliberately the same shape as `lobbies_http.js`, because the two are the
 * same operation over different storage: a lobby is ephemeral and a group is a
 * durable row with a membership table behind it, so subtracting one from the
 * other is what durability costs. Every step is read back rather than trusted --
 * a group that answers 201 with an id it then cannot serve, or a membership row
 * the create transaction did not write, is a failure the latency numbers report
 * as a success.
 *
 * Each iteration cleans up after itself instead of using a fresh device user,
 * and the choice is not cosmetic. `max_groups_created_per_user` (20) counts
 * *current* admin memberships rather than lifetime creations, so leaving is
 * enough to stay under it forever; a fresh user per iteration would dodge the
 * cap too, but it would also add a user-creation write to every iteration and
 * make this scenario a measurement of registration as much as of groups.
 * Leaving as the last member disbands the group, which the 404 below proves.
 *
 * The 409 is still handled rather than swallowed: it is what the cap answers,
 * so reaching it means an earlier iteration died before its leave and stranded
 * a group. Repairing exactly that -- leave one stranded group, skip the
 * iteration -- keeps the cap from turning one lost iteration into a run of them,
 * and the failed check from the lost iteration is still in the summary.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import {
  createGroup,
  getGroup,
  getGroupOrGone,
  groupMembers,
  leaveGroup,
  myGroups,
  data,
} from '../lib/api.js';
import { ok, okOr, readsBack, bodyMatches } from '../lib/checks.js';

const tCreate = new Trend('t_group_create', true);
const tMembers = new Trend('t_group_members', true);
const tLeave = new Trend('t_group_leave', true);

export const options = constantVus();
export const handleSummary = summaryHandler('groups');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  const title = `${RUN_TAG}-g-${__VU}-${__ITER}`;

  const created = createGroup(session.token, { title, description: RUN_TAG });
  tCreate.add(created.timings.duration);

  if (!okOr(created, 'group create', [409])) return;
  if (created.status === 409) {
    releaseOne(session.token);
    return;
  }

  const group = data(created);
  if (!group || !group.id) return;

  const fetched = getGroup(session.token, group.id);
  ok(fetched, 'group get');
  readsBack(fetched, (g) => g.title, title, 'group create');

  const members = groupMembers(session.token, group.id);
  tMembers.add(members.timings.duration);
  ok(members, 'group members');
  bodyMatches(
    members,
    (ms) => ms.some((m) => m.user_id === session.userId && m.role === 'admin'),
    'creator is an admin member',
  );

  const left = leaveGroup(session.token, group.id);
  tLeave.add(left.timings.duration);
  ok(left, 'group leave');

  const gone = getGroupOrGone(session.token, group.id);
  check(gone, { 'group disbanded on leave': (r) => r.status === 404 });

  sleep(THINK);
}

/** Free one slot under the per-user cap by leaving a group stranded earlier. */
function releaseOne(token) {
  const mine = data(myGroups(token));
  if (mine && mine.length > 0) leaveGroup(token, mine[0].id);
}
