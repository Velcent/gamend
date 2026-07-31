# `Gamend.OAuthSessions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/oauth_sessions.ex#L1)

Helpers for creating and retrieving short-lived OAuth sessions.

# `create_session`

```elixir
@spec create_session(String.t(), map()) ::
  {:ok, Gamend.OAuthSession.t()} | {:error, Ecto.Changeset.t()}
```

# `get_session`

```elixir
@spec get_session(String.t()) :: Gamend.OAuthSession.t() | nil
```

# `update_session`

```elixir
@spec update_session(String.t(), map()) ::
  {:ok, Gamend.OAuthSession.t()} | {:error, Ecto.Changeset.t()} | :not_found
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
