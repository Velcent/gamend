# `Gamend.Push.PushToken`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/push_token.ex#L1)

Ecto schema for a registered device push token.

Fields:

- `user_id` – owner; a user has many devices
- `token` – the FCM registration token or APNs device token (globally unique)
- `platform` – `"android"` | `"ios"` | `"web"`
- `provider` – `"fcm"` | `"apns"`; drives per-token delivery routing
- `device_id` – optional stable device key so re-registering rotates the
  token in place instead of accumulating rows
- `disabled_at` – set when the provider reports the token dead (soft-delete)
- `last_used_at` – bumped on successful delivery
- `metadata` – optional client info (`app_version`, `locale`, …), size-capped

# `t`

```elixir
@type t() :: %Gamend.Push.PushToken{
  __meta__: term(),
  device_id: String.t() | nil,
  disabled_at: DateTime.t() | nil,
  id: String.t() | nil,
  inserted_at: DateTime.t() | nil,
  last_used_at: DateTime.t() | nil,
  metadata: map(),
  platform: String.t() | nil,
  provider: String.t() | nil,
  token: String.t() | nil,
  updated_at: DateTime.t() | nil,
  user: term(),
  user_id: String.t() | nil
}
```

A registered device push token.

# `platforms`

```elixir
@spec platforms() :: [String.t()]
```

The accepted `platform` values.

# `providers`

```elixir
@spec providers() :: [String.t()]
```

The accepted `provider` values.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
