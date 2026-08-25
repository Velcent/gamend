defmodule Gamend.Repo.Migrations.WidenAvatarUrlColumns do
  use Ecto.Migration

  # These columns were declared `add :*, :string`, which Ecto renders as
  # varchar(255) on Postgres. They hold URLs the *provider* controls — a Google
  # `picture` can run well past that — and max_profile_url now allows 2048, so
  # without this a URL between 256 and 2048 would clear the changeset and then
  # blow up at insert with "value too long for type character varying(255)".
  #
  # SQLite stores :string and :text identically (TEXT, no length ceiling), which
  # is why the bug never showed there and why it has nothing to do here. It also
  # cannot ALTER COLUMN at all, so branching on the adapter is required, not
  # just an optimisation — see AddLabelToLeaderboardRecords for the same split.
  @columns [
    {:users, :profile_url},
    {:groups, :icon_url},
    {:leaderboards, :icon_url},
    {:tournaments, :icon_url},
    {:notifications, :icon_url},
    {:quests, :icon_url}
  ]

  def up, do: change_type(:text)

  # Narrowing back only succeeds while every stored value still fits in 255;
  # Postgres raises rather than truncating, which is the safe direction to fail.
  def down, do: change_type(:string)

  defp change_type(type) do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      for {table, column} <- @columns do
        alter table(table) do
          modify column, type
        end
      end
    end
  end
end
