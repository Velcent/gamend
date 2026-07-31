defmodule Gamend.Repo.Migrations.RenameObanWorkersToGamend do
  use Ecto.Migration

  # `oban_jobs.worker` stores the module name as a string, so every job queued
  # before the GameServer -> Gamend rename points at a module that no longer
  # exists and would be discarded on its next attempt.
  def up do
    execute("""
    UPDATE oban_jobs
       SET worker = replace(worker, 'GameServer', 'Gamend')
     WHERE worker LIKE 'GameServer%'
    """)
  end

  def down do
    execute("""
    UPDATE oban_jobs
       SET worker = replace(worker, 'Gamend', 'GameServer')
     WHERE worker LIKE 'Gamend%'
    """)
  end
end
