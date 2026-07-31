defmodule Gamend.Repo.Migrations.AddLobbyWebrtcColumns do
  use Ecto.Migration

  # Signaling configuration used to live in `lobbies.metadata`, which is a
  # single shared map that any writer replaces wholesale and that the lobby host
  # can PATCH. Both were problems: a game writing its match state wiped the
  # config, and a host could flip the topology to remove the star rule that only
  # they may broadcast.
  #
  # These columns are server-owned and not castable, like `state`.
  def change do
    alter table(:lobbies) do
      add :webrtc_enabled, :boolean, null: false, default: false
      add :webrtc_topology, :string
      add :webrtc_late_join, :boolean, null: false, default: true
      add :webrtc_reconnect_timeout_ms, :integer, null: false, default: 30_000
    end
  end
end
