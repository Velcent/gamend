defmodule Gamend.Repo.Migrations.AddIconUrl do
  use Ecto.Migration

  # Quests already carry icon_url; this brings the other icon-bearing entities
  # level. Nullable on purpose: the web UI falls back to a text-derived
  # heroicon (GamendWeb.Icons), so no backfill is needed.
  def change do
    alter table(:tournaments) do
      add :icon_url, :string
    end

    alter table(:groups) do
      add :icon_url, :string
    end

    alter table(:leaderboards) do
      add :icon_url, :string
    end
  end
end
