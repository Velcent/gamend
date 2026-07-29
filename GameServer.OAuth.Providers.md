# `GameServer.OAuth.Providers`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/oauth/providers.ex#L1)

Credentials and availability for the social sign-in providers.

A provider is live when its credentials are set and its `<provider>_enabled`
setting has not been switched off. `enabled/0` drives everything that varies
by provider — the sign-in buttons, the `/auth/:provider` routes, and the
`GET /api/v1/auth/providers` listing — so they can never disagree.

The id and secret are declared as a pair, so half-configuring one is a
warning rather than a silent failure at the first login attempt.

# `all`

```elixir
@spec all() :: [atom()]
```

Every provider this server knows, in display order.

# `configured?`

```elixir
@spec configured?(atom()) :: boolean()
```

Whether `provider` has credentials set.

# `enabled`

```elixir
@spec enabled() :: [atom()]
```

The providers a player may currently sign in with.

# `enabled?`

```elixir
@spec enabled?(atom()) :: boolean()
```

Whether `provider` is configured and switched on.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
