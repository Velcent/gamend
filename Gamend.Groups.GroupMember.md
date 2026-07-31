# `Gamend.Groups.GroupMember`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/groups/group_member.ex#L1)

Ecto schema for the `group_members` join table.

Tracks which users belong to which groups and their role within the group.

## Roles

- `"admin"` – can kick members, rename group, change settings, approve
  join requests, promote/demote members
- `"member"` – regular participant

# `t`

```elixir
@type t() :: %Gamend.Groups.GroupMember{
  __meta__: term(),
  group: term(),
  group_id: term(),
  id: term(),
  inserted_at: term(),
  role: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
