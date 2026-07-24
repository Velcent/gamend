defmodule GameServer.Quests.Quest do
  @moduledoc """
  Ecto schema for the `quests` table — one definition per quest, of any kind.

  ## Kinds

  - `"achievement"` — permanent one-shot (folded-in achievements)
  - `"daily"` / `"weekly"` — repeat per UTC period (`period_key` bucket)
  - `"event"` — time-boxed by `starts_at`/`ends_at`
  - `"chain"` — gated on `prerequisite_quest_key` being completed

  The kind determines the reset cycle; there is no per-row cron.

  ## Fields

  - `key` — unique slug (e.g. "daily_win_3"); progress rows reference it
  - `objectives` — list of `GameServer.Quests.Objective` (event/target/params)
  - `rewards` — list of `GameServer.Quests.Reward`, paid exactly-once
  - `auto_claim` — grant rewards on completion without a claim step
  - `hidden` — not shown until completed (achievements' hidden flag)
  - `active` — inactive quests never advance and are not listed
  """

  use GameServer.Schema
  import Ecto.Changeset
  import GameServer.Limits, only: [validate_metadata_size: 2]

  alias GameServer.Quests.Objective
  alias GameServer.Quests.Reward

  @type t :: %__MODULE__{}

  @kinds ~w(achievement daily weekly event chain)

  @derive {Jason.Encoder,
           only: [
             :id,
             :key,
             :title,
             :description,
             :icon_url,
             :sort_order,
             :hidden,
             :kind,
             :objectives,
             :rewards,
             :auto_claim,
             :prerequisite_quest_key,
             :starts_at,
             :ends_at,
             :active,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  schema "quests" do
    field :key, :string
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :sort_order, :integer, default: 0
    field :hidden, :boolean, default: false
    field :kind, :string

    embeds_many :objectives, Objective, on_replace: :delete
    embeds_many :rewards, Reward, on_replace: :delete

    field :auto_claim, :boolean, default: false
    field :prerequisite_quest_key, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :active, :boolean, default: true
    field :metadata, :map, default: %{}

    has_many :progress, GameServer.Quests.QuestProgress,
      foreign_key: :quest_key,
      references: :key

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(key title kind)a
  @optional_fields ~w(description icon_url sort_order hidden auto_claim
                      prerequisite_quest_key starts_at ends_at active metadata)a

  @doc "The valid quest kinds."
  def kinds, do: @kinds

  @doc false
  def changeset(quest, attrs) do
    quest
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_embed(:objectives, required: true)
    |> cast_embed(:rewards)
    |> validate_required(@required_fields)
    |> validate_length(:key, min: 1, max: GameServer.Limits.get(:max_quest_key))
    |> validate_format(:key, ~r/^[a-z0-9][a-z0-9_-]*$/,
      message: "must be lowercase letters, digits, _ or -"
    )
    |> validate_length(:title, max: GameServer.Limits.get(:max_quest_title))
    |> validate_length(:description, max: GameServer.Limits.get(:max_quest_description))
    |> validate_inclusion(:kind, @kinds)
    |> validate_objective_count()
    |> validate_reward_count()
    |> validate_window()
    |> validate_no_self_prerequisite()
    |> validate_metadata_size(:metadata)
    |> unique_constraint(:key)
  end

  defp validate_objective_count(changeset) do
    max = GameServer.Limits.get(:max_objectives_per_quest)

    validate_change(changeset, :objectives, fn :objectives, objectives ->
      if length(objectives) > max,
        do: [objectives: "cannot have more than #{max} objectives"],
        else: []
    end)
  end

  defp validate_reward_count(changeset) do
    max = GameServer.Limits.get(:max_quest_reward_entries)

    validate_change(changeset, :rewards, fn :rewards, rewards ->
      if length(rewards) > max,
        do: [rewards: "cannot have more than #{max} reward entries"],
        else: []
    end)
  end

  defp validate_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt do
      add_error(changeset, :ends_at, "must be after starts_at")
    else
      changeset
    end
  end

  defp validate_no_self_prerequisite(changeset) do
    key = get_field(changeset, :key)

    if key && get_field(changeset, :prerequisite_quest_key) == key do
      add_error(changeset, :prerequisite_quest_key, "cannot require itself")
    else
      changeset
    end
  end

  @doc """
  Returns the localized title for the given locale.

  Looks up `metadata["titles"][locale]`, falling back to `title`.
  """
  def localized_title(%{metadata: metadata, title: title}, locale) when is_binary(locale) do
    get_in(metadata || %{}, ["titles", locale]) || title
  end

  def localized_title(%{title: title}, _locale), do: title

  @doc """
  Returns the localized description for the given locale.

  Looks up `metadata["descriptions"][locale]`, falling back to `description`.
  """
  def localized_description(%{metadata: metadata, description: desc}, locale)
      when is_binary(locale) do
    get_in(metadata || %{}, ["descriptions", locale]) || desc
  end

  def localized_description(%{description: desc}, _locale), do: desc
end
