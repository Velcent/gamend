# `GameServer.Quests`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/quests.ex#L1)

Event-driven quest/progression engine.

One engine, three independent dimensions: a **reset** cycle (never / daily /
weekly / monthly / every N days), an optional **window**
(`starts_at`/`ends_at`), and an optional **prerequisite**
(`prerequisite_quest_key`). Any combination works — a biweekly quest inside
a seasonal window that also requires an earlier quest is just those three
fields set. Rewards pay into `GameServer.Economy` / `GameServer.Inventory`
exactly once. `category` is a free-form label for your UI only.

## Reporting progress (server-side / hooks)

    Quests.report_event(user_id, "enemy_killed", 1, %{"map" => "desert"})

Every **active** quest with an objective on `"enemy_killed"` (whose `params`
all match the meta) advances; a quest completes when every objective meets
its target. There is deliberately **no public endpoint** for this — clients
cannot advance their own quests. Core wires common events; games call it
from their hooks for custom events.

## Claiming

    {:ok, %{progress: progress, rewards: rewards}} = Quests.claim(user_id, "daily_win_3")

Claiming is gated by an atomic `completed → claimed` status transition, so a
double-tap or a concurrent claim can't double-pay. Rewards are granted after
the transition with a per-entry idempotency key (`"quest:<progress_id>:<i>"`),
so a crashed or retried grant can't double-apply either; rows that claimed
but never finished granting are healed by `recover_pending_rewards/1`.
Quests with `auto_claim` grant immediately on completion (skipping the
`before_quest_claim` hook — there is no player request to veto).

## Resets

`period_key` is derived from **UTC time** by the quest's reset (daily →
`"2026-07-22"`, weekly → `"2026-W30"`, monthly → `"2026-07"`, interval →
`"I14-1436"`, never → `"static"`). A new period simply means a new progress
row on the next reported event — nothing needs to fire at midnight, and
state resolves correctly even if no job ever runs.

# `user_id`

```elixir
@type user_id() :: Ecto.UUID.t()
```

# `active_quests`

```elixir
@spec active_quests() :: [GameServer.Quests.Quest.t()]
```

All active quest definitions (cached — this backs event dispatch).

# `admin_claim`

```elixir
@spec admin_claim(user_id(), String.t()) ::
  {:ok, %{progress: GameServer.Quests.QuestProgress.t(), rewards: [map()]}}
  | {:error, term()}
```

Claim on a user's behalf, skipping the `before_quest_claim` veto (admin).

# `admin_complete`

```elixir
@spec admin_complete(user_id(), String.t()) ::
  {:ok, GameServer.Quests.QuestProgress.t()} | {:error, term()}
```

Force-complete a quest for a user (admin grant): every objective jumps to
its target and the normal completion side effects fire (hooks, auto-claim).

# `admin_reset`

```elixir
@spec admin_reset(user_id(), String.t()) ::
  {:ok, GameServer.Quests.QuestProgress.t() | :not_found} | {:error, term()}
```

Delete a user's current-period progress row for a quest (admin reset).

# `change_quest`

```elixir
@spec change_quest(GameServer.Quests.Quest.t(), map()) :: Ecto.Changeset.t()
```

Returns a changeset for tracking quest changes (used by forms).

# `claim`

```elixir
@spec claim(user_id(), String.t(), keyword()) ::
  {:ok, %{progress: GameServer.Quests.QuestProgress.t(), rewards: [map()]}}
  | {:error, term()}
```

Claim a completed quest's rewards for the current period.

Runs the `before_quest_claim` pipeline hook (veto), then transitions
`completed → claimed` atomically — only the winner grants rewards.

Returns `{:ok, %{progress: progress, rewards: rewards}}` or
`{:error, :quest_not_found | :not_completed | :already_claimed | term()}`.

# `claimable_count`

```elixir
@spec claimable_count(user_id()) :: non_neg_integer()
```

Number of completed-but-unclaimed quests for a user (badge count).

# `count_progress`

```elixir
@spec count_progress(keyword()) :: non_neg_integer()
```

Count progress rows (same filters as `list_progress/1`).

# `count_quests`

```elixir
@spec count_quests(keyword()) :: non_neg_integer()
```

Count quest definitions (same filters as `list_quests/1`).

# `count_user_completions`

```elixir
@spec count_user_completions(
  user_id(),
  keyword()
) :: non_neg_integer()
```

Count of a user's completed quests (same filters as `list_user_completions/2`).

# `count_user_quests`

```elixir
@spec count_user_quests(
  user_id(),
  keyword()
) :: non_neg_integer()
```

Count of quests visible to the user (same filters as `list_user_quests/2`).

# `create_quest`

```elixir
@spec create_quest(map()) :: {:ok, GameServer.Quests.Quest.t()} | {:error, term()}
```

Creates a quest definition. Capped by the `max_quests` limit.

# `dashboard_stats`

