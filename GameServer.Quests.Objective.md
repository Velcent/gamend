# `GameServer.Quests.Objective`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/quests/objective.ex#L1)

One objective inside a quest definition: reach `target` occurrences of
`event` (as reported through `GameServer.Quests.report_event/4`).

`params` optionally narrows which events count — every key present must
match the reported event's meta (e.g. `%{"map" => "desert"}`).

# `t`

```elixir
@type t() :: %GameServer.Quests.Objective{
  event: term(),
  params: term(),
  target: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
