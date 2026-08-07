defmodule Gamend.Repo.Migrations.AddQuestGroupKey do
  use Ecto.Migration

  def change do
    alter table(:quests) do
      add :group_key, :string
    end

    create index(:quests, [:group_key])
  end
end
