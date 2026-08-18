/**
 * The same player session, held at a survivable rate for a long time.
 *
 * Capacity runs answer "how much", soaks answer "for how long" — and they find
 * different bugs. Everything that only shows up with time lives here: a cache
 * that grows without bound, a process leak per lobby, WAL that never
 * checkpoints, a scheduler that falls behind, a connection pool that slowly
 * fills with orphaned checkouts. None of those are visible in a 5-minute ramp.
 *
 * Run it at ~70% of the capacity the ramp found, so the machine is genuinely
 * working but not saturated: at 100% the queue itself explains any degradation
 * and the slow leak stays hidden underneath it.
 *
 *   RATE=140 SOAK=30m k6 run journeys/soak.js
 *
 * Read it against the metrics dashboard, not this summary: flat RSS, flat
 * process count and a flat p95 across the whole window is the pass. A rising
 * line in any of them is the finding, even if every request still returned 200.
 */

import { summaryHandler } from '../lib/config.js';
import { thresholds } from '../lib/config.js';
import playerSession from './player_session.js';

const RATE = Number.parseInt(__ENV.RATE || '50', 10);
const SOAK = __ENV.SOAK || '30m';

export const options = {
  scenarios: {
    soak: {
      // Constant arrival rate, not constant VUs: the point is to hold the
      // offered load steady for the whole window, including through a stall.
      // With VUs, a stall reduces the load and the soak quietly stops being
      // one.
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: SOAK,
      preAllocatedVUs: Number.parseInt(__ENV.PRE_VUS || String(RATE * 3), 10),
      maxVUs: Number.parseInt(__ENV.MAX_VUS || String(RATE * 10), 10),
      gracefulStop: '30s',
    },
  },
  thresholds: thresholds(),
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

export const handleSummary = summaryHandler('soak');

// The flow is the capacity journey's, unchanged on purpose: a soak that
// exercises a different mix cannot be compared with the ramp that sized it.
export default playerSession;
