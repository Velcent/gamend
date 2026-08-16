defmodule Gamend.Analytics.ActivityDay do
  @moduledoc """
  A user was seen on a UTC day. One row per `(user_id, day)`; written once by
  `Gamend.Analytics.record_activity/2`, never updated.
  """

  use Gamend.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "user_activity_days" do
    belongs_to :user, Gamend.Accounts.User
    field :day, :date

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(activity_day, attrs) do
    activity_day
    |> cast(attrs, [:user_id, :day])
    |> validate_required([:user_id, :day])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :day], name: :user_activity_days_user_id_day_index)
  end
end
