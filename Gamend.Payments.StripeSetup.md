# `Gamend.Payments.StripeSetup`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/stripe_setup.ex#L1)

The Stripe account set up the way this code reads it, from a script
(`mix gamend.stripe.setup`, a host's own task for its prices), never by
hand-copying a checklist:

  * the **webhook endpoint**: the URL, the API version this server pins
    (`ProviderConfig.stripe_api_version/0`) and exactly the events
    `Gamend.Payments.StripeEvents` handles (`webhook_events/0`);
  * the **customer portal**'s default configuration: cancel at the period
    end with no proration, card update, invoice history, and no plan
    switching (a plan is changed through the host's own page);
  * a **product** and its **prices**, for a host that describes them
    (`ensure_product/2`, `ensure_price/2`).

Every function compares what Stripe holds with what is wanted, and changes
it only when called with `apply: true`. A step answers a list of findings,
`%{area, status, message}`:

  * `:ok` — Stripe holds what is wanted;
  * `:pending` — it does not, and `apply: true` would fix it;
  * `:changed` — it did not, and it was fixed;
  * `:manual` — it does not, and only a person can fix it (in the
    Dashboard, or with an option that replaces something);
  * `:error` — Stripe answered an error.

Two things Stripe allows only once, and the steps say so instead of
guessing: a webhook endpoint's API version is set when it is created (a new
version is a new endpoint, `recreate: true`, with a new signing secret), and
a price's amount, currency, interval and tax behaviour never change (a new
price takes the old one's lookup key, and the old one is archived).

Calls go through the `:stripe_client` the adapter uses, on the pinned API
version, as maps.

# `finding`

```elixir
@type finding() :: %{area: String.t(), status: status(), message: String.t()}
```

# `status`

```elixir
@type status() :: :ok | :pending | :changed | :manual | :error
```

# `drift?`

```elixir
@spec drift?([finding()]) :: boolean()
```

Whether a list of findings needs anything: a pending, manual or failed one.

# `ensure_portal`

```elixir
@spec ensure_portal(keyword()) :: [finding()]
```

The customer portal's default configuration against `portal_features/0`.
Stripe makes the default one when the portal is activated in the
Dashboard; without it the portal cannot open, and that is a manual step.

# `ensure_price`

```elixir
@spec ensure_price(map(), keyword()) :: {String.t() | nil, [finding()]}
```

A price found by its `lookup_key`, against `product`, `unit_amount`,
`currency`, `recurring` (`%{interval: "year"}`, or nil for one payment)
and `tax_behavior`. Missing: created. Archived: unarchived. Different in
anything Stripe never changes on a price: a new price takes the lookup key
and the old one is archived (with `apply: true`).

Returns `{price_id | nil, findings}`: the id that holds the lookup key
after the step, for the host's list of price ids.

# `ensure_product`

```elixir
@spec ensure_product(map(), keyword()) :: {String.t() | nil, [finding()]}
```

A product by its fixed id (`id`, `name`, `tax_code`, optional
`metadata`), its name, tax code and `active` brought in line. When there is
no product with that id, `adopt:` (a product id already in use, e.g. the
one the configured prices are on) is used instead, so a product made by
hand is kept rather than doubled; only with neither is one created.

Returns `{product_id | nil, findings}`: the product the prices belong on.
On a check that would create it, the id it would get.

# `ensure_webhook`

```elixir
@spec ensure_webhook(String.t(), keyword()) :: [finding()]
```

The webhook endpoint for `url`. Options: `apply:` (make changes),
`recreate:` (with `apply:`, replace an endpoint on another API release:
a new endpoint, the old one disabled). A new endpoint's signing secret is
in its finding's message, the only time Stripe shows it.

# `portal_features`

```elixir
@spec portal_features() :: map()
```

What the customer portal's default configuration must hold.

# `price_product`

```elixir
@spec price_product(String.t()) :: String.t() | nil
```

The product a price is on, or nil when the price does not exist.

# `webhook_events`

```elixir
@spec webhook_events() :: [String.t()]
```

The events the webhook endpoint must send: the ones this server handles.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
