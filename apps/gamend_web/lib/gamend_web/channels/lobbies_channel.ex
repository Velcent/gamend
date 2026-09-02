defmodule GamendWeb.LobbiesChannel do
  @moduledoc """
  Channel for broadcasting global lobby list events.

  Topic: "lobbies"

  Clients may join this topic to receive real-time notifications when lobbies
  are created/updated/deleted or when membership changes occur across lobbies.
  """

  use Phoenix.Channel

  import GamendWeb.ChannelPush

  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Plugs.FeatureGate
  alias GamendWeb.Serializers

  require Logger

  @impl true
  def join("lobbies", _payload, socket) do
    # Same flag as GET /api/v1/lobbies — the feed must not outlive the API.
    if FeatureGate.enabled?(:list_lobbies) do
      GamendWeb.ConnectionTracker.register(:lobbies_channel)
      {:ok, socket}
    else
      {:error, %{reason: "listing_disabled"}}
    end
  end

  @impl true
  # Answer and stay up — see LobbyChannel: stopping the channel over one
  # unrecognised event took every broadcast it carried with it, and a client
  # cannot tell a dead channel from a quiet one.
  def handle_in(event, _payload, socket) do
    Logger.debug(fn -> "LobbiesChannel: unknown event=#{truncate_event(event)}" end)

    {:reply, {:error, %{error: "unknown_event"}}, socket}
  end

  @impl true
  def handle_info({:lobby_created, lobby}, socket) do
    payload = Serializers.serialize_lobby(lobby, include_passworded: true)
    push_event(socket, "lobby_created", payload)
    # The create doubles as the first update; remembering it suppresses an
    # identical lobby_updated immediately afterwards.
    {:noreply, ChannelUpdates.remember(socket, "lobby_updated", payload.id, payload)}
  end

  @impl true
  def handle_info({:lobby_updated, lobby}, socket) do
    payload = Serializers.serialize_lobby(lobby, include_passworded: true)
    {:noreply, ChannelUpdates.push(socket, "lobby_updated", payload.id, payload)}
  end

  @impl true
  def handle_info({:lobby_deleted, lobby_id}, socket) do
    push_event(socket, "lobby_deleted", %{id: lobby_id})
    # Prune, so a long-lived list socket doesn't accumulate an entry for every
    # lobby it has ever seen.
    {:noreply, ChannelUpdates.forget(socket, "lobby_updated", lobby_id)}
  end

  @impl true
  def handle_info({:lobby_membership_changed, lobby_id}, socket) do
    push_event(socket, "lobby_membership_changed", %{id: lobby_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:channel_updates_flush, _}, socket),
    do: {:noreply, ChannelUpdates.flush(socket)}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
  # Unknown events are logged at debug with the name truncated, and the name is
  # never interpolated at warning level.
  #
  # Every other `handle_in/3` here rate-limits first; this catch-all did not,
  # and it put a client-chosen string into a warning line. A frame allows a
  # 128 KB event name, so one socket could drive unbounded warning-level volume
  # made of attacker-controlled text into the rotating log and the admin buffer.
  # Client-chosen, so never logged whole.
  defp truncate_event(event) when is_binary(event),
    do: binary_part(event, 0, min(byte_size(event), 64))

  defp truncate_event(event), do: inspect(event)
end
