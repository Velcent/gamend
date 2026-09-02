defmodule Gamend.Repo.Migrations.LeaderboardRankIndex do
  use Ecto.Migration

  # An index matching how leaderboard records are actually ordered and ranked.
  #
  # `Leaderboards.record_order/1` sorts by `(score, inserted_at)` and
  # `calculate_rank/3` breaks ties on `inserted_at`, but the two existing
  # indexes carry `(leaderboard_id, score)` and `(leaderboard_id, score,
  # updated_at)` — so the tiebreak column was never in an index, and both the
  # rank count and the paged listing fell back to scanning the board's rows.
  #
  # Both directions are covered by one index: `sort_order` can be `:asc` or
  # `:desc` per leaderboard, and a B-tree serves an ordered scan either way.
  def change do
    create index(:leaderboard_records, [:leaderboard_id, :score, :inserted_at],
             name: :leaderboard_records_rank_index
           )
  end
end
