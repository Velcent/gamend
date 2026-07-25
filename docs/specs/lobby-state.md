# Lobby state — a server-owned lifecycle field

Design spec. Gives lobbies a `state` string that core owns, indexes and
broadcasts, but whose **vocabulary the game defines**.

Goal: one place to record "where is this lobby in its life", so core can hook,
filter and (later) reap on it — without core asserting game semantics it does
not own.

## Why

Polyglot already built this by hand in `metadata["game_state"]`
(`playing`/`ended`, absent = waiting), driving six files and a **362-line**
plugin GenServer, `lobby_cleanup.ex`, that reaps lobbies core never reclaims.

Four things core cannot do today:

1. **Reclaim lobbies.** `Retention` prunes chat, notifications, snapshots and
   push tokens — never `lobbies`. Core deletes a lobby only on specific events
   (party disband, failed matchmaking seat, admin action), so an abandoned
   lobby lives forever. A generic reaper needs a lifecycle signal; this is it.
2. **Trust it.** `metadata` is in the lobby changeset's castable fields, so a
   host can `PATCH /lobbies/:id` and rewrite `game_state` — `"ended"` to make a
   reaper bin a live match, `"playing"` to slip past gating. Worse, the guard
   in `update_lobby_by_host/3` is `host_id == host or lobby.hostless`, so in a
   **hostless** (matchmaking) lobby *any member* can do it. Today's state is
   client-owned by accident, and least protected exactly where it matters most.
3. **Hook it.** Nothing can react to "match started/ended" — snapshots infer
   run boundaries from min/max timestamps, and quests have no match lifecycle
   event to listen to.
4. **Ask when.** There is no "how long has it been finished?" — polyglot needs
   three different fudge windows keyed off raw lobby age to approximate it.

Explicitly **not** reasons (considered and rejected):

- *"`is_locked` is overloaded"* — it is not. `is_locked` means "no more
  joining"; matchmaking setting it when a match forms is correct usage.
- *"Listings can't express joinable"* — they can, via the existing `is_locked`
  and `is_hidden` filters.

(Adjacent bug, fix separately: `spectatable?/1` refuses locked lobbies, so
"no more joining" also blocks watching. Spectating is not joining.)

## The vocabulary belongs to the game

Core hardcoding `waiting → starting → playing → ended` would repeat the mistake
just undone in quests' `kind`: core ruling on semantics it does not own. Games
have drafts, countdowns, overtime, round-based loops back to a lobby.

So there is **no universal transition table**. Instead core reuses the
declaration mechanism it already has — `notification_types/0` is enforced the
same way (`Notifications.Types.known?/1` merges core's codes with
`Declarations.notification_types()` and rejects the undeclared):

```elixir
# in the plugin's hooks module
def lobby_states do
  %{
    "drafting" => %{description: "Picking teams"},
    "playing" => %{description: "Match running"},
    "post_game" => %{description: "Scoreboard", terminal: true, prune_after_minutes: 10}
  }
end
```

- `GameServer.Lobbies.States.known?/1` = core defaults ∪ declarations.
- Declare nothing and the core defaults apply — batteries included, no ceremony.
- `terminal` + `prune_after_minutes` are what a future generic reaper consumes;
  see "Retention" below.

Core ships a default vocabulary — `created`, `starting`, `playing`, `ended` —
as *documented strings*, not a machine. Any state may follow any other; a game
that needs ordering enforces it in `before_lobby_state_change`.

## What core sets itself

Core observes lobby creation, membership changes, matchmaking seating, host
change and deletion. It does **not** know when a match begins or ends — that is
game knowledge. So core sets exactly one state, once:

> `create_lobby/1` → `"created"`.

`"created"` rather than `"waiting"` because it is the only thing core can
truthfully assert: a matchmaking lobby is created already-seated and is not
waiting for anyone. Everything after is the game's to set.

## Data model

- `lobbies.state` — string, not null, default `"created"`. Index `[:state]`.
- `lobbies.state_changed_at` — `utc_datetime`, set on every change, so "how
  long has it been X?" is answerable without proxying lobby age.

Both are **excluded from the changeset's castable fields**, so no generic
`PATCH /lobbies/:id` can touch them. `state` is orthogonal to `is_locked`
(can others join) and `is_hidden` (is it listed) — none derived from another.

