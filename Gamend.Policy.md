# `Gamend.Policy`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/policy.ex#L1)

One question — "may this user do this to this thing?" — asked the same way
everywhere.

Gamend has four owners: a lobby's host, a lobby's pinned WebRTC host, a
group's admins and a party's leader. Each context decides its own rule and
keeps deciding it; this module does not own authority, it only routes to the
context that does:

    Policy.can?(user, :manage, lobby)   # -> Lobbies.can_manage_lobby?/2
    Policy.can?(user, :manage, group)   # -> Groups.can_manage_group?/2
    Policy.can?(user, :manage, party)   # -> Parties.can_manage_party?/2

A caller that holds a resource but does not know its type — an admin screen,
a hook, a serializer — can ask without a `case` per resource, and the answer
comes from the context that owns the rule rather than from a copy of it.

## Actions

  * `:view` — read the resource's details. Lobbies only; groups and parties
    have no hidden state to gate yet.
  * `:manage` — everything an owner does: edit, kick, moderate, and for a
    lobby move its `state`. Gamend does not split these, and this module
    will not invent a split it cannot enforce.

An unknown action or a resource with no rule is `false`, never an error: a
policy that raises turns a missing case into a 500 instead of a 403.

# `action`

```elixir
@type action() :: :view | :manage
```

# `resource`

```elixir
@type resource() ::
  Gamend.Lobbies.Lobby.t() | Gamend.Groups.Group.t() | Gamend.Parties.Party.t()
```

# `can?`

```elixir
@spec can?(Gamend.Accounts.User.t() | nil, action(), resource() | nil) :: boolean()
```

Whether `user` may perform `action` on `resource`.

`nil` for an anonymous caller. Only `:view` on a public lobby is ever true
for one.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
