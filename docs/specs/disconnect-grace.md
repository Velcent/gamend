# Disconnect grace and state-aware reaping

Goal: core knows when a player has been gone long enough to matter, tells the
game once, and reaps a lobby on a schedule that depends on what the lobby was
doing — so no game has to run its own cleanup loop.

Two halves of one problem: **when is a player really gone**, and **when is a
lobby really dead**.

## Why core

`after_user_offline/1` fires the instant a socket closes. That is not the same
question a game needs answered — *"is this player coming back?"* — so every game
schedules its own delay and answers it privately.

Polyglot answers it twice, both times in ways core forbids elsewhere:

- `user_offline.ex` — `Task.start` + `Process.sleep(15 min)` + a
  `:persistent_term` dedupe key, to disband a party whose members all went
  offline. Unsupervised, lost on restart and on deploy, and its own
  `PLAN_TIMERS.MD` (in the `gamend_polyglot` repo) lists it as "keep: no
  in current form".
- `lobby_cleanup.ex` — 318 lines running a recursive `Task.start` loop every two
  minutes with three different max-ages: a paused game kept while any member is
  online and deleted 15 minutes after all are offline, an active game reaped
  after 5 minutes of silence, an ended one after 60 seconds. Also unsupervised.

Core already promises half of the second half: `Hooks.Declarations` documents
that a declared lobby state carries `%{description:, terminal:, prune_after_minutes:}`
— and **nothing reads `prune_after_minutes` or `terminal`**. Retention has one
knob, `RETENTION_ABANDONED_LOBBY_MINUTES`, applied to every lobby regardless of
state. The declaration surface exists; the behaviour behind it does not.

## Half 1 — grace

When a user's last socket closes, core already records `is_online` and
`last_seen_at`. Add one durable timer:

- On disconnect, enqueue an Oban job at `now + PRESENCE_GRACE_SECONDS`
  (default 120), unique per user so reconnect churn does not pile up jobs.
- On reconnect, cancel it (or let it run and no-op — the job re-checks
  `is_online` before acting, so cancellation is an optimization, not a
  correctness requirement).
- If the user is still offline when it runs, fire **`after_user_absent(user)`**
  and apply core's own absence handling.

`after_user_absent/1` is the hook games actually wanted: *this player is not
coming back right now*. Pause the match, substitute a bot, release their
matchmaking ticket, disband the party. `after_user_offline/1` keeps its current
meaning (the socket closed — useful for presence UI) and is unchanged.

Core's own absence handling, all opt-in via config, all defaulting to today's
behaviour:

| Setting | Default | Effect when the grace expires |
| --- | --- | --- |
| `PRESENCE_GRACE_SECONDS` | 120 | when `after_user_absent` fires |
| `ABSENT_LEAVE_PARTY` | false | remove the user from their party |
| `ABSENT_DISBAND_EMPTY_PARTY_MINUTES` | 15 | disband a party whose members are all absent |
| `ABSENT_CANCEL_MATCHMAKING` | true | cancel their queued ticket (today: 5-minute prune) |
| `ABSENT_LEAVE_LOBBY` | false | clear `users.lobby_id` |

`ABSENT_LEAVE_LOBBY` defaults **false** deliberately: disconnecting must not
mean forfeiting a match, and the abandoned-lobby reaper below already handles
the case where nobody comes back. The party disband is the one polyglot needed,
now durable and supervised.

## Half 2 — state-aware reaping

Make `prune_after_minutes` real, and give core's own states sensible values:

```elixir
# GameServer.Lobbies.States — core defaults
"created"  => %{prune_after_minutes: 30,  terminal: false}
"starting" => %{prune_after_minutes: 15,  terminal: false}
"playing"  => %{prune_after_minutes: 120, terminal: false}
"ended"    => %{prune_after_minutes: 5,   terminal: true}
```

A game would override any of them through a per-state declaration. (The
`lobby_states/0` callback this spec originally piggybacked on has since been
removed, so this needs its own callback — or simpler, a pair of plain
`lobby_prune_minutes/1`-style hooks — when this spec is built.)

Retention's `prune_lobbies/0` gains one rule: use the lobby's state's
`prune_after_minutes` in place of the global `RETENTION_ABANDONED_LOBBY_MINUTES`
when the state declares one. Everything else about the sweep is unchanged, and
the two properties that make it safe stay exactly as they are:

