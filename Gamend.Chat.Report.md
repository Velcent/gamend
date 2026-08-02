# `Gamend.Chat.Report`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/report.ex#L1)

Ecto schema for the `chat_reports` table — a player- or filter-filed report
about a chat message.

`reporter_id` is `nil` when the word filter filed the report itself (a `flag`
severity hit). `reported_user_id` and `content_snapshot` are denormalized so
the queue still makes sense after the message is deleted.

# `t`

```elixir
@type t() :: %Gamend.Chat.Report{
  __meta__: term(),
  content_snapshot: term(),
  id: term(),
  inserted_at: term(),
  message: term(),
  message_id: term(),
  reason: term(),
  reported_user: term(),
  reported_user_id: term(),
  reporter: term(),
  reporter_id: term(),
  resolution_note: term(),
  resolved_at: term(),
  resolved_by: term(),
  resolved_by_user: term(),
  status: term(),
  updated_at: term()
}
```

# `resolve_changeset`

```elixir
@spec resolve_changeset(t(), map()) :: Ecto.Changeset.t()
```

Changeset for a moderator resolving a report.

# `statuses`

```elixir
@spec statuses() :: [String.t()]
```

The statuses a report may have.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
