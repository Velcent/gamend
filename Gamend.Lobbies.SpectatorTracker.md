# `Gamend.Lobbies.SpectatorTracker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/lobbies/spectator_tracker.ex#L1)

Who is watching a lobby without being a member.

Backed by `Gamend.Presence`, so counts are cluster-wide. The previous ETS
version was node-local: with more than one node every lobby undercounted,
silently and by an amount nobody could see.

Entries follow the watching channel process, so a disconnect — or a whole
node going down — removes them with no cleanup path to forget.

# `count`

```elixir
@spec count(Ecto.UUID.t()) :: non_neg_integer()
```

# `counts`

```elixir
@spec counts([Ecto.UUID.t()]) :: %{required(Ecto.UUID.t()) =&gt; non_neg_integer()}
```

Spectator counts for several lobbies, as `%{lobby_id => count}`.

# `list`

```elixir
@spec list(Ecto.UUID.t()) :: [Ecto.UUID.t()]
```

# `track`

```elixir
@spec track(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

Tracks the calling process as a spectator.

Call from the channel process: presence follows that process's lifetime.

# `untrack`

```elixir
@spec untrack(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
