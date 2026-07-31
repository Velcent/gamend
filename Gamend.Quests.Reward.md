# `Gamend.Quests.Reward`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/reward.ex#L1)

One reward entry on a quest definition: `amount` of a currency
(via `Gamend.Economy.grant/4`) or an item
(via `Gamend.Inventory.grant_item/4`).

# `t`

```elixir
@type t() :: %Gamend.Quests.Reward{amount: term(), code: term(), type: term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
