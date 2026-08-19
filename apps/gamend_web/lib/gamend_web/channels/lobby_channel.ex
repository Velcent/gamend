defmodule GamendWeb.LobbyChannel do
  @moduledoc """
  Channel for lobby realtime events.

  Topic: "lobby:<lobby_id>"

  Users may join this channel either as a **member** (their `lobby_id` matches)
  or as a **spectator** (the lobby is public: not hidden, not locked).

  Spectators receive all events (membership changes, updates, chat) but cannot
  perform any write operations.  A user who is already in a lobby can only join
  their own lobby's channel.

  ## Events pushed to clients

  - `"user_joined"` - A user joined the lobby. Payload: `%{user_id: integer}`
  - `"user_left"` - A user left the lobby. Payload: `%{user_id: integer}`
  - `"user_kicked"` - A user was kicked from the lobby. Payload: `%{user_id: integer}`
  - `"user_online"` - A lobby user came online. Payload: user brief object
  - `"user_offline"` - A lobby user went offline. Payload: user brief object
  - `"user_updated"` - A lobby user was updated. Payload: user brief object
  - `"updated"` - The lobby settings were updated. Payload: lobby object
  - `"host_changed"` - The host changed. Payload: `%{new_host_id: integer}`
  - `"chat_message_created"` - A new chat message. Payload: chat message object
  - `"chat_message_updated"` - A chat message was updated. Payload: chat message object
  - `"chat_message_deleted"` - A chat message was deleted. Payload: `%{id: integer}`
  """

  use Phoenix.Channel

  import GamendWeb.ChannelPush

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Chat
  alias Gamend.Lobbies
  alias Gamend.Lobbies.SpectatorTracker
  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Plugs.ClientSession
  alias GamendWeb.Serializers

  require Logger

  @impl true
  def join("lobby:" <> lobby_id_str, _payload, socket) do
    # This channel runs in its own process, so it stamps its own metadata;
    # the socket's connect-time call does not reach here.
    ClientSession.put_metadata(socket.assigns[:client_session_id])

    current_scope = Map.get(socket.assigns, :current_scope)

    with {:ok, lobby_id} <- Ecto.UUID.cast(lobby_id_str),
         %Scope{user_id: user_id} <- current_scope,
         %Gamend.Lobbies.Lobby{} = lobby <- Lobbies.get_lobby(lobby_id) do
      user = Accounts.get_user(user_id)

      cond do
        # Case 1: user is a member of this lobby → join as member
        match?(%User{lobby_id: ^lobby_id}, user) ->
          GamendWeb.ConnectionTracker.register(:lobby_channel, %{
            lobby_id: lobby_id,
            user_id: user_id
          })

          Chat.subscribe_lobby_chat(lobby_id)
          send(self(), {:after_join, lobby})
          {:ok, socket |> assign(:lobby_id, lobby_id) |> assign(:spectator, false)}

        # Case 2: user is in a *different* lobby → reject (must listen to their own)
        is_struct(user, User) and is_binary(user.lobby_id) ->
          {:error, %{reason: "must_spectate_own_lobby"}}

        # Case 3: user is not in any lobby and lobby is spectatable → join as spectator
        Lobbies.spectatable?(lobby) ->
          GamendWeb.ConnectionTracker.register(:lobby_channel, %{
            lobby_id: lobby_id,
            user_id: user_id,
            spectator: true
          })

          Chat.subscribe_lobby_chat(lobby_id)
          SpectatorTracker.track(lobby_id, user_id)
          send(self(), {:after_join, lobby})
          {:ok, socket |> assign(:lobby_id, lobby_id) |> assign(:spectator, true)}

        # Case 4: lobby is hidden or locked → reject
        true ->
          {:error, %{reason: "not_spectatable"}}
      end
    else
      _ ->
        {:error, %{reason: "invalid_topic_or_unauthenticated"}}
    end
  end

  # The channel twin of `GET /api/v1/time`. A connected client should not have
  # to fall back to HTTP to resynchronise its clock.
  @impl true
  def handle_in("get_server_time", _payload, socket) do
    {:reply, {:ok, %{server_now: Gamend.Time.now_ms()}}, socket}
  end

  # Answer and stay up. This used to be `{:stop, :normal, ...}`, which killed the
  # channel over a single event the server did not recognise — and this is the
  # channel a player's word data rides on, so the cost of one stray push was the
  # rest of the session going quiet. A client that pushes something we do not
  # know is a client to answer, not to hang up on.
  def handle_in(event, _payload, socket) do
    Logger.warning(
      "LobbyChannel: unknown event=#{event} lobby=#{socket.assigns[:lobby_id] || "nil"}"
    )

    {:reply, {:error, %{error: "unknown_event"}}, socket}
  end

  # Handle PubSub messages and forward them to WebSocket clients

  @impl true
  def handle_info({:user_joined, _lobby_id, user_id}, socket) do
    user = Accounts.get_user(user_id)

    payload =
      if user do
        User.serialize_brief(user) |> Map.put(:user_id, user_id)
      else
        %{user_id: user_id, display_name: ""}
      end

    push_event(socket, "user_joined", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_left, _lobby_id, user_id}, socket) do
    push_event(socket, "user_left", %{
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_kicked, _lobby_id, user_id}, socket) do
    push_event(socket, "user_kicked", %{
      user_id: user_id,
      display_name: Serializers.display_name(user_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:lobby_updated, lobby}, socket) do
    payload = Serializers.serialize_lobby(lobby, include_members: true)
    {:noreply, ChannelUpdates.push(socket, "updated", :lobby, payload)}
  end

  @impl true
  def handle_info({:lobby_state_changed, payload}, socket) do
    push_event(socket, "state_changed", payload)
    {:noreply, socket}
  end

  # A burst of members readying at once coalesces into one frame; a resolution
  # is not a state refresh, so it is never held in the debounce timer.
  @impl true
  def handle_info({:ready_check_event, "ready_check_updated" = event, check}, socket) do
    payload = serialize_ready_check(check, socket)
    {:noreply, ChannelUpdates.push(socket, event, check.id, payload)}
  end

  @impl true
  def handle_info({:ready_check_event, event, check}, socket) do
    push_event(socket, event, serialize_ready_check(check, socket))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:host_changed, _lobby_id, new_host_id}, socket) do
    push_event(socket, "host_changed", %{
      new_host_id: new_host_id,
      display_name: Serializers.display_name(new_host_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:after_join, lobby}, socket) do
    payload =
      lobby
      |> Serializers.serialize_lobby(include_members: true)
      |> Map.put(:spectator, socket.assigns[:spectator] || false)

    push_event(socket, "updated", payload)
    {:noreply, ChannelUpdates.remember(socket, "updated", :lobby, payload)}
  end

  @impl true
  def handle_info({:chat_message_created, message}, socket) do
    push_event(socket, "chat_message_created", Serializers.serialize_chat_message(message))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message_updated, message}, socket) do
    push_event(socket, "chat_message_updated", Serializers.serialize_chat_message(message))
    {:noreply, socket}
  end

  @impl true
  def handle_info({:chat_message_deleted, message}, socket) do
    push_event(socket, "chat_message_deleted", %{id: message.id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({event, user_id}, socket) when event in [:member_online, :member_offline] do
    user = Accounts.get_user(user_id)
    # Internal atom is shared with group/party; on the lobby topic occupants are
    # "users", so the wire event is user_online/user_offline.
    ws_event = if event == :member_online, do: "user_online", else: "user_offline"

    payload =
      if user do
        User.serialize_brief(user) |> Map.put(:user_id, user_id)
      else
        %{user_id: user_id, display_name: "", is_online: event == :member_online}
      end

    push_event(socket, ws_event, payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:member_updated, user_id}, socket) do
    user = Accounts.get_user(user_id)

    if user do
      payload = User.serialize_brief(user) |> Map.put(:user_id, user_id)
      {:noreply, ChannelUpdates.push(socket, "user_updated", user_id, payload)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:channel_updates_flush, _}, socket),
    do: {:noreply, ChannelUpdates.flush(socket)}

  # Ignore other messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp serialize_ready_check(check, socket) do
    viewer_id = get_in(socket.assigns, [:current_scope, Access.key(:user_id)])
    Serializers.serialize_ready_check(check, viewer_id: viewer_id)
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{lobby_id: lobby_id, spectator: true, current_scope: %{user_id: user_id}}
      when is_binary(lobby_id) ->
        SpectatorTracker.untrack(lobby_id, user_id)
        _ = Chat.unsubscribe_lobby_chat(lobby_id)
        :ok

      %{lobby_id: lobby_id} when is_binary(lobby_id) ->
        _ = Chat.unsubscribe_lobby_chat(lobby_id)
        :ok

      _ ->
        :ok
    end
  end
end