```elixir
@spec dashboard_stats() :: map()
```

Quest statistics for the admin dashboard.

# `delete_quest`

```elixir
@spec delete_quest(GameServer.Quests.Quest.t()) ::
  {:ok, GameServer.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a quest definition and all related progress.

# `funnel`

```elixir
@spec funnel(String.t()) :: %{required(String.t()) =&gt; non_neg_integer()}
```

Per-status progress counts for one quest (admin completion funnel).

# `get_progress`

```elixir
@spec get_progress(user_id(), String.t()) :: GameServer.Quests.QuestProgress.t() | nil
```

Get a user's progress row for a quest's current period.

# `get_quest`

```elixir
@spec get_quest(Ecto.UUID.t()) :: GameServer.Quests.Quest.t() | nil
```

Get a quest by ID.

# `get_quest_by_key`

```elixir
@spec get_quest_by_key(String.t()) :: GameServer.Quests.Quest.t() | nil
```

Get a quest by key.

# `list_progress`

```elixir
@spec list_progress(keyword()) :: [GameServer.Quests.QuestProgress.t()]
```

Lists progress rows (admin viewer).

## Options
- `:user_id` — exact UUID or username/display-name substring
- `:quest_key`, `:status`
- `:page` / `:page_size`

# `list_quests`

```elixir
@spec list_quests(keyword()) :: [GameServer.Quests.Quest.t()]
```

Lists quest definitions (admin view — no per-user state).

## Options
- `:category` — filter by category
- `:active` — filter by active flag
- `:search` — substring match on key/title
- `:page` / `:page_size`

# `list_user_completions`

```elixir
@spec list_user_completions(
  user_id(),
  keyword()
) :: [
  %{
    quest: GameServer.Quests.Quest.t(),
    progress: GameServer.Quests.QuestProgress.t()
  }
]
```

A user's completed quests, newest first — the public-profile view
("their achievements"). Hidden quests appear once earned.

## Options
- `:category` — filter by category (a profile typically wants `"achievement"`)
- `:page` / `:page_size`

# `list_user_quests`

```elixir
@spec list_user_quests(
  user_id(),
  keyword()
) :: [
  %{
    quest: GameServer.Quests.Quest.t(),
    progress: GameServer.Quests.QuestProgress.t() | nil,
    claimable: boolean()
  }
]
```

Lists quests as seen by one user: active definitions in-window with the
user's current-period progress and a claimable flag.

Hidden quests are listed but carry no details until earned (callers obscure
them). Chain quests only appear once their prerequisite is met.

## Options
- `:category` — filter by category
- `:status` — `"in_progress"` (not yet completed), `"claimable"`
  (completed, waiting to be claimed) or `"done"` (completed or claimed)
- `:page` / `:page_size`

# `period_key`

```elixir
@spec period_key(GameServer.Quests.Quest.t() | String.t(), DateTime.t()) :: String.t()
```

The reset bucket a quest is in at `now` (UTC).

`"static"` when it never resets, else the current day (`"2026-07-22"`),
ISO week (`"2026-W30"`), month (`"2026-07"`), or interval bucket
(`"I14-1436"` — the 1436th 14-day window since the epoch). Derived purely
from the clock, so a reset needs nothing to fire at midnight.

# `prerequisite_met?`

```elixir
@spec prerequisite_met?(user_id(), GameServer.Quests.Quest.t()) :: boolean()
```

True when the quest's prerequisite (if any) is completed by the user.

# `prune_old_periods`

```elixir
@spec prune_old_periods() :: non_neg_integer()
```

Deletes daily/weekly progress rows whose period ended more than
`max_quest_period_history` days ago (called from `GameServer.Retention`).

# `recover_pending_rewards`

```elixir
@spec recover_pending_rewards(keyword()) :: non_neg_integer()
```

Re-runs reward grants for rows that claimed but never finished granting
(e.g. the process died mid-grant). Safe to run anywhere, any time — the
per-entry idempotency keys dedupe. Pass `:user_id` to heal one user (done
lazily when they list their quests). Returns the number of rows retried.

# `report_event`

```elixir
@spec report_event(user_id(), String.t(), pos_integer(), map()) ::
  {:ok, [GameServer.Quests.QuestProgress.t()]}
```

Report a gameplay event for a user, advancing every matching active quest.

`meta` narrows objective matching: an objective with `params` only advances
when every param key/value is present in `meta`.

Returns `{:ok, progress_rows}` for the quests that advanced.

# `subscribe_quests`

```elixir
@spec subscribe_quests() :: :ok | {:error, term()}
```

Subscribe to global quest events (definition changes, completions).

# `update_quest`

```elixir
@spec update_quest(GameServer.Quests.Quest.t(), map()) ::
  {:ok, GameServer.Quests.Quest.t()} | {:error, Ecto.Changeset.t()}
```

Updates a quest definition.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
