# `Gamend.Payments.ProviderConfig`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/provider_config.ex#L1)

Runtime payment-provider configuration helpers.

`PAYMENTS_ENVIRONMENT` is the single switch that selects sandbox versus
production provider credentials for this host.

# `environment`

```elixir
@type environment() :: String.t()
```

# `environment`

```elixir
@spec environment() :: environment()
```

# `environments`

```elixir
@spec environments() :: [String.t()]
```

# `normalize_environment`

# `production?`

```elixir
@spec production?() :: boolean()
```

# `stripe_api_release`

```elixir
@spec stripe_api_release(String.t() | nil) :: String.t() | nil
```

The release a Stripe API version belongs to (`"clover"` for
`"2025-11-17.clover"`), or nil for a version older than the named releases.
Inside one release Stripe only adds; a breaking change starts the next.

# `stripe_api_version`

```elixir
@spec stripe_api_version() :: String.t()
```

The Stripe API version every request names, and webhooks are expected in.

# `stripe_candidate_labels`

```elixir
@spec stripe_candidate_labels(:secret_key | :webhook_secret) :: [String.t()]
```

# `stripe_managed_payments?`

```elixir
@spec stripe_managed_payments?() :: boolean()
```

Whether checkouts go through Stripe Managed Payments (Stripe as merchant of record).

# `stripe_secret_key`

```elixir
@spec stripe_secret_key() :: String.t() | nil
```

# `stripe_secret_key_source`

```elixir
@spec stripe_secret_key_source() :: {String.t(), String.t()} | nil
```

# `stripe_webhook_secret`

```elixir
@spec stripe_webhook_secret() :: String.t() | nil
```

# `stripe_webhook_secret_source`

```elixir
@spec stripe_webhook_secret_source() :: {String.t(), String.t()} | nil
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
