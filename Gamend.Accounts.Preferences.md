# `Gamend.Accounts.Preferences`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/preferences.ex#L1)

A user's private settings (`users.preferences`): what only they see and
change — notification choices (`Gamend.Notifications.Preferences`), their
time zone (`Gamend.Accounts.TimeZone`) and the site language they last used
(`locale/1`, for email written to them).

Kept out of `metadata` on purpose: metadata is sent to friends, lobby and
party members (`User.serialize_brief/1`), and a user's time zone or email
choices are nobody else's business. Every user serializer lists its fields,
and this one is in none of them.

Writes are serialized per user (`Gamend.Lock`) and re-read the row, so two
settings changed at once cannot lose each other.

# `get`

```elixir
@spec get(Gamend.Accounts.User.t() | nil) :: map()
```

A user's preferences map (string keys), empty when none are set.

# `locale`

```elixir
@spec locale(Gamend.Accounts.User.t() | nil) :: String.t() | nil
```

The site language the user last read in (a locale code), or nil.

# `update`

```elixir
@spec update(Gamend.Accounts.User.t(), (map() -&gt; map())) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Change a user's preferences: `fun` gets the current map and returns the
new one. `{:ok, user}` with the saved user.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
