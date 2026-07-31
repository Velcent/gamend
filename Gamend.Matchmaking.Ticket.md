# `Gamend.Matchmaking.Ticket`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/matchmaking/ticket.ex#L1)

Ecto schema for a matchmaking ticket.

A ticket represents one matchmaking request from a user. Tickets with
the same `match_params` are grouped and matched together.

A ticket queued on behalf of a party carries that party's `party_id`. Tickets
sharing a `party_id` form an indivisible unit: the matcher seats them in the
same lobby or leaves them all queued.

# `t`

```elixir
@type t() :: %Gamend.Matchmaking.Ticket{
  __meta__: term(),
  id: term(),
  inserted_at: term(),
  match_id: term(),
  match_params: term(),
  matched_at: term(),
  max_players: term(),
  min_players: term(),
  party: term(),
  party_id: term(),
  queued_at: term(),
  status: term(),
  timeout_ms: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
