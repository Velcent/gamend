/**
 * A minimal Phoenix Channels client for k6.
 *
 * The JS SDK's realtime layer is built on the `phoenix` npm package, which
 * does not run in k6's runtime — but the v2 wire protocol is small enough to
 * reproduce exactly: every frame is a JSON array
 *
 *     [join_ref, ref, topic, event, payload]
 *
 * and a reply comes back as `phx_reply` carrying the `ref` it answers plus
 * `{status, response}`. That is the whole protocol this needs.
 *
 * Usage — one socket per iteration, flow expressed as callbacks:
 *
 *     eventMetric('match');   // init context, once per scenario
 *
 *     session(token, (c, done) => {
 *       c.join(`user:${userId}`, {}, () => {
 *         c.once(`user:${userId}`, 'match_found', 'match', (payload) => {
 *           // …assert on payload…
 *           done();
 *         });
 *       });
 *     });
 *
 * `done()` closes the socket and ends the iteration. If it is never called the
 * safety timeout closes the socket anyway, so a missed event costs one
 * iteration rather than hanging a VU for the whole run.
 */

import ws from 'k6/ws';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { BASE_URL, WS_PROTOBUF } from './config.js';

const joinTrend = new Trend('t_ws_join', true);
const eventTrends = {};
const eventCounts = {};
const framesIn = new Counter('ws_frames_in');
const framesOut = new Counter('ws_frames_out');

/** Socket URL. `vsn=2.0.0` is required — the v1 serializer cannot carry binary. */
export function socketUrl(token, format) {
  const base = BASE_URL.replace(/^http/, 'ws');
  const fmt = format || (WS_PROTOBUF ? 'protobuf' : 'json');
  return `${base}/socket/websocket?token=${encodeURIComponent(token)}&vsn=2.0.0&format=${fmt}`;
}

/**
 * Open a socket, run `flow(client, done)` once connected, and block until
 * `done()` or `timeout` — whichever comes first.
 */
export function session(token, flow, { timeout = 30000, format = null, heartbeat = 30000 } = {}) {
  const url = socketUrl(token, format);

  return ws.connect(url, null, function (socket) {
    const client = new Client(socket);

    socket.on('open', function () {
      // Phoenix reaps a silent socket after its `timeout` (5 minutes here).
      // Anything longer-lived than one short iteration needs these.
      if (heartbeat > 0) {
        socket.setInterval(function () {
          client._send(null, 'phoenix', 'heartbeat', {});
        }, heartbeat);
      }

      flow(client, function () {
        socket.close();
      });
    });

    socket.on('message', function (raw) {
      framesIn.add(1);
      client._dispatch(raw);
    });

    // Protobuf frames arrive as binary. k6 has no decoder for them, which is
    // fine: the point of protobuf mode is to make the *server* pay the encode
    // cost, and the frame count plus arrival time still measure that.
    socket.on('binaryMessage', function (buf) {
      framesIn.add(1);
      if (client._onBinary) client._onBinary(buf);
    });

    socket.on('error', function (e) {
      if (e && e.error && e.error() !== 'websocket: close sent') {
        check(null, { 'ws no error': () => false });
      }
    });

    // Safety net: never let a missing event pin a VU open.
    socket.setTimeout(function () {
      socket.close();
    }, timeout);
  });
}

class Client {
  constructor(socket) {
    this.socket = socket;
    this._ref = 0;
    this._joinRefs = {};
    this._replyHandlers = {};
    this._eventHandlers = {};
    this._onBinary = null;
  }

  /** Join a topic. `cb(ok, response)` fires on the reply. */
  join(topic, payload, cb) {
    const ref = this._nextRef();
    this._joinRefs[topic] = ref;
    const started = Date.now();

    this._replyHandlers[ref] = (status, response) => {
      joinTrend.add(Date.now() - started);
      const ok = status === 'ok';
      check(ok, { [`join ${topicKind(topic)}`]: (v) => v });
      if (cb) cb(ok, response);
    };

    this._send(ref, topic, 'phx_join', payload || {});
  }

