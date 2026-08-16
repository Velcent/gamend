# `Gamend.Analytics.ActivityDay`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/activity_day.ex#L1)

A user was seen on a UTC day. One row per `(user_id, day)`; written once by
`Gamend.Analytics.record_activity/2`, never updated.

# `t`

```elixir
@type t() :: %Gamend.Analytics.ActivityDay{
  __meta__: term(),
  day: term(),
  id: term(),
  inserted_at: term(),
  user: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
