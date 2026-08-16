# `Gamend.Analytics.DailyCount`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/daily_count.ex#L1)

A named counter for one UTC day. Keys are free-form dotted strings owned by
the game (`"level.finished"`, `"level.started.lang:ja"`); the engine only
stores and sums them. Written by `Gamend.Analytics.count/3`.

# `t`

```elixir
@type t() :: %Gamend.Analytics.DailyCount{
  __meta__: term(),
  count: term(),
  day: term(),
  id: term(),
  inserted_at: term(),
  key: term(),
  updated_at: term()
}
```

# `key_max`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
