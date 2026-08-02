# `Gamend.Chat.FilterWord`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/filter_word.ex#L1)

Ecto schema for the `chat_filter_words` table — one entry of the chat word
blocklist.

## Fields

  * `word` — the normalized form (see `Gamend.Chat.Moderation.Normalizer`)
  * `severity` — `"block"` rejects the message, `"mask"` replaces the hit with
    `***`, `"flag"` stores it verbatim and files a report
  * `match_mode` — `"substring"` matches anywhere, `"exact"` only a whole word
  * `lang` — provenance of a bundled-list import (`"en"`, `"de"`, …), `nil`
    for a hand-added word. Matching is language-agnostic; this only records
    where the row came from so a list can be removed in bulk.

# `t`

```elixir
@type t() :: %Gamend.Chat.FilterWord{
  __meta__: term(),
  id: term(),
  inserted_at: term(),
  lang: term(),
  match_mode: term(),
  severity: term(),
  updated_at: term(),
  word: term()
}
```

# `match_modes`

```elixir
@spec match_modes() :: [String.t()]
```

The match modes a filter word may have.

# `severities`

```elixir
@spec severities() :: [String.t()]
```

The severities a filter word may have.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