  /** Push an event. `cb(status, response)` fires on the reply, if any. */
  push(topic, event, payload, cb) {
    const ref = this._nextRef();
    if (cb) this._replyHandlers[ref] = cb;
    this._send(ref, topic, event, payload || {});
  }

  /** Register a persistent handler for `event` on `topic`. */
  on(topic, event, handler) {
    const key = `${topic}|${event}`;
    (this._eventHandlers[key] = this._eventHandlers[key] || []).push({ handler, once: false });
  }

  /**
   * Wait for one occurrence of `event`, timing how long it took.
   *
   * `metric` names the Trend (`t_<metric>`) and the check, so a scenario can
   * report "how long until the lobby saw my message" separately from "how long
   * until a match formed". A no-show fails the check rather than passing
   * silently, which is the whole reason event delivery is measured here.
   */
  once(topic, event, metric, handler, { timeout = 5000 } = {}) {
    const key = `${topic}|${event}`;
    const started = Date.now();
    let fired = false;

    const trend = trendFor(metric);

    (this._eventHandlers[key] = this._eventHandlers[key] || []).push({
      once: true,
      handler: (payload) => {
        fired = true;
        trend.add(Date.now() - started);
        countFor(metric).add(1);
        check(true, { [`${metric} arrived`]: (v) => v });
        if (handler) handler(payload);
      },
    });

    this.socket.setTimeout(() => {
      if (!fired) check(false, { [`${metric} arrived`]: (v) => v });
    }, timeout);
  }

  /** Handler for binary (protobuf) frames. */
  onBinary(cb) {
    this._onBinary = cb;
  }

  close() {
    this.socket.close();
  }

  // ── Wire ────────────────────────────────────────────────────────────

  _nextRef() {
    this._ref += 1;
    return String(this._ref);
  }

  _send(ref, topic, event, payload) {
    const joinRef = this._joinRefs[topic] || null;
    framesOut.add(1);
    this.socket.send(JSON.stringify([joinRef, ref, topic, event, payload]));
  }

  _dispatch(raw) {
    let frame;
    try {
      frame = JSON.parse(raw);
    } catch (_e) {
      return;
    }
    if (!Array.isArray(frame) || frame.length < 5) return;

    const [, ref, topic, event, payload] = frame;

    if (event === 'phx_reply') {
      const h = this._replyHandlers[ref];
      if (h) {
        delete this._replyHandlers[ref];
        h((payload && payload.status) || 'error', (payload && payload.response) || {});
      }
      return;
    }

    const key = `${topic}|${event}`;
    const handlers = this._eventHandlers[key];
    if (!handlers || handlers.length === 0) return;

    this._eventHandlers[key] = handlers.filter((h) => {
      h.handler(payload);
      return !h.once;
    });
  }
}

/**
 * Declare the Trend that a later `once(…, metric, …)` fills.
 *
 * k6 refuses to create a metric outside the init context, so `once` cannot
 * conjure one the first time an event arrives — the name has to be known before
 * the run starts. Scenarios call this at module scope, which has the second
 * benefit of making `t_<metric>` nameable in `thresholds`.
 */
export function eventMetric(name) {
  const key = `t_${name}`;
  if (!eventTrends[key]) {
    eventTrends[key] = new Trend(key, true);
    // A paired count, because an empty k6 Trend summarises as all-zeros and is
    // indistinguishable from an event that really did arrive instantly. Without
    // this, a run where every iteration bailed before waiting for the event
    // reports "0.0 ms delivery" — the most flattering possible number for work
    // that never happened.
    eventCounts[`n_${name}`] = new Counter(`n_${name}`);
  }
  return eventTrends[key];
}

function countFor(name) {
  return eventCounts[`n_${name}`];
}

function trendFor(name) {
  const trend = eventTrends[`t_${name}`];
  if (!trend) throw new Error(`phx: call eventMetric('${name}') in the init context`);
  return trend;
}

/** `lobby:abc-123` → `lobby` — keeps join metrics from exploding per id. */
function topicKind(topic) {
  const i = topic.indexOf(':');
  return i === -1 ? topic : topic.slice(0, i);
}
