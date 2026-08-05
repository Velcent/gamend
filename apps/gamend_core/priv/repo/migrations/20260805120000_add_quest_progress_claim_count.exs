defmodule Gamend.Repo.Migrations.AddQuestProgressClaimCount do
  use Ecto.Migration

  # Rewards are deduped per progress ROW (`quest:<progress_id>:<index>`), which
  # is exactly-once as long as a row is only ever claimed once. A `repeat` quest
  # re-arms the same row, so without something that changes between claims the
  # second payout would be swallowed as a duplicate and the player would get
  # nothing, silently. This counter is that something.
  def change do
    alter table(:quest_progress) do
      add :claim_count, :integer, null: false, default: 0
    end
  end
end
