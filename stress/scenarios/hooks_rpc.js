/**
 * The plugin RPC path, one layer at a time.
 *
 * Five calls that differ by exactly one thing each, so subtracting neighbours
 * attributes cost:
 *
 *   noop         HTTP → plug → plugin manager → function
 *   memory       + an in-memory lookup
 *   kv_read      + a cached DB read
 *   kv_write     + a DB write
 *   kv_write_lock + an advisory lock around the write
 *
 * Plus `GET /kv/:key` for the same read *without* the plugin layer — the
 * difference between it and `kv_read` is what the hook path itself costs.
 *
 * `MODE` picks one; the default walks all of them in each iteration so a
 * single short run produces the whole comparison.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { kvGet } from '../lib/api.js';
import { callHook, ensureSeed } from '../lib/hooks.js';
import { ok, readsBack } from '../lib/checks.js';

const KEY = `${RUN_TAG}_bench_key`;
const MODE = __ENV.MODE || 'all';

const t = {
  noop: new Trend('t_hook_noop', true),
  memory: new Trend('t_hook_memory', true),
  kv_read: new Trend('t_hook_kv_read', true),
  kv_write: new Trend('t_hook_kv_write', true),
  kv_write_locked: new Trend('t_hook_kv_write_locked', true),
  kv_api: new Trend('t_kv_api_read', true),
};

export const options = constantVus();
export const handleSummary = summaryHandler('hooks_rpc');

export function setup() {
  const session = deviceLogin({ fresh: true, id: `${RUN_TAG}-setup` });
  if (session) ensureSeed(session.token, KEY);
  return { key: KEY };
}

export default function (ctx) {
  const session = deviceLogin();
  if (!session) return;

  const step = (name, fn) => {
    if (MODE !== 'all' && MODE !== name) return null;
    const res = fn();
    t[name].add(res.timings.duration);
    ok(res, `hook ${name}`);
    return res;
  };

  step('noop', () => callHook(session.token, 'stress_noop', []));
  step('memory', () => callHook(session.token, 'stress_memory_read', [ctx.key]));
  step('kv_read', () => callHook(session.token, 'stress_kv_read', [ctx.key]));
  step('kv_write', () => callHook(session.token, 'stress_kv_write', [ctx.key]));

  const locked = step('kv_write_locked', () =>
    callHook(session.token, 'stress_kv_write_locked', [ctx.key]),
  );

  if (locked) {
    // Read-your-write across the cache, and the only proof the locked write
    // actually wrote: the RPC returns `:ok` either way.
    const read = kvGet(session.token, ctx.key);
    t.kv_api.add(read.timings.duration);
    ok(read, 'kv api read');
    readsBack(read, (v) => v.writer, 'stress', 'locked write');
  } else if (MODE === 'all' || MODE === 'kv_api') {
    const read = kvGet(session.token, ctx.key);
    t.kv_api.add(read.timings.duration);
    ok(read, 'kv api read');
  }

  sleep(THINK);
}
