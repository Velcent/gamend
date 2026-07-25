# Retention for every unbounded table

Design spec. Extends `GameServer.Retention` from the seven classes it prunes
today to every table that grows without bound, on one configurable pattern.

Goal: no table in a long-running deployment grows forever unless an operator
chose that, and every window is a documented `RETENTION_*` env var.

## Where we are

`Retention` is a supervised GenServer that sweeps every 6h (5 min after boot)
and already prunes: chat messages, notifications, payment provider events,
OAuth sessions, expired IP bans, lobby snapshots (+ events + blobs), quest
period rows, and push tokens. Oban prunes its own `oban_jobs` (7d, via
`Oban.Plugins.Pruner`), and matchmaking sweeps offline tickets in its worker.

Each entry follows the same shape — an env var read in
`config/host_runtime.exs`, `0`/unset meaning "keep forever", and a
`prune_older_than/2`-style helper. That pattern is the one this spec extends;
nothing about it changes.

## The gaps

Audited every table. These grow unbounded with **no** retention at all:

| Table | Why it grows | Proposed default |
| --- | --- | --- |
| `lobbies` | Core never deletes an abandoned lobby — only party disband, a failed matchmaking seat, or an admin do. Games write their own reapers (polyglot's is 362 lines). | terminal: **15 min**, abandoned: **24 h** |
| `users_tokens` | Rows are deleted on logout/password change only. An expired session or magic-link token is dead weight that nothing removes. | **prune when expired** (see below) |
| `group_invites`, `party_invites`, `group_join_requests` | Resolved rows (`accepted`/`declined`/`rejected`/`cancelled`) are never deleted — one row per social interaction, forever. | **30 d** after resolution |
| `matchmaking_tickets` | The worker prunes tickets whose owner went offline, but a ticket whose owner stays connected and never matches has no upper bound. | **24 h** |
| `tournaments` + entries/matches/brackets | Finished tournaments and their bracket rows accumulate per occurrence; recurring tournaments create one per cycle. | **0 (keep)**, opt-in |
| `ledger_entries`, `inventory_ledger` | Append-only by design — one row per currency/item mutation, forever. | **0 (keep)** — financial audit trail; opt-in only |
| `lobby_events` | Pruned only via the snapshot sweep; orphan rows for lobbies that never produced a snapshot are missed. | folded into the lobby sweep |

Deliberately **not** given retention: `users`, `groups`, `parties`,
`friendships`, `wallets`, `inventory_items`, `kv_entries`,
`leaderboard_records`, `chat_read_cursors`, `quests`, `purchases`,
`entitlements`, `store_products`, `provider_products`,
`reconciliation_cursors`. These are entity or balance state, not history —
they are bounded by their owners and deleting rows would destroy player data,
not reclaim garbage. (Cascade on user deletion already covers the per-user
ones.)

## Lobbies — the one that needs real logic

Everything else is "delete rows older than N". Lobbies are not, and getting
this wrong deletes live games. Rules, in order:

1. **Terminal state** — `state` is declared `terminal: true` (see
   `GameServer.Lobbies.States`) and `state_changed_at` is older than the
   state's own `prune_after_minutes`, falling back to
   `RETENTION_ENDED_LOBBY_MINUTES`. A game therefore sets its own window per
   state: polyglot already declares `ended` with `prune_after_minutes: 5`.
2. **Abandoned** — non-terminal, no members, and `updated_at` older than
   `RETENTION_ABANDONED_LOBBY_HOURS`.
3. **Never** delete a lobby with a member who is online or was online within
   `RETENTION_LOBBY_PRESENCE_GRACE_MINUTES` (default 5). Polyglot's cleanup
   keeps paused matches alive on exactly this condition; a reaper keyed only
   on timestamps would delete games in progress during a reconnect.

Deleting a lobby already cascades its KV and snapshots via `delete_lobby/1`;
the reaper reuses it rather than issuing raw deletes, so hooks and broadcasts
still fire.

## users_tokens — expiry, not age

Token rows carry a context (`session`, `confirm`, `reset_password`,
`change:*`, `refresh`) with different validity windows already encoded in
`GameServer.Accounts.UserToken`. Pruning by a single age would either kill live
sessions or keep dead ones, so the sweep deletes **rows past their own
context's validity** — the same predicate the verify queries use, inverted.
No new env var; correctness, not policy.

## Configuration

New vars, all following the existing convention (read in
`config/host_runtime.exs`, `0` disables, documented in `.env.example`):

```
RETENTION_ENDED_LOBBY_MINUTES=15          # terminal-state fallback window
RETENTION_ABANDONED_LOBBY_HOURS=24        # empty, non-terminal lobbies
RETENTION_LOBBY_PRESENCE_GRACE_MINUTES=5  # never reap around a reconnect
RETENTION_INVITES_DAYS=30                 # resolved invites/join requests
RETENTION_MATCHMAKING_TICKETS_HOURS=24    # never-matched tickets
RETENTION_TOURNAMENTS_DAYS=0              # finished tournaments (opt-in)
RETENTION_LEDGER_DAYS=0                   # wallet + inventory ledgers (opt-in)
```

Defaults keep today's behavior for anything already retained. The two lobby
windows and invites default to a real window rather than "keep forever",
because unbounded growth there is a bug, not a policy choice; ledgers and
tournaments default to keep because deleting them loses an audit trail.

## Batching and safety

The sweep runs on a live database, so each class deletes in **bounded
batches** (`@batch 500`) in a loop until a pass deletes nothing, rather than
one unbounded `DELETE`. On SQLite a large delete holds the write lock long
enough to stall gameplay writes; on Postgres it bloats a single transaction.
Batching also makes the run interruptible — a restart mid-sweep just resumes
next cycle.

Every class stays **idempotent and independent**: one class raising must not
abort the rest, so each is wrapped and logged, and the result map reports per
class as it does today.

## Observability

- `prune_all/0` keeps returning `%{class => count}`; the log line stays.
- Emit `[:game_server, :retention, :pruned]` telemetry per class so the counts
  reach Prometheus/Grafana like other metrics.
- **Admin**: a Retention card on `/admin` (last run, per-class counts) and a
  "Run now" action on the System page, with API parity. Operators currently
  have no way to see whether retention is working.

## Deferred / rejected

- **Per-table cron schedules: rejected.** One 6h sweep with per-class windows
  is enough; separate schedules multiply configuration for no gain.
- **Soft deletes / archive tables: rejected.** Retention exists to bound
  storage; moving rows sideways does not.
- **Pruning `leaderboard_records`: rejected.** Bounded by users × leaderboards,
  and a missing record is a lost player achievement, not garbage.
- **A plugin-declared retention class: defer.** `lobby_states/0` already lets a
  game tune the lobby window; a general "prune my table" API needs its own
  design.

## Definition of done (CONTRIBUTING)

- [ ] Every gap above pruned, batched, and independently failure-isolated.
- [ ] Lobby reaper honours terminal `prune_after_minutes`, abandonment, and the
      presence grace; it goes through `delete_lobby/1` so cascades and hooks run.
- [ ] `users_tokens` pruned by per-context validity, with a test per context.
- [ ] New `RETENTION_*` vars in `config/host_runtime.exs` + `.env.example`,
      `0` disabling each.
- [ ] Telemetry event per class; admin card + "Run now" + API parity + render test.
- [ ] Docs page updated (Deployment/Operations), CHANGELOG, i18n.
- [ ] Tests both adapters: each class prunes what it should and **nothing else**;
      a lobby with an online member survives; batching loops past one batch.
- [ ] Polyglot's `lobby_cleanup.ex` reduced to what core cannot express, with
      its tests updated to match.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green.
