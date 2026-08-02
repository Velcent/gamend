# `Gamend.Chat.Moderation.Cache`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/moderation/cache.ex#L1)

Node-local hot path for chat moderation: the word blocklist and active mutes.

Mirrors the shape of `GamendWeb.Plugs.IpBan` — the database is the source of
truth, ETS is the per-message read path, and PubSub carries changes to the
other instances (applied by `Gamend.Chat.Moderation.Sync`, which also loads
both tables at boot).

It lives in core rather than beside the IP-ban table in the web app because
the check runs inside `Gamend.Chat.send_message/2`, before anything web-facing
is involved.

Substring matching goes through a compiled binary pattern (Aho-Corasick), kept
in `:persistent_term` so a 10k-word list costs one pass over the message
instead of 10k comparisons. It is rebuilt whole on every change, so bulk
imports must insert their rows and call `reload_words/0` once rather than
going through `put_word/1` per row.

# `apply_remote`

```elixir
@spec apply_remote(atom(), term()) :: :ok
```

Apply a change that originated on another instance.

Only touches ETS — the originating instance already persisted it.

# `delete_mute`

```elixir
@spec delete_mute(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: :ok
```

Remove a mute locally and on the other instances.

# `delete_word`

```elixir
@spec delete_word(String.t()) :: :ok
```

Remove a blocklist entry locally and on the other instances.

# `init_table`

```elixir
@spec init_table() :: :ok
```

Ensure the ETS tables exist (called once at app startup).

# `list_words`

```elixir
@spec list_words() :: [{String.t(), String.t(), String.t()}]
```

Every blocklist entry as `[{word, severity, match_mode}]`.

# `load_persisted`

```elixir
@spec load_persisted() :: :ok
```

Load the blocklist and every unexpired mute from the database into ETS.

Called at boot by `Gamend.Chat.Moderation.Sync`.

# `lookup_word`

```elixir
@spec lookup_word(String.t()) :: {String.t(), String.t()} | nil
```

Look up the severity and match mode of `word` (already normalized).

Returns `nil` when the word is not on the blocklist.

# `mute_count`

```elixir
@spec mute_count() :: non_neg_integer()
```

Number of active mutes loaded on this node.

# `muted?`

```elixir
@spec muted?(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: boolean()
```

Whether `user_id` is currently muted for the given chat.

A `"global"` mute covers every chat type including friend DMs; a scoped mute
only covers its own room. Expired entries are dropped on read, so enforcement
never depends on the sweep having run.

# `normalize`

```elixir
@spec normalize(term()) :: String.t()
```

Normalized form of `text`, for callers that only have the cache aliased.

# `put_mute`

```elixir
@spec put_mute(Gamend.Chat.Mute.t()) :: :ok
```

Mirror a mute locally and on the other instances.

# `put_word`

```elixir
@spec put_word(Gamend.Chat.FilterWord.t()) :: :ok
```

Mirror a single blocklist entry locally and on the other instances.

# `reload_words`

```elixir
@spec reload_words() :: :ok
```

Reload the whole blocklist from the database.

Used after a bulk import or delete, and by `Sync` at boot. Broadcasts so the
other instances reload too — the alternative is one message per word.

# `substring_pattern`

```elixir
@spec substring_pattern() :: :binary.cp() | nil
```

The compiled pattern of every `substring` word, or `nil` when there are none.

# `topic`

```elixir
@spec topic() :: String.t()
```

PubSub topic on which moderation changes are broadcast.

# `word_count`

```elixir
@spec word_count() :: non_neg_integer()
```

Number of words currently loaded on this node.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
