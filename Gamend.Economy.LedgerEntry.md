# `Gamend.Economy.LedgerEntry`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/economy/ledger_entry.ex#L1)

Append-only record of a single wallet change (grant, spend, transfer, admin
adjustment). One row per balance mutation, keeping an auditable history.

# `t`

```elixir
@type t() :: %Gamend.Economy.LedgerEntry{
  __meta__: term(),
  balance_after: term(),
  currency: term(),
  delta: term(),
  id: term(),
  idempotency_key: term(),
  inserted_at: term(),
  metadata: term(),
  reason: term(),
  user: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
