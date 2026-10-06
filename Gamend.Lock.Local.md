# `Gamend.Lock.Local`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lock/local.ex#L1)

Reentrant keyed mutex, first come first served: the non-Postgres half of
`Gamend.Lock.serialize/3`, and the node-local line in front of the Postgres
advisory lock.

Callers wait in `Gamend.Lock.Queue`, in the order they asked, and the key
passes to the next one when the holder finishes or dies. It was a bare
`:global.trans`, whose waiters retry after a random sleep that doubles up to
8 s: with fifty callers on one key the lock sat free while they slept, and
the last of them waited seconds for a section that takes milliseconds.

`trans/2` also takes the `:global` lock, so the section stays exclusive across
connected nodes; only the head of each node's line asks for it, so on a single
node it never waits there. `:global` shares a lock between holders with the
same *requester*, so the resource goes in the resource slot and `self()` in
the requester slot.

Reentrant within a process: the matchmaking sweep takes a lock and then
creates a match, which takes one again. Before `Gamend.Lock.Queue` is running
(it starts with the host's supervision tree) both fall back to `:global`.

# `in_turn`

```elixir
@spec in_turn(term(), (-&gt; result)) :: result when result: term()
```

Runs `fun` after this node's earlier callers of `key`, holding no database
lock: for an optimistic read-modify-write (read, ask a `before_*` hook with
no lock held, then write under `Gamend.Lock.serialize/3` only if the row is
unchanged). Without it, concurrent callers read together, and each round
only one write lands while the rest find the row changed and read again in
lockstep, so a burst of ten exhausts a few attempts. In line, each reads what
the one before it wrote; the compare still catches other writers and nodes.

Inside a transaction it runs `fun` at once: waiting in a line while holding
the write lock can deadlock against whoever is first in it (see
`Gamend.Lock.serialize/3`).

# `trans`

```elixir
@spec trans(term(), (-&gt; result)) :: result when result: term()
```

Runs `fun` holding the lock for `key`. Blocks; reentrant within a process.

# `trans_on_node`

```elixir
@spec trans_on_node(term(), (-&gt; result)) :: result when result: term()
```

As `trans/2`, on this node only. On Postgres the advisory lock is the
cluster-wide one; this queues a node's own callers in the BEAM, where waiting
is free, instead of each holding a pooled connection blocked on the database.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
