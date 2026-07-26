defmodule GameServer.Repo.Migrations.RenameDeadlineToDeadlineAt do
  use Ecto.Migration

  # Instants are named `*_at` (docs/specs/api-conventions.md, R3). These two
  # were the only `:utc_datetime` columns that were not.
  def change do
    rename table(:ready_checks), :deadline, to: :deadline_at
    rename table(:tournament_matches), :deadline, to: :deadline_at
  end
end
