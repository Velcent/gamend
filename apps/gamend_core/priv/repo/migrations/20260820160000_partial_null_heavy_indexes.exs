defmodule Gamend.Repo.Migrations.PartialNullHeavyIndexes do
  @moduledoc """
  Make the remaining NULL-heavy indexes partial.

  Same argument as `PartialUserProviderIndexes`, applied past the identity
  columns. An index entry is written for a NULL just as for a value, so a
  column that is NULL for most rows charges every insert a B-tree descent to
  record that the row has nothing there — and keeps an entry per row that no
  lookup can ever match.

  Measured on a 30,000-row `users` table: dropping the five indexes that are
  NULL for a freshly registered device user took an insert from 193us to
  125us, 35% of the write. `users` carries 15 indexes over 30 columns, so an
  insert is one row plus fifteen B-trees.

  Which ones qualify is decided by the queries, not by the column being
  nullable. A partial index only serves a query whose WHERE implies the
  predicate: `WHERE party_id = $1` and `WHERE party_id IS NOT NULL` both do,
  and both planners match them. A query that *wants* the NULL rows does not,
  which is why these are left alone:

    * `users.last_seen_at` — the admin list sorts on it, and an ORDER BY needs
      every row.
    * `users.is_online` + `last_seen_at` — the presence sweeper reads
      `is_nil(last_seen_at) or last_seen_at < cutoff`, so a NOT NULL predicate
      on `last_seen_at` would hide exactly the rows it is looking for. It is
      made partial on `is_online` instead: the sweeper filters
      `is_online == true`, few users are online at once, and a new user is
      offline, so the insert skips it either way.
    * `kv_entries.user_id` / `lobby_id` — a global entry *is* the pair of
      NULLs, and `:global_only` looks them up by it.
    * `leaderboards.starts_at` / `ends_at` and `chat_mutes.expires_at` — NULL
      means "no bound" and the window queries all read
      `is_nil(x) or x <op> now`.
    * `users.username` — generated for every user, so there is nothing to skip.
  """
  use Ecto.Migration

  # {table, columns, where, unique?}
  @indexes [
    {:users, [:party_id], "party_id IS NOT NULL", false},
    {:users, [:lobby_id], "lobby_id IS NOT NULL", false},
    # Expression index: anonymous device accounts have no display name at all,
    # so this one is empty for the majority of a device-auth database.
    {:users, ["lower(display_name)"], "display_name IS NOT NULL", false},
    {:quest_progress, [:claimed_at], "claimed_at IS NOT NULL", false},
    {:quest_progress, [:completed_at], "completed_at IS NOT NULL", false},
    {:lobbies, [:webrtc_host_id], "webrtc_host_id IS NOT NULL", false},
    {:matchmaking_tickets, [:party_id, :status], "party_id IS NOT NULL", false},
    {:entitlements, [:source_purchase_id], "source_purchase_id IS NOT NULL", false},
    {:purchases, [:provider, :provider_original_transaction_id],
     "provider_original_transaction_id IS NOT NULL", false}
  ]

  # `users(is_online, last_seen_at)` exists on SQLite only. 20260716120000
  # branched on the adapter: Postgres got `users_online_last_seen_index`,
  # already partial on `is_online = true`, while SQLite got a plain composite
  # under the default name. So Postgres has nothing to convert here, and
  # looking for the SQLite name there fails outright.
  @sqlite_only [{:users, [:is_online, :last_seen_at], "is_online", false}]

  defp indexes do
    if repo().__adapter__() == Ecto.Adapters.Postgres,
      do: @indexes,
      else: @indexes ++ @sqlite_only
  end

  def up do
    for {table, columns, where, unique?} <- indexes() do
      drop index(table, columns)
      create index_for(table, columns, unique?, where: where)
    end
  end

  def down do
    for {table, columns, _where, unique?} <- indexes() do
      drop index(table, columns)
      create index_for(table, columns, unique?, [])
    end
  end

  defp index_for(table, columns, true, opts), do: unique_index(table, columns, opts)
  defp index_for(table, columns, false, opts), do: index(table, columns, opts)
end
