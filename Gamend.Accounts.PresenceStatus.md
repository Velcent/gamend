# `Gamend.Accounts.PresenceStatus`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/presence_status.ex#L1)

How recently a user was seen, as the three states the UI actually draws.

Distinct from `Gamend.Presence`, which tracks live socket membership across
the cluster. This is the durable, per-user view derived from `is_online` and
`last_seen_at` — the thing a friends list or a chat sidebar wants when the
user is not connected to *this* node at all.

The rule already existed twice, in two shapes: `Gamend.Parties` kept a private
`@online_grace_seconds` with a boolean active/not check, and the Godot client
kept its own `RECENT_THRESHOLD_SECONDS` with a three-state version. They
happened to agree on 300 seconds, which is exactly the kind of agreement that
quietly stops being true. This module is the authority; clients may mirror the
constant, but the server decides it.

`:recent` is the state the web has never drawn — every surface had a boolean
`online`, so someone who closed the tab a minute ago looked identical to
someone who has not played in a week.

# `t`

```elixir
@type t() :: :online | :recent | :offline
```

Online now, seen within the grace window, or neither.

# `active?`

```elixir
@spec active?(Gamend.Accounts.User.t() | map() | nil) :: boolean()
```

Whether the user counts as present at all — `:online` or `:recent`.

The boolean `Gamend.Parties` needs when deciding whether a member has gone
quiet, defined in terms of `status/1` so the two cannot diverge.

# `recent_threshold_seconds`

```elixir
@spec recent_threshold_seconds() :: pos_integer()
```

Seconds after `last_seen_at` during which a signed-off user still counts as
`:recent`. Authoritative — mirror it in clients, do not redefine it.

# `status`

```elixir
@spec status(Gamend.Accounts.User.t() | map() | nil) :: t()
```

Presence state for a user.

Accepts a `User`, or any map carrying `is_online`/`last_seen_at` (a serialized
payload, say) so a caller does not have to reload the struct just to draw a
dot. Anything else is `:offline` — an unknown user is not an online one.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
