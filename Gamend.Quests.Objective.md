# `Gamend.Quests.Objective`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/quests/objective.ex#L1)

One objective inside a quest definition: reach `target` occurrences of
`event` (as reported through `Gamend.Quests.report_event/4`).

`params` optionally narrows which events count — every key present must
match the reported event's meta (e.g. `%{"map" => "desert"}`).

# `t`

```elixir
@type t() :: %Gamend.Quests.Objective{event: term(), params: term(), target: term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
