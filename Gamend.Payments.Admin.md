# `Gamend.Payments.Admin`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/admin.ex#L1)

What the admin payments pages and API read: the stats, provider configuration
status, and filtered listings of products, purchases, entitlements, provider
events and reconciliation cursors.

Split out of `Gamend.Payments`, which still exposes every function here under
the same name.

# `admin_stats`

```elixir
@spec admin_stats() :: map()
```

# `count_entitlements`

```elixir
@spec count_entitlements(keyword()) :: non_neg_integer()
```

# `count_products`

```elixir
@spec count_products(keyword()) :: non_neg_integer()
```

# `count_provider_events`

```elixir
@spec count_provider_events(keyword()) :: non_neg_integer()
```

# `count_provider_products`

```elixir
@spec count_provider_products(keyword()) :: non_neg_integer()
```

# `count_purchases`

```elixir
@spec count_purchases(keyword()) :: non_neg_integer()
```

# `count_reconciliation_cursors`

```elixir
@spec count_reconciliation_cursors(keyword()) :: non_neg_integer()
```

# `list_admin_entitlements`

```elixir
@spec list_admin_entitlements(keyword()) :: [Gamend.Payments.Entitlement.t()]
```

# `list_admin_products`

```elixir
@spec list_admin_products(keyword()) :: [Gamend.Payments.Product.t()]
```

# `list_admin_provider_products`

```elixir
@spec list_admin_provider_products(keyword()) :: [Gamend.Payments.ProviderProduct.t()]
```

# `list_admin_purchases`

```elixir
@spec list_admin_purchases(keyword()) :: [Gamend.Payments.Purchase.t()]
```

# `list_provider_events`

```elixir
@spec list_provider_events(keyword()) :: [Gamend.Payments.ProviderEvent.t()]
```

# `list_reconciliation_cursors`

```elixir
@spec list_reconciliation_cursors(keyword()) :: [
  Gamend.Payments.ReconciliationCursor.t()
]
```

# `provider_adapter_statuses`

```elixir
@spec provider_adapter_statuses() :: [map()]
```

# `stripe_config_status`

```elixir
@spec stripe_config_status() :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
