/**
 * Submit a score, then read it back three ways.
 *
 * Score submission is server-owned -- a player has no endpoint that writes a
 * record -- so it goes through `stress_hook`, which answers with the
 * `leaderboard_id` it wrote to. Taking the id from the response rather than
 * hardcoding a slug means this scenario keeps working when the board is
 * recreated between runs.
 *
 * The three reads are timed apart because they rank different amounts of the
 * board: the page read ranks a window, `/records/me` ranks a single user, and
 * `/records/around/:user_id` has to locate a user's rank first and then window
 * around it. Splitting them is what tells a ranking-query regression apart from
 * a submission regression.
 *
 * `/records/me` carries the check that matters. A score the server accepts and
 * then cannot serve back is the failure mode a latency chart reports as a
 * success, and it is exactly what a stale rank cache looks like from outside.
 * The board's operator is `best`, so the assertion is a lower bound: the stored
 * score is never *less* than the one just submitted.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { leaderboardRecords, myRecord, aroundMe, data } from '../lib/api.js';
import { callHook } from '../lib/hooks.js';
import { ok, bodyMatches, nonEmptyList } from '../lib/checks.js';

const tSubmit = new Trend('t_lb_submit', true);
const tRecords = new Trend('t_lb_records', true);
const tMe = new Trend('t_lb_me', true);
const tAround = new Trend('t_lb_around', true);

export const options = constantVus();
export const handleSummary = summaryHandler('leaderboards');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  // Random, but rooted in wall-clock milliseconds so it beats anything this
  // user submitted in an earlier iteration or an earlier run. With a `best`
  // board a plain random score is usually below the stored one, and the
  // read-back below would then pass without ever observing this write.
  const score = Date.now() * 1000 + Math.floor(Math.random() * 1000);

  const submitted = callHook(
    session.token,
    'stress_submit_score',
    [score],
    'hook stress_submit_score',
  );
  tSubmit.add(submitted.timings.duration);
  if (!ok(submitted, 'score submit')) return;

  const board = data(submitted);
  if (!board || !board.leaderboard_id) return;
  const id = board.leaderboard_id;

  const records = leaderboardRecords(session.token, id);
  tRecords.add(records.timings.duration);
  ok(records, 'lb records');
  nonEmptyList(records, 'lb records');

  const mine = myRecord(session.token, id);
  tMe.add(mine.timings.duration);
  ok(mine, 'lb records me');
  bodyMatches(
    mine,
    (r) => r.user_id === session.userId && r.score >= score,
    'submitted score reads back',
  );

  const around = aroundMe(session.token, id, session.userId);
  tAround.add(around.timings.duration);
  ok(around, 'lb records around');
  bodyMatches(around, (rs) => rs.some((r) => r.user_id === session.userId), 'around includes me');

  sleep(THINK);
}
