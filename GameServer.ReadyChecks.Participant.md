# `GameServer.ReadyChecks.Participant`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/ready_checks/participant.ex#L1)

Ecto schema for one player's answer inside a ready check.

A row, not a key in a map on the check: answering is then a single-row write,
so two players answering in the same instant cannot overwrite each other.

`ticket_id` is set only for matchmaking checks, where the participant's seat
in the queue has to dissolve with the check.

# `t`

```elixir
@type t() :: %GameServer.ReadyChecks.Participant{
  __meta__: term(),
  id: term(),
  inserted_at: term(),
  ready_check: term(),
  ready_check_id: term(),
  responded_at: term(),
  state: term(),
  ticket: term(),
  ticket_id: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `states`

```elixir
@spec states() :: [String.t()]
```

The states a participant may be in.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
