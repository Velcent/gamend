defmodule Gamend.Repo.Migrations.AddQuestProgressLockVersion do
  @moduledoc """
  Optimistic-lock counter for `quest_progress`.

  Advancing a quest is a read-modify-write on the `objective_progress` JSON
  map, and it used to be serialized with a per-(user, quest) advisory lock —
  a transaction and a lock round trip on the hottest write a player makes.
  This column replaces the lock: every writer of the row carries the version
  it read, so a merge that raced another one matches no row and is retried
  against what actually landed instead of overwriting it.

  Defaults to 1 and is never null, so rows written before this migration take
  part from their next write without a backfill.
  """
  use Ecto.Migration

  def change do
    alter table(:quest_progress) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
