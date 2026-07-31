# `Gamend.Groups.GroupInvite`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/group_invite.ex#L1)

Ecto schema for the `group_invites` table.

Stores pending, accepted, declined, and cancelled invitations for **hidden**
groups. Unlike the previous approach (which stored invites as notifications),
invite records are independent of the notification system — deleting
notifications does not affect pending invites.

## Statuses

- `"pending"`   – waiting for the recipient to decide
- `"accepted"`  – recipient joined the group
- `"declined"`  – recipient declined the invite
- `"cancelled"` – sender cancelled the invite

# `t`

```elixir
@type t() :: %Gamend.Groups.GroupInvite{
  __meta__: term(),
  group: term(),
  group_id: term(),
  id: term(),
  inserted_at: term(),
  recipient: term(),
  recipient_id: term(),
  sender: term(),
  sender_id: term(),
  status: term(),
  updated_at: term()
}
```

# `changeset`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
