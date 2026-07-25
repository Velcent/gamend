defmodule GameServer.LobbyStateTest do
  use GameServer.DataCase

  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.Lobbies.States

  defp lobby_fixture(attrs \\ %{}) do
    {:ok, lobby} =
      Lobbies.create_lobby(Map.merge(%{title: "L#{System.unique_integer([:positive])}"}, attrs))

    lobby
  end

  describe "states registry" do
    test "core ships a default vocabulary and knows only declared states" do
      assert States.initial() == "created"
      assert States.known?("created")
      assert States.known?("playing")
      assert States.known?("ended")

      refute States.known?("drafting")
      refute States.known?("Playing")
      refute States.known?(nil)
    end

    test "ended is terminal, the rest are not" do
      assert Map.has_key?(States.terminal(), "ended")
      refute Map.has_key?(States.terminal(), "playing")
    end
  end

  describe "create_lobby/1" do
    test "starts in the initial state with a timestamp" do
      lobby = lobby_fixture()

      assert lobby.state == "created"
      assert lobby.state_changed_at
    end
  end

  describe "transition_state/3" do
    test "moves the lobby and stamps state_changed_at" do
      lobby = lobby_fixture()

      assert {:ok, playing} = Lobbies.transition_state(lobby, "playing")
      assert playing.state == "playing"
      assert DateTime.compare(playing.state_changed_at, lobby.state_changed_at) != :lt
    end

    test "rejects a state nobody declared" do
      lobby = lobby_fixture()

      assert {:error, :unknown_state} = Lobbies.transition_state(lobby, "drafting")
      assert {:error, :unknown_state} = Lobbies.transition_state(lobby, "Playing")
      assert Lobbies.get_lobby(lobby.id).state == "created"
    end

    test "is idempotent — a same-state write is a no-op" do
      lobby = lobby_fixture()
      {:ok, playing} = Lobbies.transition_state(lobby, "playing")

      assert {:ok, again} = Lobbies.transition_state(playing, "playing")
      assert again.state_changed_at == playing.state_changed_at
    end

    test "any state may follow any other — core enforces no ordering" do
      lobby = lobby_fixture()

      {:ok, lobby} = Lobbies.transition_state(lobby, "ended")
      # Core does not model a machine; a round-based game may reopen a lobby.
      assert {:ok, lobby} = Lobbies.transition_state(lobby, "created")
      assert lobby.state == "created"
    end

    test "state is not reachable through a generic lobby update" do
      lobby = lobby_fixture()

      {:ok, updated} = Lobbies.update_lobby(lobby, %{"state" => "playing", "title" => "renamed"})

      assert updated.title == "renamed"
      assert updated.state == "created"
    end
  end

  describe "transition_state_by_host/3" do
    test "the host of a host-managed lobby may move it" do
      host = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{host_id: host.id})

      assert {:ok, moved} = Lobbies.transition_state_by_host(host, lobby, "playing")
      assert moved.state == "playing"
    end

    test "a non-host may not" do
      host = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{host_id: host.id})

      assert {:error, :not_host} = Lobbies.transition_state_by_host(other, lobby, "playing")
      assert Lobbies.get_lobby(lobby.id).state == "created"
    end

    test "nobody may move a hostless lobby — matchmaking matches belong to the server" do
      user = AccountsFixtures.user_fixture()
      lobby = lobby_fixture(%{hostless: true})

      assert {:error, :not_host} = Lobbies.transition_state_by_host(user, lobby, "ended")
      assert Lobbies.get_lobby(lobby.id).state == "created"

      # The server itself still can, via the unscoped call.
      assert {:ok, ended} = Lobbies.transition_state(lobby, "ended")
      assert ended.state == "ended"
    end
  end

  describe "listing" do
    test "filters by state" do
      a = lobby_fixture()
      b = lobby_fixture()
      {:ok, _} = Lobbies.transition_state(b, "playing")

      keys = Lobbies.list_lobbies(%{state: "playing"}) |> Enum.map(& &1.id)

      assert b.id in keys
      refute a.id in keys
    end
  end
end
