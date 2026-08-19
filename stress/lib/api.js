/**
 * Thin HTTP wrappers, one per endpoint the harness touches.
 *
 * These mirror the API paths directly rather than using the generated JS SDK:
 * the SDK is superagent-based and does not run inside k6's runtime. Keeping
 * them one-liners means a route change shows up here and nowhere else.
 *
 * Every call carries a `name` tag so k6 groups metrics per endpoint instead of
 * per URL — otherwise `/api/v1/lobbies/<uuid>/join` becomes thousands of
 * distinct metric series and the summary is unreadable.
 */

import http from 'k6/http';
import { BASE_URL } from './config.js';
import { jsonHeaders } from './auth.js';

function opts(token, name) {
  return Object.assign(jsonHeaders(token), { tags: { name } });
}

function post(path, token, body, name) {
  return http.post(`${BASE_URL}${path}`, JSON.stringify(body || {}), opts(token, name));
}

function patch(path, token, body, name) {
  return http.patch(`${BASE_URL}${path}`, JSON.stringify(body || {}), opts(token, name));
}

function get(path, token, name) {
  return http.get(`${BASE_URL}${path}`, opts(token, name));
}

function del(path, token, body, name) {
  return http.del(`${BASE_URL}${path}`, JSON.stringify(body || {}), opts(token, name));
}

/**
 * `{data: …}` or null. Most endpoints use that envelope; the group controller
 * serializes bare objects, hence the fallback rather than a blind `.data`.
 */
export function data(res) {
  if (res.status < 200 || res.status >= 300) return null;
  try {
    const body = res.json();
    return body && 'data' in body ? body.data : body;
  } catch (_e) {
    return null;
  }
}

// ── Identity ──────────────────────────────────────────────────────────

export const me = (t) => get('/api/v1/me', t, 'GET /me');
export const setDisplayName = (t, name) =>
  patch('/api/v1/me/display_name', t, { display_name: name }, 'PATCH /me/display_name');

// ── KV ────────────────────────────────────────────────────────────────

export const kvGet = (t, key) => get(`/api/v1/kv/${key}`, t, 'GET /kv/:key');

// ── Lobbies ───────────────────────────────────────────────────────────

export const createLobby = (t, body) => post('/api/v1/lobbies', t, body, 'POST /lobbies');
export const listLobbies = (t) => get('/api/v1/lobbies', t, 'GET /lobbies');
export const getLobby = (t, id) => get(`/api/v1/lobbies/${id}`, t, 'GET /lobbies/:id');
export const joinLobby = (t, id, password) =>
  post(`/api/v1/lobbies/${id}/join`, t, password ? { password } : {}, 'POST /lobbies/:id/join');
export const quickJoin = (t, body) =>
  post('/api/v1/lobbies/quick_join', t, body, 'POST /lobbies/quick_join');
export const leaveLobby = (t) => post('/api/v1/lobbies/leave', t, {}, 'POST /lobbies/leave');
export const lobbyState = (t, state) =>
  post('/api/v1/lobbies/state', t, { state }, 'POST /lobbies/state');

// ── Chat ──────────────────────────────────────────────────────────────

export const sendChat = (t, chat_type, chat_ref_id, content) =>
  post('/api/v1/chat/messages', t, { chat_type, chat_ref_id, content }, 'POST /chat/messages');
export const listChat = (t, chat_type, chat_ref_id) =>
  get(
    `/api/v1/chat/messages?chat_type=${chat_type}&chat_ref_id=${chat_ref_id}&page_size=20`,
    t,
    'GET /chat/messages',
  );

// ── Matchmaking ───────────────────────────────────────────────────────

export const joinQueue = (t, body) =>
  post('/api/v1/matchmaking/tickets', t, body, 'POST /matchmaking/tickets');
export const leaveQueue = (t) =>
  del('/api/v1/matchmaking/tickets', t, {}, 'DELETE /matchmaking/tickets');
export const myTicket = (t) =>
  get('/api/v1/matchmaking/tickets/me', t, 'GET /matchmaking/tickets/me');

// ── Groups ────────────────────────────────────────────────────────────

export const createGroup = (t, body) => post('/api/v1/groups', t, body, 'POST /groups');
export const listGroups = (t) => get('/api/v1/groups', t, 'GET /groups');
export const getGroup = (t, id) => get(`/api/v1/groups/${id}`, t, 'GET /groups/:id');
export const myGroups = (t) => get('/api/v1/groups/me', t, 'GET /groups/me');

