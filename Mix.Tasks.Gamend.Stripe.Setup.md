# `mix gamend.stripe.setup`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/mix/tasks/gamend.stripe.setup.ex#L1)

The Stripe account's webhook endpoint and customer portal, as
`Gamend.Payments.StripeSetup` wants them, on the account the configured
secret key belongs to (`GAMEND_PAYMENTS_ENVIRONMENT` picks the sandbox or
the production key, read from `.env` like the server reads it).

    mix gamend.stripe.setup --url https://example.com/api/v1/payments/webhooks/stripe
    mix gamend.stripe.setup --url … --check            # exit 1 when anything differs
    mix gamend.stripe.setup --url … --apply            # make the changes
    mix gamend.stripe.setup --url … --apply --recreate # also replace an endpoint on another API version
    mix gamend.stripe.setup --url … --apply --live     # required to change a live (sk_live_) account

Without `--apply` nothing changes: every line says what is right, what
would change, and what only the Dashboard can do. A new endpoint's signing
secret is printed once; put it in `.env`. A host with prices of its own
runs its own task, which calls `run_steps/2` with them.

# `print`

```elixir
@spec print([Gamend.Payments.StripeSetup.finding()]) :: :ok
```

Prints findings, one line each, marked by status.

# `run_steps`

```elixir
@spec run_steps(keyword(), (keyword() -&gt; [Gamend.Payments.StripeSetup.finding()])) ::
  [
    Gamend.Payments.StripeSetup.finding()
  ]
```

Loads the config, prints which account and mode, refuses `--apply` on a
live key without `--live`, runs `steps` with `[apply:, recreate:]`, prints
every finding and the Dashboard-only steps, and with `--check` raises when
anything differs. For a host task that adds steps of its own.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
