/**
 * PATCH /api/v1/me/display_name, then GET /api/v1/me must show the new name.
 *
 * The canonical read-your-write check. `/me` is served from the user cache and
 * the PATCH is what has to invalidate it, so a broken invalidation shows up
 * here as a failed check while both requests stay fast and return 200 — the
 * exact failure a latency-only benchmark reports as a success.
 *
 * Single-node this proves the cache is invalidated. On the two-node run it
 * proves L2, because the read usually lands on the node that did not write.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin, resetSession } from '../lib/auth.js';
import { me, setDisplayName } from '../lib/api.js';
import { ok, readsBack } from '../lib/checks.js';

const tWrite = new Trend('t_profile_write', true);
const tRead = new Trend('t_profile_read', true);

export const options = constantVus();
export const handleSummary = summaryHandler('profile_write');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  // Unique per write, so the read cannot pass on a value left by an earlier
  // iteration — the failure mode a fixed name would hide entirely.
  const name = `${RUN_TAG}-${__VU}-${__ITER}`;

  const written = setDisplayName(session.token, name);
  tWrite.add(written.timings.duration);

  if (written.status === 401) {
    resetSession();
    return;
  }
  if (!ok(written, 'display name write')) return;

  const read = me(session.token);
  tRead.add(read.timings.duration);
  ok(read, 'me after write');
  readsBack(read, (u) => u.display_name, name, 'display name');

  sleep(THINK);
}
