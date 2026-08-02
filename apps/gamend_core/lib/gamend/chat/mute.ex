defmodule Gamend.Chat.Mute do
  @moduledoc """
  Ecto schema for the `chat_mutes` table — a silenced chat sender.

  `expires_at` is `nil` for a permanent mute; `scope_ref_id` is `nil` for a
  `"global"` mute and required otherwise.

  ## Scopes

    * `"global"` — every chat type, including friend DMs. Admin/plugin only.
    * `"lobby"` / `"group"` / `"party"` — that room only. `scope_ref_id` is the
      lobby, group or party id, and the room's own authority (host, group admin,
      party leader) may set it.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @type t :: %__MODULE__{}

  @scopes ~w(global lobby group party)

  schema "chat_mutes" do
    field :scope, :string, default: "global"
    field :scope_ref_id, Gamend.UUIDv7
    field :expires_at, :utc_datetime
    field :reason, :string

    belongs_to :user, User
    belongs_to :muted_by_user, User, foreign_key: :muted_by

    timestamps(type: :utc_datetime)
  end

  @doc "The scopes a mute may have."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(mute, attrs) do
    mute
    |> cast(attrs, [:user_id, :scope, :scope_ref_id, :expires_at, :reason, :muted_by])
    |> validate_required([:user_id, :scope])
    |> validate_inclusion(:scope, @scopes)
    |> validate_length(:reason, max: Gamend.Limits.get(:max_mute_reason))
    |> validate_scope_ref()
    |> foreign_key_constraint(:user_id)
    # Both names on purpose: Postgres reports the index by its real name, while
    # ecto_sqlite3 reports the default `<table>_<field>_index`.
    |> unique_constraint([:user_id, :scope, :scope_ref_id],
      name: :chat_mutes_user_scope_ref_index
    )
    |> unique_constraint([:user_id, :scope, :scope_ref_id])
    |> unique_constraint([:user_id, :scope], name: :chat_mutes_user_global_index)
  end

  defp validate_scope_ref(changeset) do
    case {get_field(changeset, :scope), get_field(changeset, :scope_ref_id)} do
      {"global", nil} -> changeset
      {"global", _} -> add_error(changeset, :scope_ref_id, "must be nil for a global mute")
      {_, nil} -> add_error(changeset, :scope_ref_id, "is required for a scoped mute")
      _ -> changeset
    end
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.Chat.Mute do
  def encode(mute, opts) do
    Gamend.SchemaJSON.encode(
      mute,
      [
        :id,
        :user_id,
        :scope,
        :scope_ref_id,
        :expires_at,
        :reason,
        :muted_by,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
