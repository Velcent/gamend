# `Gamend.Tournaments.Entry`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/tournaments/entry.ex#L1)

One side of the bracket: a leader and their tournament progress.

Core never tracks team rosters — for `team_size > 1` tournaments the team is
game policy (hooks), optionally stored in `metadata`.

# `t`

```elixir
@type t() :: %Gamend.Tournaments.Entry{
  __meta__: term(),
  bracket_index: term(),
  id: term(),
  inserted_at: term(),
  leader: term(),
  leader_id: term(),
  metadata: term(),
  seed: term(),
  state: term(),
  tournament: term(),
  tournament_id: term(),
  updated_at: term(),
  wins: term()
}
```

# `changeset`

# `states`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
