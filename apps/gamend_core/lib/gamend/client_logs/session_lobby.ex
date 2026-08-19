defmodule Gamend.ClientLogs.SessionLobby do
  @moduledoc """
  A lobby a client session was in.

  Written once per (session, lobby) pair with `on_conflict: :nothing`, so
  repeated batches from the same run cost an ignored insert rather than a
  read-modify-write that two nodes could race.

  Keyed by `client_session_id` (the client-generated string) rather than by the
  session row's id, so a batch can record its lobbies without first resolving
  the row. See the migration for why this is a table and not an array column.
  """

  use Gamend.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "client_session_lobbies" do
    field :client_session_id, :string
    field :lobby_id, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(session_lobby, attrs) do
    session_lobby
    |> cast(attrs, [:client_session_id, :lobby_id])
    |> validate_required([:client_session_id, :lobby_id])
    |> validate_length(:client_session_id, min: 8, max: 128)
    |> validate_length(:lobby_id, min: 1, max: 128)
    |> unique_constraint([:client_session_id, :lobby_id])
  end
end
