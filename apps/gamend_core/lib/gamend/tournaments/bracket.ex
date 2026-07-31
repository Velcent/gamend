defmodule Gamend.Tournaments.Bracket do
  @moduledoc false

  use Gamend.Schema
  import Ecto.Changeset

  schema "tournament_brackets" do
    belongs_to :tournament, Gamend.Tournaments.Tournament

    field :index, :integer
    field :size, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:tournament_id, :index, :size])
    |> validate_required([:tournament_id, :index, :size])
    |> unique_constraint([:tournament_id, :index])
  end
end
