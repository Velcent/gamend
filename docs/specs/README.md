# Design specs

Per-item design specs for the planned phases in [../../ROADMAP.md](../../ROADMAP.md).
Each follows the Phase 0 house format: goal, why, concrete architecture grounded
in the existing codebase, and the full CONTRIBUTING checklist it must satisfy.

**A spec here is a proposal, not a work order.** It is deleted once resolved —
shipped or rejected — with its outcome recorded below. Only unbuilt work keeps a
file.

## Conventions

Not a plan; a living reference.

- [api-conventions.md](api-conventions.md) — **API conventions.** The
  vocabulary and shapes every schema, serializer and route follows —
  identifiers, names, time, lifecycle, the never-null policy, response shapes,
  paths. Six rules are enforced by `mix gamend.api.lint` in precommit and CI.

## Open

- [chat-moderation.md](chat-moderation.md) — **Chat moderation.** Word filter +
  report queue + mute, enforced in the existing `before_chat_message` pipeline.
- [cloud-saves.md](cloud-saves.md) — **Cloud saves.** Versioned save-slots on
  object storage with lock-free optimistic conflict detection.
- [skill-matchmaking.md](skill-matchmaking.md) — **Skill matchmaking.** Rating +
  wait-widening skill bands in the existing pure matcher, with the override hook
  intact.
- [webhooks-remote-config.md](webhooks-remote-config.md) — **Webhooks + remote
  config.** Signed, retried outbound webhooks on the Oban `webhooks` queue;
  client-read-only live remote config.
- [event-tracking.md](event-tracking.md) — **Event-tracking API.** Batched,
  enriched, auto-pruned `events` capture — the base a later ClickHouse/PostHog
  sink swaps into.
- [push-godot-client.md](push-godot-client.md) — **Push: Godot client.** The
  client half — Android (FCM plugin) then iOS (native APNs plugin) behind one
  `GamendPush.gd` API. The server half shipped; this did not.
- [resource-regen.md](resource-regen.md) — **Regenerating currencies.** Lives,
  energy and stamina as a declared `%{amount, interval, cap}` on a wallet,
  folded lazily from a timestamp with no timers.
- [kv-prefix-streaming.md](kv-prefix-streaming.md) — **KV prefix queries and
  streaming.** Indexed left-anchored prefixes and a keyset cursor, replacing the
  substring filter and offset paging plugins loop over today.
- [discord-notifications.md](discord-notifications.md) — **Discord
  notifications.** One env var, Oban-delivered, rate-limit aware and redacted by
  construction — the concrete slice of the parked webhooks spec.

## Resolved — shipped

Spec deleted; the code, its moduledocs and the CHANGELOG are the record.

| | |
|---|---|
| Settings | one declared config surface, env names derived from the declaration |
| Retention | sweep over every unbounded table, `RETENTION_*` windows |
| Economy / inventory | currencies, atomic wallet, idempotent ledger |
| Quests / progression | one event-driven engine; achievements folded in |
| Push (server) | `push_tokens` + fan-out on the Oban `push` queue, FCM + APNs |
| Ready checks | `Gamend.ReadyChecks` |
| Lobby state | server-owned lifecycle column with legal transitions |
| i18n | one theme config plus a `theme` PO domain; content translated at render |
| Locking on SQLite | `Lock.serialize/3` per-key on both adapters, via a `:global` mutex |

## Resolved — rejected

**Read these before proposing anything similar.** Each was fully built, then
removed, and the reason is the point.

- **Lobby session** (one writer process per lobby). Its "why core" premise was
  false: plugins are OTP applications and supervise their own trees —
  `gamend_polyglot` already does exactly this with `BoatGamend`.
  `Lock.serialize/3` covers the lost-update problem it opened with. Before
  reviving: check that a plugin genuinely *cannot* do it, and that more than one
  game has written the duplicate.
- **Server time / state revision / action idempotency.** The transport already
  handles it — TCP de-duplicates within a connection, and Phoenix does not
  resend a push it has already sent. Operations where a double-apply costs money
  already carry durable idempotency keys in `Economy` and `Quests`. No client
  ever sent `seq`. Only `GET /api/v1/time` survives. Written from a *plan
  document* polyglot never implemented rather than from code it had already
  written — that was the tell.
- **Disconnect grace** (`after_user_absent/1` on a durable timer). Half shipped:
  the abandoned-party sweep in `Gamend.Retention` is the part that mattered.
  The grace timer was removed — it generalised "polyglot delays a party
  disband" into "games need a delayed presence signal", but the delay belonged
  to the *disband*. The one candidate game pauses on disconnect and wants that
  immediately.

## Not specced (parked by the roadmap)

- **ClickHouse / PostHog analytics** ("Later") — gated behind volume; the
  event-tracking schema is kept portable so it's a sink swap. No spec until the
  capture layer proves it's needed.
- **Unity / Unreal SDKs** ("Defer") — the realtime layer is hand-written per SDK
  (the real cost); revisit on demonstrated demand.
