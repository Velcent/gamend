# `GameServer.Theme.Translatable`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/theme/translatable.ex#L1)

Which leaves of a theme config are text, and which are configuration.

One list, used by both the renderer (`GameServer.Theme.JSONConfig`) and the
extractor (`mix gamend.theme.extract`), so the strings a translator is shown
and the strings the server translates cannot drift apart.

This is also the guard that keeps configuration out of translations. The
theme used to be one whole JSON file per locale, and a config field added to
English never reached the other 29 — every one of them silently lost
`theme_color`, so non-English visitors got the fallback colour. A key that
is not on this list is configuration: it is never extracted, never
translated, and cannot vary by locale.

# `keys`

```elixir
@spec keys() :: [String.t()]
```

Keys whose string values are user-facing text.

# `strings`

```elixir
@spec strings(term()) :: [String.t()]
```

Every translatable string in a decoded config, in document order, without
duplicates. What the extractor writes into `theme.pot`.

# `text?`

```elixir
@spec text?(String.t() | atom()) :: boolean()
```

Whether a leaf at `key` holds text rather than configuration.

# `walk`

```elixir
@spec walk(term(), (String.t() -&gt; String.t())) :: term()
```

Walks a decoded theme config, applying `fun` to every translatable leaf and
leaving everything else untouched.

`fun` receives the string and returns its replacement, so the same traversal
serves rendering (translate it) and extraction (collect it).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
