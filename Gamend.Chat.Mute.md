# `Gamend.Chat.Mute`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/mute.ex#L1)

Ecto schema for the `chat_mutes` table — a silenced chat sender.

`expires_at` is `nil` for a permanent mute; `scope_ref_id` is `nil` for a
`"global"` mute and required otherwise.

## Scopes

  * `"global"` — every chat type, including friend DMs. Admin/plugin only.
  * `"lobby"` / `"group"` / `"party"` — that room only. `scope_ref_id` is the
    lobby, group or party id, and the room's own authority (host, group admin,
    party leader) may set it.

# `t`

```elixir
@type t() :: %Gamend.Chat.Mute{
  __meta__: term(),
  expires_at: term(),
  id: term(),
  inserted_at: term(),
  muted_by: term(),
  muted_by_user: term(),
  reason: term(),
  scope: term(),
  scope_ref_id: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `scopes`

```elixir
@spec scopes() :: [String.t()]
```

The scopes a mute may have.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
