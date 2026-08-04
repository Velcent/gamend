defmodule Gamend.Repo.Migrations.AddLobbyWebrtcHostId do
  @moduledoc """
  Adds `webrtc_host_id` so the WebRTC signaling host can be set independently
  from the lobby host. If `null`, Signaling falls back to `lobby.host_id`.
  """

  use Ecto.Migration

  def change do
    alter table(:lobbies) do
      add :webrtc_host_id, references(:users, on_delete: :nilify_all)
    end

    # `on_delete: :nilify_all` scans this column on every user deletion.
    create index(:lobbies, [:webrtc_host_id])
  end
end
