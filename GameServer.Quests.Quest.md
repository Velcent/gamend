# `GameServer.Quests.Quest`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/quests/quest.ex#L1)

Ecto schema for the `quests` table.

Three independent dimensions, so any combination is expressible:

- **`reset`** — when progress starts over: `"never"` (permanent, e.g. an
  achievement), `"daily"`, `"weekly"`, `"monthly"`, or `"interval"` with
  `reset_interval_days` (biweekly = 14, or any cadence).
- **`starts_at`/`ends_at`** — an availability window ("event" quests). Works
  with any reset, so a daily can run only during a seasonal window.
- **`prerequisite_quest_key`** — must be completed first ("chains"). Works
  with any reset, so dailies and events can chain too.

## Fields

- `key` — unique slug (e.g. "daily_win_3"); progress rows reference it
- `category` — free-form label for grouping/filtering in your UI
  ("achievement", "story", "seasonal", …); no engine behavior
- `objectives` — list of `GameServer.Quests.Objective` (event/target/params)
- `rewards` — list of `GameServer.Quests.Reward`, paid exactly-once
- `auto_claim` — grant rewards on completion without a claim step
- `hidden` — details withheld until earned (a teaser)
- `active` — inactive quests never advance and are not listed

# `t`

```elixir
@type t() :: %GameServer.Quests.Quest{
  __meta__: term(),
  active: term(),
  auto_claim: term(),
  category: term(),
  description: term(),
  ends_at: term(),
  hidden: term(),
  icon_url: term(),
  id: term(),
  inserted_at: term(),
  key: term(),
  metadata: term(),
  objectives: term(),
  prerequisite_quest_key: term(),
  progress: term(),
  reset: term(),
  reset_interval_days: term(),
  rewards: term(),
  sort_order: term(),
  starts_at: term(),
  title: term(),
  updated_at: term()
}
```

# `resets`

The valid reset cycles.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
