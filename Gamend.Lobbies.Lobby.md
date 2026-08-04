# `Gamend.Lobbies.Lobby`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lobbies/lobby.ex#L1)

Ecto schema for the `lobbies` table and changeset helpers.

A lobby represents a game room with basic settings (title, host, capacity,
visibility, lock/password and arbitrary metadata).

# `t`

```elixir
@type t() :: %Gamend.Lobbies.Lobby{
  __meta__: term(),
  host: term(),
  host_id: term(),
  hostless: term(),
  id: term(),
  inserted_at: term(),
  is_hidden: term(),
  is_locked: term(),
  max_users: term(),
  memberships: term(),
  metadata: term(),
  password_hash: term(),
  slowdown: term(),
  state: term(),
  state_changed_at: term(),
  title: term(),
  updated_at: term(),
  users: term(),
  webrtc_enabled: term(),
  webrtc_host_id: term(),
  webrtc_late_join: term(),
  webrtc_reconnect_timeout_ms: term(),
  webrtc_topology: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
