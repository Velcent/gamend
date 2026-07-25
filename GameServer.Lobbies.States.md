# `GameServer.Lobbies.States`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/lobbies/states.ex#L1)

The vocabulary a lobby's `state` may use.

Core does not model a state *machine* — it does not know when a match starts,
ends, drafts, pauses or goes to overtime. It knows a lobby was created, and
nothing more. So the values below are a documented default vocabulary, not an
enum, and any state may follow any other; a game that needs ordering enforces
it in `before_lobby_state_change`.

Games add their own by exporting `lobby_states/0` (see
`GameServer.Hooks.Declarations`), which merge with the core defaults:

    def lobby_states do
      %{
        "drafting" => %{description: "Picking teams"},
        "post_game" => %{description: "Scoreboard", terminal: true, prune_after_minutes: 10}
      }
    end

Declaring is optional — a game that says nothing simply uses the defaults.
`terminal`/`prune_after_minutes` are read by lobby retention (see
docs/specs/lobby-state.md); they have no other effect.

# `all`

```elixir
@spec all() :: %{required(String.t()) =&gt; map()}
```

Core defaults plus every plugin-declared state.

# `core`

```elixir
@spec core() :: %{required(String.t()) =&gt; map()}
```

Core's default vocabulary, mapped to its metadata.

# `initial`

```elixir
@spec initial() :: String.t()
```

The state core assigns when a lobby is created.

# `known?`

```elixir
@spec known?(term()) :: boolean()
```

True when `state` is a core default or declared by a loaded plugin.

# `terminal`

```elixir
@spec terminal() :: %{required(String.t()) =&gt; map()}
```

States that end a lobby's life, mapped to their metadata. Lobby retention
consumes this; nothing else in core reads it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
