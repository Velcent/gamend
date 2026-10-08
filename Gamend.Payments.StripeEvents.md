# `Gamend.Payments.StripeEvents`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_events.ex#L1)

Stripe: starting a checkout, and keeping purchases and entitlements in step
with what Stripe says — webhooks as they arrive, reconciliation when one was
missed, and cancelling a subscription at the end of its period.

Split out of `Gamend.Payments`, which still exposes every function here under
the same name.

# `cancel_stripe_subscription_at_period_end`

```elixir
@spec cancel_stripe_subscription_at_period_end(
  Gamend.Accounts.User.t(),
  Ecto.UUID.t()
) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     entitlement: Gamend.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
```

# `create_stripe_billing_portal`

```elixir
@spec create_stripe_billing_portal(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, String.t()} | {:error, term()}
```

Open Stripe's customer portal for this account: cancel, change card, download
invoices. `{:error, :no_stripe_customer}` when the account never paid through
Stripe Checkout.

# `create_stripe_checkout`

```elixir
@spec create_stripe_checkout(Gamend.Accounts.User.t(), map(), keyword()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     checkout_url: String.t() | nil,
     provider_session_id: String.t() | nil
   }}
  | {:error, term()}
```

Open a Stripe Checkout for `attrs` (a client's: product, quantity, return
URLs). Options are the server's own and never read from `attrs`:

  * `:trial_end` — a `DateTime` a subscription's first charge waits for
    (the card is taken now, the subscription starts `trialing`). Ignored for
    a one-off product, and when it is under 48 hours or over two years
    away, where Stripe would refuse it. For a host that grants a free
    period of its own: buying during it keeps the days already given.

A subscription bought to replace a shorter one (`Upgrades`, monthly to
yearly) waits for the period already paid for: its `trial_end` is the
later of `:trial_end` and that period's end (`Upgrades.trial_end/3`).

# `handle_stripe_webhook`

```elixir
@spec handle_stripe_webhook(binary(), binary() | nil) ::
  {:ok, atom()} | {:error, term()}
```

Verify, record and handle one Stripe webhook delivery.

Every answer is logged and counted (`payments.webhook`): a refused
signature at warning (a wrong signing secret refuses every delivery, and
only the logs say so), a handler that failed at error with the event's id
and type (Stripe retries it, and it stays unprocessed in `provider_events`
until one succeeds), and a processed or ignored one at info.

# `reconcile_stripe_purchase`

```elixir
@spec reconcile_stripe_purchase(Gamend.Payments.Purchase.t()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     result: atom(),
     stripe_session: map()
   }}
  | {:error, term()}
```

# `resume_stripe_subscription`

```elixir
@spec resume_stripe_subscription(Gamend.Accounts.User.t(), Ecto.UUID.t()) ::
  {:ok,
   %{
     purchase: Gamend.Payments.Purchase.t(),
     entitlement: Gamend.Payments.Entitlement.t(),
     stripe_subscription: map()
   }}
  | {:error, term()}
```

Takes back a cancellation scheduled for the period end, so the
subscription renews again. Stripe refuses it once the subscription ended.

# `stripe_customer_id`

```elixir
@spec stripe_customer_id(Gamend.Accounts.User.t()) :: String.t() | nil
```

The Stripe customer this account has paid as, or nil: the newest Stripe
purchase whose stored checkout session names one. Stripe creates the customer
at checkout (subscriptions always; one-off payments since
`customer_creation: "always"`), and `checkout.session.completed` stores the
session on the purchase.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
