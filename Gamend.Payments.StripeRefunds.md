# `Gamend.Payments.StripeRefunds`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_refunds.ex#L1)

Refunding a Stripe purchase in full: the buyer's own, within
`refund_window_days` of paying (account settings, Payments), or any Stripe
purchase from the admin page.

A one-off payment is refunded. A subscription is cancelled now and its last
payment refunded. Cancelling comes first: a refund that then fails leaves no
renewal to charge, and a retry finishes it.

Nothing is revoked here. What the refund bought ends through the webhooks
that already handle a refund made in the Stripe Dashboard: `charge.refunded`
(and the refund's own events, which carry the purchase id) for a one-off
payment, `customer.subscription.deleted` for a subscription. One path,
whoever refunds.

The purchase's `metadata["stripe_refund"]` records the request
(`requested_at`, `by`) before Stripe is called and the refund (`refund_id`,
`amount`, `refunded_at`) after it. A purchase is refunded once: a recorded
refund or a `refunded` status refuses, the refund's idempotency key is the
purchase id, and Stripe refuses a second refund of a refunded payment.

# `result`

```elixir
@type result() ::
  {:ok, %{purchase: Gamend.Payments.Purchase.t(), refund: map()}}
  | {:error, term()}
```

# `admin_refund_stripe_purchase`

```elixir
@spec admin_refund_stripe_purchase(Ecto.UUID.t()) :: result()
```

Refund any Stripe purchase not refunded yet, with no window: the admin page's.

# `admin_refundable?`

```elixir
@spec admin_refundable?(Gamend.Payments.Purchase.t()) :: boolean()
```

Whether an admin can refund `purchase`: any Stripe purchase not refunded yet, at any time.

# `refund_stripe_purchase`

```elixir
@spec refund_stripe_purchase(Gamend.Accounts.User.t(), Ecto.UUID.t()) :: result()
```

Refund the buyer's own purchase (`refundable?/2`). Another account's
purchase answers `:purchase_not_found`.

# `refund_window_days`

```elixir
@spec refund_window_days() :: non_neg_integer()
```

Days after paying in which a buyer can refund; 0 when self-serve refunds are off.

# `refundable?`

```elixir
@spec refundable?(Gamend.Payments.Purchase.t(), DateTime.t()) :: boolean()
```

Whether the buyer can refund `purchase` themselves now: a completed Stripe
purchase of an entitlement or a subscription, paid within the window, not
refunded yet, and the buyer's own refunds not used up
(`self_refunds_per_account`). A subscription still in a free trial has paid
nothing. Reads the row, and the buyer's other purchases only when the row
passes; the refund checks the window again against Stripe's own payment
date.

# `self_refunds_per_account`

```elixir
@spec self_refunds_per_account() :: non_neg_integer()
```

How many refunds a buyer can make themselves over the account's life; 0 for no limit.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
