defmodule GamendWeb.AdminLive.FriendsTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Repo

  setup %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    requester = AccountsFixtures.user_fixture()
    target = AccountsFixtures.user_fixture()
    {:ok, request} = Friends.create_request(requester.id, target.id)

    %{
      conn: log_in_user(conn, admin),
      requester: requester,
      target: target,
      request: request
    }
  end

  test "lists friendships with requester and target, but not blocks", %{
    conn: conn,
    requester: requester,
    target: target
  } do
    blocker = AccountsFixtures.user_fixture()
    stranger = AccountsFixtures.user_fixture()
    {:ok, _block} = Friends.block_user(blocker, stranger.id)

    {:ok, _lv, html} = live(conn, ~p"/admin/friends")

    assert html =~ requester.id
    assert html =~ target.id
    assert html =~ "pending"
    assert html =~ "Friendships (1)"
    # blocks stay on the Blacklist page
    refute html =~ stranger.id
  end

  test "remove deletes the row and the request stops existing", %{
    conn: conn,
    request: request
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/friends")

    html =
      lv
      |> element("#friendship-#{request.id} button", "Remove")
      |> render_click()

    assert html =~ "Friendship removed"
    assert html =~ "No friendships."
    refute Friends.get_friendship(request.id)
  end

  test "filters by a user on either side of the friendship", %{
    conn: conn,
    requester: requester,
    target: target
  } do
    other = AccountsFixtures.user_fixture()
    stranger = AccountsFixtures.user_fixture()
    {:ok, _} = Friends.create_request(other.id, stranger.id)

    {:ok, lv, _html} = live(conn, ~p"/admin/friends")

    # the target side matches too, not just the requester
    html =
      lv
      |> form("#friends-filter-form", %{"user_id" => target.id})
      |> render_change()

    assert html =~ requester.id
    refute html =~ stranger.id
  end

  test "filters by status", %{conn: conn, requester: requester, target: target} do
    other = AccountsFixtures.user_fixture()
    stranger = AccountsFixtures.user_fixture()
    {:ok, request} = Friends.create_request(other.id, stranger.id)
    {:ok, _} = Friends.accept_friend_request(request.id, stranger)

    {:ok, lv, _html} = live(conn, ~p"/admin/friends")

    html =
      lv
      |> form("#friends-filter-form", %{"status" => "accepted"})
      |> render_change()

    assert html =~ other.id
    refute html =~ requester.id
    refute html =~ target.id
  end
end
