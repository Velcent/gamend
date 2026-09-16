# `Gamend.Payments.StoreEvents`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/store_events.ex#L1)

Apple App Store and Google Play server notifications: verifying them, recording
them once, and applying what they say to purchases and entitlements.

Split out of `Gamend.Payments`, which still exposes every function here under
the same name.

# `handle_apple_webhook`

```elixir
@spec handle_apple_webhook(binary()) :: {:ok, atom()} | {:error, term()}
```

# `handle_google_webhook`

```elixir
@spec handle_google_webhook(binary(), binary() | nil) ::
  {:ok, atom()} | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
