# `Gamend.Ledger`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/ledger.ex#L1)

The mechanics both ledgered balances share: `Gamend.Economy` (currency in a
wallet) and `Gamend.Inventory` (quantity of an item).

The two contexts are near-isomorphic — the same `run_change`, `apply_delta`,
`record_ledger`, `idem_applied?` set, differing only in whether the noun is a
currency or an item. Most of that difference is real: a wallet and an item
stack are different tables with different constraints, and folding them into
one generic ledger would trade a little duplication for a lot of indirection.

What is *not* different is the transaction shape around them, which is what
lives here:

  * apply the delta and write the ledger row in one transaction;
  * treat a duplicate `idempotency_key` as a replay rather than an error,
    because losing that race means the other request already applied it —
    so the caller should be told the resulting balance, not a failure;
  * roll back anything else.

Getting that wrong is a double-spend or a phantom grant, so it is worth
having exactly one copy of it.

# `change`

```elixir
@spec change(
  (-&gt; {:ok, integer()} | {:error, term()}),
  (integer() -&gt; term()),
  (-&gt; integer())
) ::
  {:ok, integer()} | {:error, term()}
```

Runs `apply_fun` and `record_fun` in one transaction and normalises the
result.

`apply_fun` returns `{:ok, new_total}` or `{:error, reason}`. `record_fun`
receives the new total and writes the ledger row; it is expected to
`Repo.rollback(:idempotent_replay)` when the idempotency key already exists.

`replay_fun` is called only on that replay, to read back the total the
winning request produced.

# `rollback_insert_error`

```elixir
@spec rollback_insert_error(Ecto.Changeset.t(), atom()) :: no_return()
```

Classifies a failed ledger insert: a duplicate idempotency key is a replay,
anything else is a genuine error. Rolls back either way.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
