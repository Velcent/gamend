# `GameServer.Inventory.LedgerEntry`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/inventory/ledger_entry.ex#L1)

Append-only record of a single item-stack change (grant, consume, admin
adjustment) — the inventory counterpart of `GameServer.Economy.LedgerEntry`.
Carries the `idempotency_key` that makes item grants safe to retry.

# `t`

```elixir
@type t() :: %GameServer.Inventory.LedgerEntry{
  __meta__: term(),
  delta: term(),
  id: term(),
  idempotency_key: term(),
  inserted_at: term(),
  item: term(),
  metadata: term(),
  quantity_after: term(),
  reason: term(),
  user: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
