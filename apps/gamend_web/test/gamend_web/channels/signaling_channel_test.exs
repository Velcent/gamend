defmodule GamendWeb.SignalingChannelTest do
  @moduledoc """
  Presence translation on the signaling channel.

  Presence diffs are broadcast on the channel's own topic, so they reach
  `handle_out/3` (via `intercept`), not `handle_info/2`. Getting that wrong is
  invisible from the server side — the channel keeps working, it just stops
  translating, or translates twice — so these assert on what peers receive.
  """
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Signaling
  alias GamendWeb.Auth.Guardian

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)

    host = AccountsFixtures.user_fixture()
    peer = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{"title" => "Signaling", "host_id" => host.id})

    {:ok, lobby} =
      Signaling.configure(lobby, enabled: true, topology: :mesh, reconnect_timeout: 0)

    %{lobby: lobby, host: host, peer: peer}
  end

  defp join_signaling(user, lobby_id) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    subscribe_and_join(socket, "signaling:#{lobby_id}", %{})
  end

  # Every socket in this test shares the test process mailbox, so the pushes are
  # counted rather than matched in order.
  defp pushed_ids(event) do
    {:messages, messages} = :erlang.process_info(self(), :messages)

    for %Phoenix.Socket.Message{event: ^event, payload: payload} <- messages,
        do: payload.user_id
  end

  test "a peer is announced exactly once to everyone already in the room", %{
    lobby: lobby,
    host: host,
    peer: peer
  } do
    {:ok, _reply, _socket} = join_signaling(host, lobby.id)
    Process.sleep(200)
    assert pushed_ids("user_joined") == []

    {:ok, _reply, _socket} = join_signaling(peer, lobby.id)
    Process.sleep(300)

    ids = pushed_ids("user_joined")

    # The presence diff the host sees. Two would mean the channel is subscribed
    # to its own topic twice.
    assert Enum.count(ids, &(&1 == peer.id)) == 1
    # The seed the newcomer gets for whoever was already there.
    assert Enum.count(ids, &(&1 == host.id)) == 1
  end

  test "a leave is announced exactly once", %{lobby: lobby, host: host, peer: peer} do
    {:ok, _reply, _socket} = join_signaling(host, lobby.id)
    Process.sleep(200)

    {:ok, _reply, peer_socket} = join_signaling(peer, lobby.id)
    Process.sleep(300)

    # subscribe_and_join links the channel to the test process, and leaving
    # stops it with {:shutdown, :left}.
    Process.unlink(peer_socket.channel_pid)
    leave(peer_socket)
    Process.sleep(300)

    assert pushed_ids("user_left") == [peer.id]
  end
end
