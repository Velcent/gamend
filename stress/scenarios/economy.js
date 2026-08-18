/**
 * Credit a wallet through the plugin, then read the three surfaces that have to
 * agree with it.
 *
 * `Economy.grant/4` is the shape every payout in the product shares -- an
 * advisory lock around a read-modify-write of the balance plus a ledger insert
 * in the same transaction -- and no player-facing endpoint calls it, so the
 * harness drives it the way a game server does. Quest rewards and purchases all
 * land on this path, which makes `t_credit` a number several features inherit.
 *
 * The wallet read is the read-your-write: a balance the grant returned but the
 * wallet endpoint does not show is a stale currency cache, and it is invisible
 * from latency alone. The ledger read is the second half of the same write --
 * balance and ledger are written together and a run where only one of them
 * moved is a broken transaction, not a slow one.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { wallet, ledger, inventory, data } from '../lib/api.js';
import { callHook } from '../lib/hooks.js';
import { ok, bodyMatches } from '../lib/checks.js';

const AMOUNT = 5;

const tCredit = new Trend('t_credit', true);
const tWallet = new Trend('t_wallet', true);
const tLedger = new Trend('t_ledger', true);
const tInventory = new Trend('t_inventory', true);

export const options = constantVus();
export const handleSummary = summaryHandler('economy');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  const credited = callHook(session.token, 'stress_credit', [AMOUNT], 'hook stress_credit');
  tCredit.add(credited.timings.duration);
  if (!ok(credited, 'wallet credit')) return;

  // Gold only ever accumulates -- the starter kit, every quest reward, and every
  // previous iteration of this scenario are already in there -- so an equality
  // check against AMOUNT would fail from the second iteration on. The tightest
  // sound bound is the balance the grant itself reported.
  const after = data(credited);
  const expected = after && typeof after.balance === 'number' ? after.balance : AMOUNT;

  const balances = wallet(session.token);
  tWallet.add(balances.timings.duration);
  ok(balances, 'wallet');
  bodyMatches(balances, (w) => (w.gold || 0) >= expected, 'wallet reflects the credit');

  const entries = ledger(session.token);
  tLedger.add(entries.timings.duration);
  ok(entries, 'wallet ledger');
  bodyMatches(
    entries,
    (es) => es.some((e) => e.reason === 'stress' && e.delta === AMOUNT),
    'ledger records the credit',
  );

  const items = inventory(session.token);
  tInventory.add(items.timings.duration);
  ok(items, 'inventory');

  sleep(THINK);
}
