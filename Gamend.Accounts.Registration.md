# `Gamend.Accounts.Registration`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/registration.ex#L1)

Creating an account and confirming it: registration, the generated username,
the first-user-is-admin rule and account activation, and email confirmation.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `change_user_registration`

```elixir
@spec change_user_registration(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

# `change_user_registration_for_validation`

```elixir
@spec change_user_registration_for_validation(Gamend.Accounts.User.t(), map()) ::
  Ecto.Changeset.t()
```

A registration changeset for live form feedback, with the uniqueness query
skipped.

`change_user_registration/2` runs `unsafe_validate_unique`, which is right on
submit and wrong on every keystroke: the registration form's `validate` event
is neither rate-limited nor captcha'd, so running it there turned the form
into an unauthenticated oracle for "does this address have an account here?",
one query per character typed. Submitting still checks, and the unique index
is what actually enforces it.

Separate function rather than an option, because `mix gen.sdk` cannot generate
a stub for a function carrying two default arguments.

# `confirm_user`

```elixir
@spec confirm_user(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Confirms a user's email by setting confirmed_at timestamp.

## Examples

    iex> confirm_user(user)
    {:ok, %User{}}

# `confirm_user_by_token`

```elixir
@spec confirm_user_by_token(String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid | :not_found}
```

Confirm a user by an email confirmation token (context: "confirm").

Returns {:ok, user} when the token is valid and user was confirmed.
Returns {:error, :not_found} or {:error, :expired} when token is invalid/expired.

# `deliver_user_confirmation_instructions`

```elixir
@spec deliver_user_confirmation_instructions(Gamend.Accounts.User.t(), (String.t() -&gt;
                                                                    String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
```

# `register_user`

```elixir
@spec register_user(Gamend.Types.user_registration_attrs()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Registers a user.

## Attributes

See `t:Gamend.Types.user_registration_attrs/0` for available fields.

## Examples

    iex> register_user(%{email: "user@example.com", password: "secret123"})
    {:ok, %User{}}

    iex> register_user(%{email: "invalid"})
    {:error, %Ecto.Changeset{}}

# `register_user_and_deliver`

```elixir
@spec register_user_and_deliver(
  Gamend.Types.user_registration_attrs(),
  (String.t() -&gt; String.t()),
  module()
) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Register a user and send the confirmation email inside a DB transaction.

The function accepts a `confirmation_url_fun` which must be a function of arity 1
that receives the encoded token and returns the confirmation URL string.

If sending the confirmation email fails the transaction is rolled back and
`{:error, reason}` is returned. On success it returns `{:ok, user}`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
