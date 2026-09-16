# `Gamend.Accounts.Stats`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/stats.ex#L1)

Counts over the user table for the admin dashboard and the public stats page.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `count_admins`

```elixir
@spec count_admins() :: non_neg_integer()
```

How many accounts hold the admin flag.

Used to refuse the write that would take that number to zero: nothing else can
grant `is_admin`, so an installation that reaches zero admins cannot be
administered again.

# `count_unactivated_users`

```elixir
@spec count_unactivated_users() :: non_neg_integer()
```

Count users who are not yet activated (is_activated == false).

# `count_users`

```elixir
@spec count_users() :: non_neg_integer()
```

Returns the total number of users.

# `count_users_in_lobbies`

```elixir
@spec count_users_in_lobbies() :: non_neg_integer()
```

Count users currently seated in a lobby (`users.lobby_id`, indexed).

# `count_users_in_parties`

```elixir
@spec count_users_in_parties() :: non_neg_integer()
```

Count users currently in a party (`users.party_id`, indexed).

# `count_users_online`

```elixir
@spec count_users_online() :: non_neg_integer()
```

Count users currently marked as online.

# `count_users_with_password`

```elixir
@spec count_users_with_password() :: non_neg_integer()
```

Count users with a password set (hashed_password not nil/empty).

# `count_users_with_provider`

```elixir
@spec count_users_with_provider(atom()) :: non_neg_integer()
```

Count users with non-empty provider id for a given provider field (e.g. :google_id)

# `list_admin_ids`

```elixir
@spec list_admin_ids() :: [Ecto.UUID.t()]
```

Ids of every admin user.

Used to fan a moderation alert out to whoever can act on it. Not cached: the
callers are rare (a chat report arriving), and a stale list would silently
skip a newly promoted moderator.

# `player_stats`

```elixir
@spec player_stats() :: %{
  players_online: non_neg_integer(),
  players_total: non_neg_integer(),
  players_offline: non_neg_integer(),
  players_in_lobbies: non_neg_integer(),
  players_in_parties: non_neg_integer()
}
```

Aggregate player counts for the public stats endpoint.

Every field is derived, never a counter: a counter would put a write on the
login path (SQLite has one writer) and would drift from the bulk updates in
`touch_users/1` and `StalePresenceSweeper`. `players_online` rides the
partial index over online rows, so it scans the smallest set; the unfiltered
`players_total` cannot use an index at all, which is what the cache is for.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
