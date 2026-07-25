# `GameServer.Lobbies.States`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/lobbies/states.ex#L1)

The vocabulary a lobby's `state` commonly uses.

Core does not model a state *machine* — it does not know when a match starts,
ends, drafts, pauses or goes to overtime. It knows a lobby was created, and
nothing more. So the values below are documentation, not an enum: core
accepts any state word, any state may follow any other, and a game that
needs a vocabulary or an ordering enforces both in
`before_lobby_state_change` — the same callback that already gates who may
move to what:

    def before_lobby_state_change(_lobby, _from, to)
        when to not in ["created", "starting", "playing", "ended"],
        do: {:error, :unknown_state}

A state is a word, not a lifecycle: core attaches no meaning to any of them,
including whether one ends the lobby. A game that finishes a match deletes
the lobby itself; retention only reaps lobbies everyone has gone quiet in.

# `core`

```elixir
@spec core() :: %{required(String.t()) =&gt; String.t()}
```

Core's default vocabulary, mapped to each state's description.

# `initial`

```elixir
@spec initial() :: String.t()
```

The state core assigns when a lobby is created.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
