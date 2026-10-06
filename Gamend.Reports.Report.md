# `Gamend.Reports.Report`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/report.ex#L1)

Ecto schema for the `reports` table: one report a player filed about the
game — a page, a word, anything a `Gamend.Reports.Kind` describes.

`subject` is the kind's snapshot of what was reported, taken when it was
filed, so the queue still reads right after the thing itself is renamed or
removed. `subject_ref` is the kind's short key for it, which the queue groups
duplicates on. `data` holds the kind's extra fields (a suggested correction).

# `t`

```elixir
@type t() :: %Gamend.Reports.Report{
  __meta__: term(),
  attachments: term(),
  client: term(),
  data: term(),
  description: term(),
  email: term(),
  id: term(),
  inserted_at: term(),
  kind: term(),
  locale: term(),
  resolution_note: term(),
  resolved_at: term(),
  resolved_by: term(),
  resolved_by_user: term(),
  source: term(),
  status: term(),
  subject: term(),
  subject_ref: term(),
  topic: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `files`

```elixir
@spec files(t()) :: [map()]
```

The stored attachments, each `%{"key", "type", "size"}`.

# `max_description`

```elixir
@spec max_description() :: pos_integer()
```

Longest description accepted, in characters.

# `statuses`

```elixir
@spec statuses() :: [String.t()]
```

The statuses a report may have. `open` is the only unresolved one.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
