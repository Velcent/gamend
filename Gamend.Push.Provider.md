# `Gamend.Push.Provider`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/provider.ex#L1)

Behaviour for push delivery providers.

Delivery is one message to one token (FCM v1 and APNs are both
one-request-per-token), invoked from `Gamend.Push.DeliveryWorker`.
Result meanings drive the worker's bookkeeping:

- `:ok` – delivered; `last_used_at` is bumped.
- `{:invalid, reason}` – the provider says this token is dead; it is
  soft-disabled.
- `{:error, :transient, reason}` – worth retrying; the Oban job errors and
  backs off.
- `{:error, :permanent, reason}` – a config/payload error retrying cannot
  fix; the job is cancelled and the reason logged.

# `result`

```elixir
@type result() :: :ok | {:invalid, atom()} | {:error, :transient | :permanent, term()}
```

# `configured?`

```elixir
@callback configured?() :: boolean()
```

Whether the provider can deliver right now (credentials + process up).

# `deliver`

```elixir
@callback deliver(Gamend.Push.Message.t(), Gamend.Push.PushToken.t()) :: result()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