## Ownership: who may write it

The server owns the field; who may *request* a change depends on whether the
lobby has a host.

| Writer | Scope |
| --- | --- |
| **Core** | `create_lobby` → `"created"` |
| **The host** | `POST /lobbies/:id/state` — host-managed lobbies only |
| **The game, server-side** | `Lobbies.transition_state/3` from hooks/RPCs — the only path for hostless lobbies |
| **Admins** | force any state from the admin page/API |

**Host-managed lobbies: the host may set it.** The host already renames, locks,
resizes, kicks and can leave the lobby to die — `state` is no more powerful
than what they hold, and a "Start match" button is the normal shape of a
party/custom game. Forcing every such game to ship a plugin RPC just to press
Start would break the batteries-included promise.

**Hostless lobbies: server, plugin and admin only.** Nobody owns a matchmaking
match, so no player may declare it `playing` (forcing an early start) or
`ended` (dodging a loss). Player requests get `{:error, :not_host}`.

`transition_state/3` is idempotent — a same-state write is a no-op, so
at-least-once hook retries are safe.

## Hooks (all six places, per CONTRIBUTING §Hooks)

- `before_lobby_state_change(lobby, from, to)` — veto-only pipeline; where a
  game enforces its own ordering or minimum player count.
- `after_lobby_state_changed(lobby, from, to)` — observe: snapshot the run,
  report a quest event, notify.

Dispatched after commit via `defer/1`, never inside the lock.

## Web / realtime / admin

- `state` and `state_changed_at` in lobby payloads (REST + protobuf); `state`
  filter on `GET /lobbies`.
- `lobby_state_changed` on the lobby channel, registered in `RealtimeEvents`.
- `POST /lobbies/:id/state` — `403 not_host` for a non-host or **any** caller on
  a hostless lobby; `422` for an unknown state; veto errors passed through.
- Admin: state column + filter on `/admin/lobbies`, force-state action, API
  parity; declared states listed on the runtime page next to notification types.

## Retention (deferred to the Retention pass)

This spec deliberately stops at the signal. The generic reaper — delete
terminal-state lobbies after `prune_after_minutes`, and abandoned ones with no
members — lands with the broader "Retention handles all classes" work. Note for
that pass: polyglot keeps a paused match alive **while any member is online or
recently disconnected**, so the reaper must consider presence, not just
membership, or it will delete live games.

## Migration

Add both columns; backfill every existing lobby to `"created"` with
`state_changed_at = inserted_at`. Core cannot know a game's metadata keys, so
**games backfill their own**: polyglot maps `metadata["game_state"]` → `state`
once at plugin startup (the pattern its quest chain rebaseline already uses),
then drops the metadata key.

## Deferred / rejected

- **A universal transition table: rejected.** Declarations + the veto hook.
- **Per-game states in a core enum: rejected.** That is what declarations are.
- **`lobby_state_history` table: defer.** The after-hook plus lobby snapshots
  already give an audit trail.
- **Auto-`ended` on host disconnect: defer.** Host migration already exists;
  conflating the two needs its own design.

## Definition of done (CONTRIBUTING)

- [ ] Migration adds `state` + `state_changed_at` with an index; applies on
      SQLite **and** `DATABASE_ADAPTER=postgres`.
- [ ] Neither column is castable via `PATCH /lobbies/:id`; `create_lobby` sets
      `"created"`.
- [ ] `transition_state/3` validates against core ∪ declared states, is
      idempotent, broadcasts, and defers hooks post-commit.
- [ ] `lobby_states/0` declaration registered, merged, and shown on the admin
      runtime page.
- [ ] Hooks in all six places, RPC-blocked, SDK-mirrored.
- [ ] `POST /lobbies/:id/state` allows the host, rejects a non-host and **any**
      caller on a hostless lobby, and honours the veto.
- [ ] `state` filter + payload fields + `lobby_state_changed` registered.
- [ ] Admin column/filter/force-state + API parity + render test.
- [ ] Docs (Lobbies + Data Schema), `api_spec.ex`, CHANGELOG, i18n.
- [ ] Tests both adapters: unknown state rejected, declared state accepted,
      idempotent no-op, veto, host vs hostless authorization, and a booted run
      through `created → playing → ended`.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
