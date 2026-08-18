/**
 * Correctness checks that run *inside* the load test.
 *
 * A benchmark where every request returns 200 quickly while the cache serves
 * a value two writes stale is worse than a slow one — it reports success. So
 * every write path here is followed by a read that has to observe it, and the
 * check rate sits next to latency in the report.
 *
 * On one node this proves cache invalidation. On the later multi-node run
 * (Postgres + Redis L2, two app instances behind the proxy) the same checks
 * prove the distributed cache, because the read usually lands on the node that
 * did not do the write.
 */

import { check } from 'k6';
import { data } from './api.js';

/** 2xx, and the body parses. The floor every call gets. */
export function ok(res, label) {
  return check(res, {
    [`${label} 2xx`]: (r) => r.status >= 200 && r.status < 300,
  });
}

/** 2xx or one of `allowed` — for endpoints where a conflict is a real outcome. */
export function okOr(res, label, allowed) {
  return check(res, {
    [`${label} ok`]: (r) => (r.status >= 200 && r.status < 300) || allowed.includes(r.status),
  });
}

/**
 * Read-your-write: `readFn` must observe what `expected` says was just
 * written. `pick` pulls the field out of the read response.
 */
export function readsBack(readRes, pick, expected, label) {
  const body = data(readRes);
  const actual = body ? pick(body) : null;
  return check(actual, {
    [`${label} reads back`]: (v) => v === expected,
  });
}

/** A response body satisfies `pred`. */
export function bodyMatches(res, pred, label) {
  const body = data(res);
  return check(body, {
    [label]: (b) => b !== null && pred(b),
  });
}

/** A list response is a non-empty array. */
export function nonEmptyList(res, label) {
  const body = data(res);
  return check(body, {
    [`${label} non-empty`]: (b) => Array.isArray(b) && b.length > 0,
  });
}
