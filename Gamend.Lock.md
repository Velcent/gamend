# `Gamend.Lock`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lock.ex#L1)

Serialized execution using database-level advisory locks.

Wraps a function in a `Repo.transaction` with an advisory lock so that
only one process at a time can execute the critical section for a given
`(namespace, resource_id)` pair.

This is useful for game RPCs where multiple players may trigger the same
operation concurrently (e.g. guessing a word, claiming a reward) and the
logic involves read-modify-write on KV entries or lobby metadata.

## How it works

Serialized on **both** adapters, per key, by different mechanisms:

  * **PostgreSQL** — `pg_advisory_xact_lock` inside the transaction.
  * **SQLite** — `Gamend.Lock.Local`, a `:global` mutex taken *around* the
    transaction, since SQLite has no advisory locks and its single-writer rule
    covers neither a read-modify-write across statements nor a critical
    section that never touches the database.

`default_transaction_mode: :immediate` is a backstop for callers who forget
this function, not the mechanism — it does nothing for ETS or process state.

## Nesting

Take the lock at the outermost point. A `serialize/3` reached inside an open
transaction cannot take the mutex — the caller holds the write lock, so
waiting on a mutex whose holder wants that lock deadlocks — so it runs under
the outer transaction and relies on the outer lock.

## Prefer an atomic write

Prefer an atomic write where one exists: `Economy.debit/3` does
`balance = balance - x where balance >= x` in one statement, which needs no
lock at all.

## Multi-node safety

Both paths are cluster-wide: the Postgres lock lives in the shared database,
and `:global.trans` coordinates across connected nodes. A netsplit can produce
two holders on either path, which is why value operations must also be atomic.

## Namespace conventions

The `namespace` argument can be:

- A **predefined atom**: `:lobby` (1), `:group` (2), `:party` (3)
- An **arbitrary string**: hashed to a stable integer, e.g. `"word_guessed"`

The `resource_id` is typically the lobby, group, or user id that scopes
the lock.

## Examples

    # Serialize all "word_guessed" RPCs per lobby
    Gamend.Lock.serialize("word_guessed", lobby_id, fn ->
      {:ok, entry} = Gamend.KV.get("game_state", lobby_id: lobby_id)
      new_val = Map.update(entry.value, "guessed", [word], &[word | &1])
      Gamend.KV.put("game_state", new_val, %{}, lobby_id: lobby_id)
    end)

    # Using a predefined atom namespace
    Gamend.Lock.serialize(:lobby, lobby_id, fn ->
      # exclusive per-lobby operation
    end)

## Return value

Returns `{:ok, result}` where `result` is the return value of the function,
or `{:error, reason}` if the transaction rolls back.

# `serialize`

```elixir
@spec serialize(atom() | String.t(), String.t(), (-&gt; result)) ::
  {:ok, result} | {:error, term()}
when result: term()
```

Execute `fun` inside a transaction with an advisory lock on `(namespace, resource_id)`.

Only one process at a time can hold the lock for a given key pair. Other
callers block until the lock is released (on transaction commit/rollback).

Returns `{:ok, result}` on success or `{:error, reason}` on rollback.

## Parameters

- `namespace` — atom (`:lobby`, `:group`, `:party`) or any string
- `resource_id` — id of the specific resource (e.g. lobby id)
- `fun` — zero-arity function to execute while holding the lock

---

*Consult [api-reference.md](api-reference.md) for complete listing*
