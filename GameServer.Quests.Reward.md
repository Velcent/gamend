# `GameServer.Quests.Reward`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/quests/reward.ex#L1)

One reward entry on a quest definition: `amount` of a currency
(via `GameServer.Economy.grant/4`) or an item
(via `GameServer.Inventory.grant_item/4`).

# `t`

```elixir
@type t() :: %GameServer.Quests.Reward{amount: term(), code: term(), type: term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
