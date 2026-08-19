defmodule Gamend.Repo.Migrations.PartialUserProviderIndexes do
  @moduledoc """
  Make the identity-provider unique indexes on `users` partial.

  A player signs in one way, so the columns for the other ways are NULL — and
  a plain unique index stores a row for a NULL just the same. On a bench
  database of 23,184 device-auth users every one of `email`, `steam_id`,
  `discord_id`, `apple_id`, `facebook_id` and `google_id` was NULL for every
  row, and the six indexes still held 23,184 entries each: ~2.9 MB of index
  that can never match anything, and six B-tree insertions charged to every
  registration — the slowest common write in the load test.

  `device_id` has been partial since it was added; this brings the rest in
  line. Uniqueness is unchanged: NULLs never compare equal in a unique index,
  so the entries being dropped were never enforcing anything. Lookups are
  unchanged too — `WHERE email = $1` implies `email IS NOT NULL`, which both
  planners use to match the partial predicate.
  """
  use Ecto.Migration

  @columns [:email, :discord_id, :apple_id, :google_id, :facebook_id, :steam_id]

  def up do
    for column <- @columns do
      drop index(:users, [column])
      create unique_index(:users, [column], where: "#{column} IS NOT NULL")
    end
  end

  def down do
    for column <- @columns do
      drop index(:users, [column])
      create unique_index(:users, [column])
    end
  end
end
