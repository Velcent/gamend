# `Gamend.Presence`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/presence.ex#L1)

Cluster-wide tracking of who is connected where.

Backed by `Phoenix.Presence`, so entries are tied to process liveness and
replicated between nodes by CRDT: a node that dies takes its entries with it,
with no sweeper to notice. That is the property node-local ETS and database
flags both lack.

Used for signaling room membership and lobby spectators. Not for anything
queried in SQL — presence lives in memory and cannot be joined against a
table — and not for anything durable, since a full cluster restart empties it.

During a netsplit each side sees only its own members until they heal.

# `child_spec`

# `fetch`

# `fetchers_pids`

# `get_by_key`

# `last_socket?`

```elixir
@spec last_socket?(Ecto.UUID.t()) :: boolean()
```

Whether the calling process holds this user's only tracked socket.

Cluster-wide, unlike the per-node registry count it replaces.

# `list`

# `track`

# `track`

# `untrack`

# `untrack`

# `update`

# `update`

# `users_topic`

```elixir
@spec users_topic() :: String.t()
```

Topic every connected user is tracked on.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
