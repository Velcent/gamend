# `Gamend.Tournaments.Tournament`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/tournaments/tournament.ex#L1)

A bracket tournament occurrence.

Recurring tournaments share a `slug` (one row per occurrence, like
leaderboard seasons); `recur` holds the cron expression that spawns the next
occurrence. `team_size` is advisory — core only ever tracks entry leaders.
A nil `starts_at` means manual start: registration stays open until an
admin/game sets `starts_at` (the "draw now" force action does exactly that).

`icon_url` is optional; when nil, clients show their default tournament
icon (the web UI uses `GamendWeb.Icons.default(:tournament)`).

# `t`

```elixir
@type t() :: %Gamend.Tournaments.Tournament{
  __meta__: term(),
  bracket_size: term(),
  deadline_policy: term(),
  description: term(),
  ends_at: term(),
  entries: term(),
  icon_url: term(),
  id: term(),
  inserted_at: term(),
  max_entries: term(),
  metadata: term(),
  recur: term(),
  registration_opens_at: term(),
  round_window_sec: term(),
  slug: term(),
  starts_at: term(),
  state: term(),
  team_size: term(),
  title: term(),
  updated_at: term()
}
```

# `changeset`

# `deadline_policies`

# `states`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
