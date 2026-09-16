# `Gamend.Accounts.Sessions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/sessions.ex#L1)

Signing in and staying signed in: session and magic-link tokens, the emails
that carry them, and listing or revoking a user's sessions.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name. Revoking *every* token on a credential change stays there, next
to the writes that trigger it.

# `count_user_tokens`

```elixir
@spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
```

Counts tokens for a given user.

# `delete_user_session_token`

```elixir
@spec delete_user_session_token(binary()) :: :ok
```

Deletes the signed token with the given context.

# `deliver_login_instructions`

```elixir
@spec deliver_login_instructions(Gamend.Accounts.User.t(), (String.t() -&gt; String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the magic link login instructions to the given user.

# `deliver_user_update_email_instructions`

```elixir
@spec deliver_user_update_email_instructions(
  Gamend.Accounts.User.t(),
  String.t(),
  (String.t() -&gt; String.t())
) :: {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the update email instructions to the given user.

## Examples

    iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
    {:ok, %{to: ..., body: ...}}

# `generate_user_session_token`

```elixir
@spec generate_user_session_token(Gamend.Accounts.User.t()) :: binary()
```

Generates a session token.

# `get_user_by_magic_link_token`

```elixir
@spec get_user_by_magic_link_token(String.t()) :: Gamend.Accounts.User.t() | nil
```

Gets the user with the given magic link token.

# `get_user_by_session_token`

```elixir
@spec get_user_by_session_token(binary()) ::
  {Gamend.Accounts.User.t(), DateTime.t()} | nil
```

Gets the user with the given signed token.

If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.

# `list_user_tokens`

```elixir
@spec list_user_tokens(Ecto.UUID.t(), keyword()) :: [Gamend.Accounts.UserToken.t()]
```

Lists tokens for a given user, optionally filtered by context.

# `login_user_by_magic_link`

```elixir
@spec login_user_by_magic_link(String.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, :not_found | Ecto.Changeset.t() | term()}
```

Logs the user in by magic link.

There are three cases to consider:

1. The user has already confirmed their email. They are logged in
   and the magic link is expired.

2. The user has not confirmed their email and no password is set.
   In this case, the user gets confirmed, logged in, and all tokens -
   including session ones - are expired. In theory, no other tokens
   exist but we delete all of them for best security practices.

3. The user has not confirmed their email but a password is set.
   This cannot happen in the default implementation but may be the
   source of security pitfalls. See the "Mixing magic link and password registration" section of
   `mix help phx.gen.auth`.

# `revoke_all_user_sessions`

```elixir
@spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
```

Revokes all session tokens for a user (mass logout).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
