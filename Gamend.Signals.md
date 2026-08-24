# `Gamend.Signals`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/signals.ex#L1)

Server-side signals: a plugin emits a named event, another part of the plugin
waits for it.

This is the server's answer to Godot's `signal` / `emit` / `await`. Nothing
on the server emits engine signals, so a hook that wants to wait for
something needs a source of its own:

    Gamend.Signals.subscribe("my_game", "level_up")
    Gamend.Signals.emit("my_game", "level_up", [user_id, 5])
    {:ok, [user_id, level]} = Gamend.Signals.await("my_game", "level_up")

Signals are scoped to one plugin, so two plugins may use the same name
without colliding, and they ride `Phoenix.PubSub`, so an emit reaches every
node in a cluster.

`subscribe/2` before `await/3`, not inside it: a signal emitted between the
two would otherwise be missed. The GDScript front end does this
automatically, subscribing at function entry for every signal the function
awaits.

# `payload`

```elixir
@type payload() :: term()
```

Whatever the emitter passed, unchanged.

# `await`

```elixir
@spec await(String.t(), String.t(), timeout()) ::
  {:ok, payload()} | {:error, :timeout}
```

Waits for the next `name`, returning `{:ok, payload}` or `{:error, :timeout}`.

Only sees signals emitted after `subscribe/2` ran in this process.

# `emit`

```elixir
@spec emit(String.t(), String.t(), payload()) :: :ok
```

Emits `name` with `payload` to every subscriber, on every node.

Returns `:ok` whether or not anyone was listening -- a signal with no
listener is dropped, as in Godot.

# `subscribe`

```elixir
@spec subscribe(String.t(), String.t()) :: :ok
```

Subscribes the calling process to `name`.

Idempotent, and scoped to the process that calls it -- when a hook's Task
ends, the subscription goes with it.

# `topic`

```elixir
@spec topic(String.t(), String.t()) :: String.t()
```

Topic a signal rides on. Public so a plugin can subscribe by hand.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