- **Silence, not emptiness.** A lobby is reaped only when no member is online
  *and* none has been seen inside the window *and* the lobby row has not been
  touched. Disconnecting does not clear `users.lobby_id`, so "no members" is
  never the signal.
- **Being over is not a reason to delete** — except that a `terminal: true`
  state now says the game itself considers it over, which is a stronger signal
  than silence and earns the short window.

`terminal` gets a second use, free: `before_lobby_state_change` can reject a
transition *out of* a terminal state, so `ended → playing` stops being legal by
accident. That is the one piece of state-machine semantics core can own without
knowing anything about the game.

The global `RETENTION_ABANDONED_LOBBY_MINUTES` remains the default for states
that declare nothing, so an existing deployment sees no change until it declares
something.

## Interaction with lobby sessions

A [lobby session](lobby-session.md) stops on lobby delete, so reaping a lobby
tears down its session. The reverse is not true — a session idling out does not
mean the lobby is dead, since state lives in the database. Retention is the only
thing that deletes lobbies, before and after this spec.

## What core still does not do

- **No auto-kick, no forfeit, no rating penalty.** Core records absence; the
  game decides what it costs. Same division as ready checks (core records who
  stalled, the host decides) and lobby states (core stores the word, the game
  gives it meaning).
- **No reconnect token, no session resume.** Reconnecting is already just
  authenticating again; the grace window is about *state*, not identity.
- **No presence heartbeat protocol.** `is_online` + `last_seen_at` and socket
  lifecycle are what core has; this spec adds a delay on top, not a new
  transport-level mechanism.

## Alternatives considered

- **A supervised sweeper GenServer scanning for absent users** instead of a job
  per disconnect. Simpler in one way (no job churn), worse in another: the
  grace becomes a poll interval, so a 120 s grace fires anywhere between 120 s
  and 120 s + interval, and every game that wants a precise pause point is back
  to guessing. `Accounts.StalePresenceSweeper` already exists as the backstop
  for jobs that were lost, which is the right division: precise jobs, plus a
  sweep that catches what fell through.
- **Firing `after_user_absent` from `StalePresenceSweeper` only.** Same
  imprecision, and the sweeper's job is fixing stale `is_online` flags after a
  node dies — a different concern that should not grow game semantics.
- **Per-lobby grace instead of per-user.** A player is in at most one lobby, so
  per-user is the same thing with fewer rows and it also covers party and
  matchmaking, which have no lobby.
- **Letting games keep their own loops.** They do today, unsupervised, and both
  polyglot instances are on its own removal list.

## Definition of done (CONTRIBUTING)

- [ ] Disconnect enqueues a unique Oban job at the grace deadline; reconnect
      cancels it; the job re-checks `is_online` and no-ops if the user returned.
- [ ] `after_user_absent/1` hook in all six places, RPC-blocked, SDK-mirrored;
      `after_user_offline/1` unchanged in meaning and timing.
- [ ] Absence settings applied per the table, all defaulting to today's
      behaviour except matchmaking cancellation, which replaces the 5-minute
      prune and is called out in the CHANGELOG.
- [ ] `Lobbies.States` core defaults carry `prune_after_minutes` and `terminal`;
      a plugin callback overrides them (see amendment above — `lobby_states/0`
      no longer exists); the admin runtime page shows the effective values.
- [ ] Retention uses the per-state window, falls back to
      `RETENTION_ABANDONED_LOBBY_MINUTES`, and keeps the silence rule intact — a
      lobby with any member seen inside the window is never reaped, whatever its
      state (test).
- [ ] `before_lobby_state_change` rejects transitions out of a `terminal: true`
      state.
- [ ] Env vars in `.env.example`, declared for the runtime page; `Limits` entries
      where they are caps.
- [ ] Tests on both adapters: reconnect inside the grace fires nothing;
      staying away fires exactly once; a restart between disconnect and deadline
      still fires (durability); per-state reaping picks the right window; an
      `ended` lobby with an online member is not reaped early.
- [ ] Admin: presence card shows users inside the grace window; lobby list shows
      each lobby's effective prune window; API parity.
- [ ] Docs (Lobbies, Parties, Retention pages), `api_spec.ex`, CHANGELOG, i18n.
- [ ] Polyglot deletes `lobby_cleanup.ex` and the party-disband task in favour
      of declarations plus `after_user_absent/1` (tracked in that repo).
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin warning-free.
