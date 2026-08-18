/**
 * One player, doing several things — the capacity number.
 *
 * The isolated scenarios answer "what does this operation cost". This answers
 * "how many players fit", which is a different question: a real session mixes
 * cached reads with occasional writes, holds a socket open, and arrives
 * independently of how fast the server is currently answering.
 *
 * Hence a ramping *arrival rate* rather than a fixed VU count. With constant
 * VUs a slowing server produces less load, which hides saturation behind a
 * comfortable-looking latency curve; a fixed arrival rate keeps offering
 * sessions and lets the queue grow, which is what a player population actually
 * does. Ramp until the SLO in lib/config.js breaks — that VU/arrival number is
 * the machine's capacity.
 *
 *   PEAK=500 RAMP=5m k6 run journeys/player_session.js
 *
 * The weights (30% matchmaking, 50% lobby+chat, 20% groups) are a guess at a
 * session-based game's mix. They are one env var away from being something
 * else, and any conclusion drawn from this number should say which mix it used.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { rampingArrivalRate, summaryHandler, RUN_TAG } from '../lib/config.js';
import { deviceLogin, resetSession } from '../lib/auth.js';
import {
  me,
  myQuests,
  createLobby,
  sendChat,
  leaveLobby,
  joinQueue,
  leaveQueue,
  createGroup,
  leaveGroup,
  wallet,
  data,
} from '../lib/api.js';
import { callHook } from '../lib/hooks.js';
import { ok, okOr } from '../lib/checks.js';

const PEAK = Number.parseInt(__ENV.PEAK || '200', 10);
const RAMP = __ENV.RAMP || '3m';
const HOLD = __ENV.HOLD || '2m';

const tSession = new Trend('t_session', true);

export const options = rampingArrivalRate([
  { duration: RAMP, target: PEAK },
  { duration: HOLD, target: PEAK },
]);

export const handleSummary = summaryHandler('player_session');

export default function () {
  const started = Date.now();
  const session = deviceLogin();
  if (!session) return;

  const profile = me(session.token);
  if (profile.status === 401) {
    resetSession();
    return;
  }
  ok(profile, 'session me');

  // Every session checks its quests and its wallet — the two screens a player
  // opens without being asked to.
  ok(myQuests(session.token), 'session quests');
  callHook(session.token, 'stress_quest_event', [1]);

  const roll = Math.random();
  if (roll < 0.3) matchmaking(session);
  else if (roll < 0.8) lobbyAndChat(session);
  else groups(session);

  ok(wallet(session.token), 'session wallet');

  tSession.add(Date.now() - started);

  // Think time, and a separate knob from the scenarios' `THINK`: this is the
  // one place where pacing is the point. Without it every VU is a bot hammering
  // as fast as the server allows, and the arrival rate stops describing
  // anything a player does.
  sleep(Number.parseFloat(__ENV.SESSION_THINK || '1'));
}

function matchmaking(session) {
  // "casual" rather than a made-up mode: when `example_hook` is also loaded it
  // rejects anything outside casual|ranked from `before_matchmaking_join`, and
  // with only `stress_hook` loaded any mode passes — so this one value works in
  // both configurations. See stress/README.md on why a measurement run should
  // load stress_hook alone.
  const ticket = joinQueue(session.token, {
    match_params: { mode: 'casual' },
    min_players: 2,
    max_players: 4,
  });

  // 409 means this player is already queued or already in a match — an
  // ordinary outcome under load, not an error.
  okOr(ticket, 'queue join', [409]);

  sleep(0.5);
  leaveQueue(session.token);
}

function lobbyAndChat(session) {
  const created = createLobby(session.token, {
    title: `${RUN_TAG}-${__VU}-${__ITER}`,
    max_users: 8,
  });

  // 422 as well as 409 — see the note in scenarios/lobbies_http.js.
  if (!okOr(created, 'session lobby', [409, 422])) return;

  const lobby = data(created);
  if (lobby && lobby.id) {
    ok(sendChat(session.token, 'lobby', lobby.id, 'gg'), 'session chat');
  }

  leaveLobby(session.token);
}

function groups(session) {
  const created = createGroup(session.token, {
    title: `${RUN_TAG}-g-${__VU}-${__ITER}`,
    type: 'public',
  });

  // Group membership caps (50 joined / 20 created per user) are reached
  // quickly when one device user runs many iterations, so each session cleans
  // up after itself rather than letting the cap turn into a fake error rate.
  if (okOr(created, 'session group', [409, 422])) {
    const group = data(created);
    if (group && group.id) leaveGroup(session.token, group.id);
  }
}
