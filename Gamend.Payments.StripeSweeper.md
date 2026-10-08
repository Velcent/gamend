# `Gamend.Payments.StripeSweeper`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_sweeper.ex#L1)

The safety net for a Stripe webhook that never arrived.

A checkout is fulfilled by `checkout.session.completed`. If that delivery
is lost (the endpoint down for longer than Stripe's three days of retries, a
wrong signing secret, an event left out of the endpoint's list), the buyer
has paid and the purchase stays `requires_action` with nothing to move it.

Hourly, this reconciles every Stripe purchase still `requires_action` past
the checkout session's life (`Providers.Stripe` opens one for 31 minutes)
through `Gamend.Payments.reconcile_stripe_purchase/1`: a paid one is
fulfilled, an expired one cancelled, one whose payment is still clearing
left for the next hour. A batch at a time, oldest first. Each result is
counted (`payments.sweep`), and a run that changed something is logged.

It also ends a subscription a longer plan replaced when a Stripe error left
it running (`Gamend.Payments.Upgrades.sweep/1`).

Idle while no Stripe secret key is configured. `enabled: false` in the app
config keeps it supervised but idle, for test suites (`sweep/1` still
works). Safe on several nodes at once: a reconcile locks the purchase row.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

# `sweep`

```elixir
@spec sweep(DateTime.t()) :: %{required(atom()) =&gt; non_neg_integer()}
```

Reconcile the Stripe checkouts left open past their session's life, as of
`now`. Returns how many ended each way (`%{fulfilled: 1, cancelled: 3}`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
