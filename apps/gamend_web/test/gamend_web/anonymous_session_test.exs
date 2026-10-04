defmodule GamendWeb.AnonymousSessionTest do
  @moduledoc """
  The website's anonymous accounts: made on demand (`UserAuth.ensure_user/1`,
  `ensure_user_conn/1`) as device accounts, handed to the browser through
  `POST /users/anonymous_session`, and only while device accounts are on.
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias GamendWeb.UserAuth

  setup do
    previous = Application.get_env(:gamend_core, Gamend.Accounts, [])

    Application.put_env(
      :gamend_core,
      Gamend.Accounts,
      Keyword.put(previous, :device_auth_enabled, true)
    )

    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, previous) end)
    :ok
  end

  defp connected_socket(scope \\ nil) do
    %Phoenix.LiveView.Socket{
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_scope: scope, flash: %{}}
    }
  end

  defp pushed_token(socket) do
    [[event, %{token: token}]] = Phoenix.LiveView.Utils.get_push_events(socket)
    assert event == "gamend:anonymous_session"
    token
  end

  describe "ensure_user/1 on a live page" do
    test "counts new accounts per IP, in the bucket registering uses" do
      # It runs over the socket, which the HTTP rate limiter never sees.
      limit = Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, :auth_limit)

      from = fn ip ->
        %{connected_socket() | assigns: Map.put(connected_socket().assigns, :client_ip, ip)}
      end

      for _ <- 1..limit, do: assert({:ok, _} = UserAuth.ensure_user(from.("198.51.100.7")))

      assert {:error, :rate_limited} = UserAuth.ensure_user(from.("198.51.100.7"))
      assert {:ok, _} = UserAuth.ensure_user(from.("198.51.100.8"))
    end

    test "a signed-out page records the IP its new accounts count against", %{conn: conn} do
      # Read at mount (the page's signed session), since a LiveView's connect
      # info is gone by the time an event asks for an account.
      {:ok, view, _html} = Phoenix.LiveViewTest.live(conn, ~p"/leaderboards")
      assert %{socket: %{assigns: %{client_ip: "127.0.0.1"}}} = :sys.get_state(view.pid)

      user = Gamend.AccountsFixtures.user_fixture()

      {:ok, view, _html} =
        conn |> log_in_user(user) |> Phoenix.LiveViewTest.live(~p"/leaderboards")

      refute Map.has_key?(:sys.get_state(view.pid).socket.assigns, :client_ip)
    end

    test "a signed-out visitor gets an anonymous account and the browser is sent its session" do
      assert {:ok, socket} = UserAuth.ensure_user(connected_socket())

      user = Scope.user(socket.assigns.current_scope)
      assert %User{} = user
      assert User.anonymous?(user)
      assert "web:" <> _ = user.device_id
      assert is_binary(pushed_token(socket))
    end

    test "a signed-in caller is left as they are" do
      user = Gamend.AccountsFixtures.user_fixture()
      socket = connected_socket(Scope.for_user(user))

      assert {:ok, ^socket} = UserAuth.ensure_user(socket)
    end

    test "the static render makes nothing: there is no browser to hand it to yet" do
      socket = %{connected_socket() | transport_pid: nil}
      assert {:error, :not_connected} = UserAuth.ensure_user(socket)
    end

    test "nothing while device accounts are off" do
      Application.put_env(:gamend_core, Gamend.Accounts, device_auth_enabled: false)
      count = Gamend.Repo.aggregate(User, :count, :id)

      assert {:error, :disabled} = UserAuth.ensure_user(connected_socket())
      assert Gamend.Repo.aggregate(User, :count, :id) == count
    end
  end

  describe "POST /users/anonymous_session" do
    test "stamps the account into the session, so the next page is signed in", %{conn: conn} do
      {:ok, socket} = UserAuth.ensure_user(connected_socket())
      user = Scope.user(socket.assigns.current_scope)

      conn = post(conn, ~p"/users/anonymous_session", %{token: pushed_token(socket)})
      assert response(conn, 204)
      assert conn.resp_cookies["_gamend_web_user_remember_me"]

      conn = conn |> recycle() |> get(~p"/")
      assert Scope.user_id(conn.assigns.current_scope) == user.id
    end

    test "refuses a token it did not make", %{conn: conn} do
      conn = post(conn, ~p"/users/anonymous_session", %{token: "nope"})
      assert response(conn, 422)
      assert post(build_conn(), ~p"/users/anonymous_session", %{}) |> response(422)
    end

    test "never replaces a real account the browser is signed in with", %{conn: conn} do
      real = Gamend.AccountsFixtures.user_fixture()
      {:ok, socket} = UserAuth.ensure_user(connected_socket())

      conn =
        conn
        |> log_in_user(real)
        |> post(~p"/users/anonymous_session", %{token: pushed_token(socket)})

      assert response(conn, 204)
      conn = conn |> recycle() |> get(~p"/")
      assert Scope.user_id(conn.assigns.current_scope) == real.id
    end
  end

  describe "ensure_user_conn/1 in a controller" do
    test "writes the new account straight into the session", %{conn: conn} do
      conn =
        %{conn | secret_key_base: GamendWeb.endpoint().config(:secret_key_base)}
        |> init_test_session(%{})
        |> assign(:current_scope, nil)

      assert {:ok, conn} = UserAuth.ensure_user_conn(conn)
      user = Scope.user(conn.assigns.current_scope)
      assert User.anonymous?(user)
      assert get_session(conn, :user_token)
    end
  end

  defp session_conn(scope) do
    build_conn()
    |> Map.replace!(:secret_key_base, GamendWeb.endpoint().config(:secret_key_base))
    |> init_test_session(%{})
    |> fetch_flash()
    |> assign(:current_scope, scope)
  end

  defp guest do
    {:ok, socket} = UserAuth.ensure_user(connected_socket())
    Scope.user(socket.assigns.current_scope)
  end

  describe "a guest who signs up" do
    test "gets the email on the account they already have, so it keeps everything" do
      guest = guest()

      assert {:ok, upgraded} =
               Accounts.upgrade_anonymous_user_and_deliver(
                 guest,
                 %{"email" => "guest@example.com"},
                 &"/confirm/#{&1}"
               )

      assert upgraded.id == guest.id
      assert upgraded.email == "guest@example.com"
      refute User.anonymous?(upgraded)
    end

    test "cannot take an email another account has: they log in to that one instead" do
      Gamend.AccountsFixtures.user_fixture(%{email: "taken@example.com"})

      assert {:error, %Ecto.Changeset{}} =
               Accounts.upgrade_anonymous_user_and_deliver(
                 guest(),
                 %{"email" => "taken@example.com"},
                 &"/confirm/#{&1}"
               )
    end

    test "an account that is not a guest's is never upgraded" do
      user = Gamend.AccountsFixtures.user_fixture()

      assert {:error, :not_anonymous} =
               Accounts.upgrade_anonymous_user_and_deliver(
                 user,
                 %{"email" => "x@example.com"},
                 & &1
               )
    end
  end

  describe "a guest who logs in to an account they already have" do
    test "is signed in to it as it is, and the guest account is deleted" do
      guest = guest()
      existing = Gamend.AccountsFixtures.user_fixture()

      conn = guest |> Scope.for_user() |> session_conn() |> UserAuth.log_in_user(existing)

      assert get_session(conn, :user_token)
      assert Accounts.get_user(guest.id) == nil
      assert %User{} = Accounts.get_user(existing.id)
    end

    test "a real account signing in to another never deletes the first" do
      first = Gamend.AccountsFixtures.user_fixture()
      second = Gamend.AccountsFixtures.user_fixture()

      first |> Scope.for_user() |> session_conn() |> UserAuth.log_in_user(second)

      assert %User{} = Accounts.get_user(first.id)
    end
  end

  describe "require_registered_user/2" do
    test "lets a real account through, sends a guest to register and a visitor to log in" do
      real = Gamend.AccountsFixtures.user_fixture()
      conn = real |> Scope.for_user() |> session_conn() |> UserAuth.require_registered_user([])
      refute conn.halted

      conn = guest() |> Scope.for_user() |> session_conn() |> UserAuth.require_registered_user([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/users/register"

      conn = nil |> session_conn() |> UserAuth.require_registered_user([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
