defmodule Gamend.Repo.Migrations.CreateUserActivityDays do
  use Ecto.Migration

  # One row per user per UTC day they were seen. `users.last_seen_at` only
  # keeps the latest instant, which answers "active in the last N days" but
  # not "of the players who joined on day X, how many came back on X+1/X+7/
  # X+30" — that needs the history this table is.
  def change do
    create table(:user_activity_days) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :day, :date, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_activity_days, [:user_id, :day])
    # DAU/WAU/MAU and cohort joins scan by day.
    create index(:user_activity_days, [:day])
  end
end
