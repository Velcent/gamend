defmodule Gamend.Analytics.DailyCount do
  @moduledoc """
  A named counter for one UTC day. Keys are free-form dotted strings owned by
  the game (`"level.finished"`, `"level.started.lang:ja"`); the engine only
  stores and sums them. Written by `Gamend.Analytics.count/3`.
  """

  use Gamend.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @key_max 128

  schema "analytics_daily_counts" do
    field :day, :date
    field :key, :string
    field :count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daily_count, attrs) do
    daily_count
    |> cast(attrs, [:day, :key, :count])
    |> validate_required([:day, :key, :count])
    |> validate_length(:key, min: 1, max: @key_max)
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> unique_constraint([:day, :key], name: :analytics_daily_counts_day_key_index)
  end

  def key_max, do: @key_max
end
