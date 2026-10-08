# `Gamend.Payments.Counters`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/counters.ex#L1)

What happened to payments, per day, as `Gamend.Analytics.count/3` counters:
the admin analytics page lists them under "Counters" with the game's own.

Every key starts with `payments.`. A dimension goes after a colon, one
counter each, so a family reads back by prefix
(`Analytics.counts("payments.purchase.fulfilled.sku:*")`):

  * `payments.checkout.opened` / `.refused` / `.failed` — a checkout session
    opened, refused before money could move (`reason:`), or refused by the
    provider (`reason:`). `provider:`, `sku:`.
  * `payments.purchase.fulfilled` / `.revoked` / `.restored` — the goods
    handed over, taken back (`reason:` the status it ended in), or handed
    back when a dispute was won. `provider:`, `sku:`.
  * `payments.subscription.renewed` / `.past_due` / `.cancel_scheduled` /
    `.resumed` — read off each subscription write. `sku:`.
  * `payments.subscription.superseded` / `.supersede_failed` — a plan
    that renews, ended for a longer one (`Gamend.Payments.Upgrades`), by
    `mode:` (now, at_period_end) and `sku:`, or the `reason:` it was not.
  * `payments.refund.requested` / `.failed` — a refund through
    `Gamend.Payments.StripeRefunds` (`by:` buyer or admin).
  * `payments.portal.opened` — the Stripe customer portal.
  * `payments.webhook` — every delivery, by `provider:`, `type:` and
    `result:` (processed, ignored, duplicate, failed, refused).
  * `payments.sweep` — `Gamend.Payments.StripeSweeper`, by `result:`.

Counted after the write it describes, outside any transaction. Never
raises and never fails the caller: a counter is not worth a payment.

# `count`

```elixir
@spec count(String.t(), keyword()) :: :ok
```

Adds one to `payments.<event>` and to each `payments.<event>.<dim>:<value>`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
