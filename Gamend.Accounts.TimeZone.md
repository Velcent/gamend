# `Gamend.Accounts.TimeZone`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/time_zone.ex#L1)

A user's time zone, for "their day" and "their evening": an IANA name
(`"Europe/Bucharest"`) kept in their private preferences
(`Gamend.Accounts.Preferences`), taken from the browser
(`Intl.DateTimeFormat().resolvedOptions().timeZone`, sent on connect) or
chosen in settings. Unknown or unset, everything falls back to UTC.

The `tz` database is passed to `DateTime.shift_zone/3` explicitly, so a
host needs no global `:time_zone_database` config.

# `day_start`

```elixir
@spec day_start(Gamend.Accounts.User.t() | String.t() | nil, Date.t()) :: DateTime.t()
```

The moment `date` begins for a user or a zone, as a UTC DateTime (UTC
midnight when the zone is unknown). Where midnight does not exist (a clock
change at 00:00), the first moment after it.

# `local`

```elixir
@spec local(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) :: DateTime.t()
```

`utc` (default now) in a user's or a zone's local time; UTC when the zone
is unknown.

# `local_date`

```elixir
@spec local_date(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) ::
  Date.t()
```

The user's local date (UTC's when their zone is unknown).

# `local_hour`

```elixir
@spec local_hour(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) :: 0..23
```

The hour (0-23) it is for the user now.

# `of`

```elixir
@spec of(Gamend.Accounts.User.t() | nil) :: String.t() | nil
```

A user's time zone, or nil when unknown.

# `put`

```elixir
@spec put(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid_time_zone | term()}
```

Save a user's time zone; an unknown name is refused, the same one is a no-op.

# `valid?`

```elixir
@spec valid?(term()) :: boolean()
```

Whether `name` is a time zone the database knows.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
