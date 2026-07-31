# `Gamend.Chat.ReadCursor`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/read_cursor.ex#L1)

Ecto schema for the `chat_read_cursors` table.

Tracks the last message a user has read in a given chat conversation.
The unique constraint on `[user_id, chat_type, chat_ref_id]` ensures
one cursor per user per conversation.

# `t`

```elixir
@type t() :: %Gamend.Chat.ReadCursor{
  __meta__: term(),
  chat_ref_id: term(),
  chat_type: term(),
  id: term(),
  inserted_at: term(),
  last_read_message: term(),
  last_read_message_id: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `changeset`

Changeset for creating/updating a read cursor.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
