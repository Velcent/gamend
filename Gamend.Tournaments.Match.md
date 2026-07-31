# `Gamend.Tournaments.Match`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/tournaments/match.ex#L1)

A pairing plus a verdict: two entries that must produce a winner by
`deadline_at`. Never a lobby — how the pairing is played is game policy;
`metadata` is game scratch space (runs, lobby id, ...).

# `t`

```elixir
@type t() :: %Gamend.Tournaments.Match{
  __meta__: term(),
  a_entry: term(),
  a_entry_id: term(),
  b_entry: term(),
  b_entry_id: term(),
  bracket_index: term(),
  deadline_at: term(),
  expired_at: term(),
  id: term(),
  inserted_at: term(),
  metadata: term(),
  ready_at: term(),
  resolved_at: term(),
  round: term(),
  slot: term(),
  tournament: term(),
  tournament_id: term(),
  updated_at: term(),
  winner_entry: term(),
  winner_entry_id: term()
}
```

# `changeset`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
