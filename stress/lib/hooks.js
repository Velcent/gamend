/**
 * Plugin RPC calls — `POST /api/v1/hooks/call`.
 *
 * This is how the harness reaches everything a player has no endpoint for
 * (quest progress, score submission, wallet credits, seeding), and how it
 * measures the plugin path itself. See `modules/plugins_examples/stress_hook`.
 */

import http from 'k6/http';
import { BASE_URL, PLUGIN } from './config.js';
import { jsonHeaders } from './auth.js';
import { data } from './api.js';

/** Call `fn` on the stress plugin. `label` groups the metric. */
export function callHook(token, fn, args = [], label = null) {
  return http.post(
    `${BASE_URL}/api/v1/hooks/call`,
    JSON.stringify({ plugin: PLUGIN, fn, args }),
    Object.assign(jsonHeaders(token), { tags: { name: label || `hook ${fn}` } }),
  );
}

/** Call and unwrap, or null. */
export function hook(token, fn, args = [], label = null) {
  return data(callHook(token, fn, args, label));
}

/** Call a hook over an open channel instead of HTTP, to compare transports. */
export function callHookWs(client, topic, fn, args = [], cb = null) {
  client.push(topic, 'call_hook', { plugin: PLUGIN, fn, args }, cb);
}

/**
 * Idempotent per-run setup: the ETS table, the seeded KV key, and the seeded
 * email users. Safe to call from every scenario's `setup()` — the plugin skips
 * what already exists — which is what keeps scenarios runnable one at a time.
 */
export function ensureSeed(token, key, { users = 0, prefix = 'stress-', password = null } = {}) {
  callHook(token, 'stress_setup', [key], 'hook stress_setup');
  if (users > 0 && password) {
    callHook(token, 'stress_seed_users', [users, prefix, password], 'hook stress_seed_users');
  }
}
