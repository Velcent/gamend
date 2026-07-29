defmodule GameServer.Modules.WebRTCLobbyHook do
  @moduledoc """
  Keeps a WebRTC signaling room in sync with a lobby.

  This is the only module that connects the lobby system to the WebRTC
  signaling layer. When a lobby has `metadata.webrtc.enabled = true`, a
  signaling room with the same id as the lobby is created automatically.
  The room is closed when the lobby is deleted, and the allowed-user list
  is kept in sync with lobby joins and leaves.

  When a star-topology room is created, the designated host is notified on
  its user channel (`user:<host_user_id>`) with a `webrtc:room_ready` event
  so a headless server can connect automatically.

  Configuration is read from `lobby.metadata.webrtc`:

      %{
        "enabled" => true,
        "topology" => "star" | "mesh",
        "late_join" => true,
        "reconnect_timeout" => 30_000,
        "host_user_id" => "optional-server-user-id"
      }

  In `:star` mode the host is resolved in this order:
    1. `metadata.webrtc.host_user_id`
    2. `lobby.host_id`

  The allowed-user list is seeded from the lobby members at creation time.
  Late joiners are added via `after_lobby_join/2`.
  """

  use GameServer.Hooks

  require Logger

  alias GameServer.Realtime
  alias GameServer.Signaling

  @room_ready_event "webrtc:room_ready"

  @doc """
  Realtime events this plugin pushes with `GameServer.Realtime.push_to_user/3`.
  """
  def realtime_events do
    %{
      @room_ready_event => "A signaling room is ready; the star host should connect to it."
    }
  end

  # Star for every lobby. Written here rather than injected into the create
  # attrs, because the `webrtc_*` columns are deliberately not castable.
  @impl true
  def after_lobby_create(lobby) do
    with {:ok, configured} <- Signaling.configure(lobby, enabled: true, topology: :star) do
      ensure_room(configured)
    end

    :ok
  end

  @impl true
  def after_lobby_updated(lobby) do
    # If WebRTC is enabled later, create the room. If disabled, close it.
    ensure_room(lobby)
  end

  @impl true
  def after_lobby_deleted(lobby) do
    Logger.info("WebRTC: closing signaling room for deleted lobby=#{lobby.id}")
    Signaling.close(lobby.id)
  end

  @impl true
  def after_lobby_host_change(lobby, new_host_id) do
    # Nothing to mirror: `Signaling.config/1` reads the host off the lobby, so
    # the next join already sees the new one. The notification is the only
    # side effect a headless host still needs.
    case Signaling.config(lobby.id) do
      {:ok, %{topology: :star}} ->
        Logger.info("WebRTC: star host changed lobby=#{lobby.id} host=#{new_host_id}")
        notify_host_ready(lobby.id, :star, new_host_id)

      _mesh_or_disabled ->
        :ok
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  # There is no room to create — `GameServer.Signaling` derives everything from
  # the lobby. All that is left is telling a star host it can connect.
  defp ensure_room(lobby) do
    case Signaling.config(lobby.id) do
      {:ok, %{topology: :star, host_user_id: host_user_id}} when is_binary(host_user_id) ->
        notify_host_ready(lobby.id, :star, host_user_id)

      {:ok, _mesh} ->
        :ok

      # WebRTC was turned off on a live lobby. Peers stay connected and tracked
      # otherwise, unable to relay anything and never told why.
      {:error, :room_not_found} ->
        Signaling.close(lobby.id)
    end
  end

  # Broadcasts a notification to the host's user channel so the headless
  # server can connect to the signaling room automatically.
  defp notify_host_ready(lobby_id, topology, host_user_id) do
    Logger.info("WebRTC: notifying host user=#{host_user_id} of ready room=#{lobby_id}")

    Realtime.push_to_user(host_user_id, @room_ready_event, %{
      "lobby_id" => lobby_id,
      "topology" => to_string(topology),
      "host_user_id" => host_user_id,
      "signaling_topic" => "signaling:#{lobby_id}"
    })

    Logger.info("WebRTC: notifying host=#{host_user_id} about signaling room lobby=#{lobby_id}")
  end
end
