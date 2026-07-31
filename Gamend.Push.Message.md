# `Gamend.Push.Message`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/message.ex#L1)

A validated push message: what `Gamend.Push.send_to_user/3` accepts and
what the delivery workers carry through job args.

Fields:

- `title` – required, capped by `max_push_title` **bytes**
- `body` – optional, capped by `max_push_body` **bytes**
- `data` – optional custom key/value map, serialized size capped by
  `max_push_data_size` bytes. FCM requires string values on the wire, so
  non-string values are JSON-encoded by the FCM provider; clients decode
  them back.

Caps are bytes, not characters, because the provider limits are bytes (FCM
and APNs both cap the payload at 4096) — a character cap would let multibyte
text through validation only to fail on the wire.
- `image` – optional image URL
- `sound` – optional sound name
- `badge` – optional iOS badge count
- `collapse_key` – optional dedupe key (`apns-collapse-id` / FCM
  `collapse_key`), which is what makes an at-least-once redelivery invisible
  on-device

# `t`

```elixir
@type t() :: %Gamend.Push.Message{
  badge: non_neg_integer() | nil,
  body: String.t() | nil,
  collapse_key: String.t() | nil,
  data: map() | nil,
  image: String.t() | nil,
  sound: String.t() | nil,
  title: String.t()
}
```

# `from_map`

```elixir
@spec from_map(map()) :: t()
```

Rebuild from job args. Args were validated at enqueue time.

# `new`

```elixir
@spec new(map()) :: {:ok, t()} | {:error, %{required(atom()) =&gt; String.t()}}
```

Build and validate a message from a map (string or atom keys).

Returns `{:ok, %Message{}}` or `{:error, errors}` where `errors` maps a
field to its problem, e.g. `%{title: "can't be blank"}`.

# `to_map`

```elixir
@spec to_map(t()) :: map()
```

Serialize for Oban job args (string keys, nils dropped).

# `truncate`

```elixir
@spec truncate(String.t(), non_neg_integer()) :: String.t()
```

Truncate a UTF-8 string to at most `max_bytes` without splitting a
character. For callers bridging longer content (notification bodies,
personalized titles) into the push byte caps.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
