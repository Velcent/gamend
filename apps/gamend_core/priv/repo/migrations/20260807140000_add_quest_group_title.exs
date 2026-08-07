defmodule Gamend.Repo.Migrations.AddQuestGroupTitle do
  use Ecto.Migration

  def change do
    alter table(:quests) do
      add :group_title, :string
    end
  end
end
