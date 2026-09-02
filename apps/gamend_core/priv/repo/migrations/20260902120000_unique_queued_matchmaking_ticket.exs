defmodule Gamend.Repo.Migrations.UniqueQueuedMatchmakingTicket do
  use Ecto.Migration

  # One queued ticket per user, enforced by the database.
  #
  # `Matchmaking.ensure_none_queued/1` is a bare existence check outside any
  # transaction, and the `before_matchmaking_join` hook runs between it and the
  # insert — so a double tap or a client retry produced two queued tickets for
  # one player. The sweep treats those as separate FIFO groups and can seat them
  # in one match (matching a player with themselves, which is what the guard's
  # own comment says it prevents) or in two different lobbies.
  #
  # Partial, so only queued tickets are constrained: a user accumulates matched
  # and cancelled rows over time, and those must stay unconstrained.
  def up do
    create unique_index(:matchmaking_tickets, [:user_id],
             where: "status = 'queued'",
             name: :matchmaking_tickets_one_queued_per_user
           )
  end

  def down do
    drop index(:matchmaking_tickets, [:user_id], name: :matchmaking_tickets_one_queued_per_user)
  end
end
