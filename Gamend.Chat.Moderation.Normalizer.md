# `Gamend.Chat.Moderation.Normalizer`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/moderation/normalizer.ex#L1)

Canonical form for chat filter matching.

Blocklist entries and incoming messages both go through `normalize/1`, so a
word stored as `"idiot"` still matches `"ïd１0T"` and `"iiiidiot"`. The
transform is deliberately lossy and identical on both sides — it is a
matching key, never something to show a player.

Steps, in order: lower-case; decompose and drop diacritics; drop zero-width
and soft-hyphen characters; map common leetspeak substitutions; drop
everything that is not a letter, digit or space; collapse runs of a repeated
character to one; collapse runs of whitespace to one.

Known gap: letters spaced out individually (`"i d i o t"`) survive as separate
tokens and do not match. Catching those means matching across word boundaries,
which turns benign phrases into hits far more often than it catches evasion.

# `normalize`

```elixir
@spec normalize(term()) :: String.t()
```

Reduce `text` to its matching key. Returns `""` for anything that is not a
binary, so changesets and the hot path never have to special-case nil.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
