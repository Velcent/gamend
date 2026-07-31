# `Gamend.OAuthSession`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/oauth_session.ex#L1)

Simple Ecto schema for OAuth session polling used by client SDKs.

OAuth sessions allow multi-step auth flows (popup or mobile) where the SDK
polls for completion status (pending/completed/failed). The schema stores
provider-specific data in the `data` field for debugging and eventing.

# `t`

```elixir
@type t() :: %Gamend.OAuthSession{
  __meta__: term(),
  data: map(),
  id: integer() | nil,
  inserted_at: term(),
  provider: String.t(),
  session_id: String.t(),
  status: String.t(),
  updated_at: term()
}
```

A short-lived OAuth session used for polling by SDKs.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
