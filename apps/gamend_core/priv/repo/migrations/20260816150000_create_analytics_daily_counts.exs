defmodule Gamend.Repo.Migrations.CreateAnalyticsDailyCounts do
  use Ecto.Migration

  # Per-day counters for things that have no table of their own: a level
  # finished, a start blocked by empty hearts, a shop opened. One row per
  # `(day, key)`, incremented in place — the cheap alternative to an event
  # table when all a dashboard needs is a daily series.
  def change do
    create table(:analytics_daily_counts) do
      add :day, :date, null: false
      add :key, :string, null: false
      add :count, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_daily_counts, [:day, :key])
    create index(:analytics_daily_counts, [:key, :day])

    # Coin source/sink per day groups the ledger by insertion time; the
    # existing indexes all lead with user_id.
    create index(:ledger_entries, [:inserted_at])
  end
end
