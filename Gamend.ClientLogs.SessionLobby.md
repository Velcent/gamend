# `Gamend.ClientLogs.SessionLobby`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/client_logs/session_lobby.ex#L1)

A lobby a client session was in.

Written once per (session, lobby) pair with `on_conflict: :nothing`, so
repeated batches from the same run cost an ignored insert rather than a
read-modify-write that two nodes could race.

Keyed by `client_session_id` (the client-generated string) rather than by the
session row's id, so a batch can record its lobbies without first resolving
the row. See the migration for why this is a table and not an array column.

# `t`

```elixir
@type t() :: %Gamend.ClientLogs.SessionLobby{
  __meta__: term(),
  client_session_id: term(),
  id: term(),
  inserted_at: term(),
  lobby_id: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