/**
 * Read a group where 404 is the expected answer. `http_req_failed` counts every
 * 4xx, so a deliberate "is it gone?" probe has to declare its success statuses
 * or a working teardown shows up in the summary as a broken run.
 */
const goneIsFine = http.expectedStatuses({ min: 200, max: 299 }, 404);
export const getGroupOrGone = (t, id) =>
  http.get(
    `${BASE_URL}/api/v1/groups/${id}`,
    Object.assign(opts(t, 'GET /groups/:id (gone)'), { responseCallback: goneIsFine }),
  );
export const joinGroup = (t, id) => post(`/api/v1/groups/${id}/join`, t, {}, 'POST /groups/:id/join');
export const leaveGroup = (t, id) =>
  post(`/api/v1/groups/${id}/leave`, t, {}, 'POST /groups/:id/leave');
export const groupMembers = (t, id) =>
  get(`/api/v1/groups/${id}/members`, t, 'GET /groups/:id/members');

// ── Quests ────────────────────────────────────────────────────────────

export const myQuests = (t) => get('/api/v1/me/quests', t, 'GET /me/quests');
export const claimQuest = (t, key) =>
  post(`/api/v1/me/quests/${key}/claim`, t, {}, 'POST /me/quests/:key/claim');

// ── Leaderboards ──────────────────────────────────────────────────────

export const leaderboardRecords = (t, id) =>
  get(`/api/v1/leaderboards/${id}/records?page_size=20`, t, 'GET /leaderboards/:id/records');
export const myRecord = (t, id) =>
  get(`/api/v1/leaderboards/${id}/records/me`, t, 'GET /leaderboards/:id/records/me');
export const aroundMe = (t, id, userId) =>
  get(
    `/api/v1/leaderboards/${id}/records/around/${userId}`,
    t,
    'GET /leaderboards/:id/records/around/:user_id',
  );

// ── Economy ───────────────────────────────────────────────────────────

export const wallet = (t) => get('/api/v1/me/wallet', t, 'GET /me/wallet');
export const ledger = (t) => get('/api/v1/me/wallet/ledger', t, 'GET /me/wallet/ledger');
export const inventory = (t) => get('/api/v1/me/inventory', t, 'GET /me/inventory');

// ── Friends ───────────────────────────────────────────────────────────

export const addFriend = (t, target_user_id) =>
  post('/api/v1/friends', t, { target_user_id }, 'POST /friends');
export const acceptFriend = (t, id) =>
  post(`/api/v1/friends/${id}/accept`, t, {}, 'POST /friends/:id/accept');
export const myFriends = (t) => get('/api/v1/me/friends', t, 'GET /me/friends');
export const friendRequests = (t) =>
  get('/api/v1/me/friend_requests', t, 'GET /me/friend_requests');

// ── Notifications ─────────────────────────────────────────────────────

export const notifications = (t) =>
  get('/api/v1/notifications?page_size=20', t, 'GET /notifications');
// Sender and recipient must be friends: the endpoint refuses `not_friends` and
// `cannot_notify_self`, so this is a two-user path by construction.
export const sendNotification = (t, user_id, title, content) =>
  post('/api/v1/notifications', t, { user_id, title, content }, 'POST /notifications');
export const deleteNotifications = (t, ids) =>
  del('/api/v1/notifications', t, { ids }, 'DELETE /notifications');
/** Chat read receipts — unrelated to the notification inbox above. */
export const markChatRead = (t, ids) => post('/api/v1/chat/read', t, { ids }, 'POST /chat/read');

// ── Web pages (dead render only) ──────────────────────────────────────

// `Accept-Encoding: gzip`, because that is what a browser sends and Bandit
// compresses by default. Without it k6 gets `identity` and the run measures a
// path no real reader takes: 102 KB of home page on the wire instead of 9.6 KB,
// and none of the CPU the server spends compressing it. k6 decompresses
// transparently, so `res.body` is still the full document to check against --
// only `data_received` changes, and it changes to the truth.
export const page = (path, name) =>
  http.get(`${BASE_URL}${path}`, { tags: { name }, headers: { 'Accept-Encoding': 'gzip' } });
