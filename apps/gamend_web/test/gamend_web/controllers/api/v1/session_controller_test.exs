defmodule GamendWeb.Api.V1.SessionControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.Repo

  @valid_email "testuser@example.com"
  @valid_password "hello world!"

  setup do
    # Create a user with email and hashed password directly
    # This mimics what would happen after email/password registration
    hashed_password = Bcrypt.hash_pwd_salt(@valid_password)

    user = %User{
      email: @valid_email,
      username: "testuser",
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now(:second)
    }

    {:ok, user} = Repo.insert(user)
    %{user: user}
  end

  describe "POST /api/v1/login" do
    test "returns access and refresh tokens on successful login", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => access_token,
                 "refresh_token" => refresh_token,
                 "expires_in" => 900,
                 "user_id" => user_id,
                 "display_name" => _display_name
               }
             } = resp

      assert user_id == user.id

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert access_token != refresh_token
    end

    test "returns 401 with invalid credentials", %{conn: conn} do
      conn =
        post(conn, "/api/v1/login", %{
          email: "wrong@example.com",
          password: "wrongpassword"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "device login creates and returns tokens", %{conn: conn} do
      device_id = "device:#{System.unique_integer([:positive])}"

      conn = post(conn, "/api/v1/login/device", %{device_id: device_id})

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => access_token,
                 "refresh_token" => refresh_token,
                 "expires_in" => 900,
                 "user_id" => device_user_id,
                 "display_name" => _display_name
               }
             } = resp

      assert is_binary(device_user_id) and device_user_id != ""

      assert is_binary(access_token)
      assert is_binary(refresh_token)

      # ensure user record was created and has device_id set
      assert %Gamend.Accounts.User{device_id: ^device_id} =
               Gamend.Repo.get_by(Gamend.Accounts.User, device_id: device_id)
    end

    test "device login returns existing user tokens", %{conn: conn} do
      # Create a user pre-attached to device_id
      device_id = "device_pre_#{System.unique_integer([:positive])}"

      {:ok, user} =
        Gamend.Accounts.register_user(%{
          email: "devuser#{System.unique_integer([:positive])}@example.com",
          password: "longenoughpass"
        })

      # Registration ignores a submitted `device_id` on purpose; attaching one is
      # an authenticated action.
      {:ok, user} = Gamend.Accounts.link_device_id(user, device_id)

      assert user.device_id == device_id

      conn = post(conn, "/api/v1/login/device", %{device_id: device_id})

      resp = json_response(conn, 200)
      assert %{"data" => %{"access_token" => access_token, "user_id" => returned_id}} = resp
      assert returned_id == user.id

      assert is_binary(access_token)
    end
  end

  describe "POST /api/v1/refresh" do
    test "returns new access token with valid refresh token", %{conn: conn, user: user} do
      # Login to get tokens
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"refresh_token" => refresh_token}} = json_response(conn, 200)

      # Use refresh token to get new access token
      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: refresh_token})

      resp = json_response(conn, 200)

      assert %{
               "data" => %{
                 "access_token" => new_access_token,
                 "refresh_token" => returned_refresh_token,
                 "user_id" => user_id,
                 "expires_in" => 900,
                 "display_name" => _display_name
               }
             } = resp

      assert is_binary(new_access_token)
      assert returned_refresh_token == refresh_token
      assert user_id == user.id
    end

    test "returns 401 with invalid refresh token", %{conn: conn} do
      conn = post(conn, "/api/v1/refresh", %{refresh_token: "invalid.token.here"})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns 401 when using access token instead of refresh token", %{conn: conn} do
      # Login to get tokens
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"access_token" => access_token}} = json_response(conn, 200)

      # Try to use access token for refresh (should fail)
      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: access_token})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns 400 when refresh_token is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/refresh", %{})

      assert %{"error" => "missing_param"} = json_response(conn, 400)
    end

    test "returns 401 after a password change revokes the refresh token", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"refresh_token" => refresh_token}} = json_response(conn, 200)

      {:ok, {_user, _tokens}} =
        Gamend.Accounts.update_user_password(user, %{password: "brand new password!"})

      conn = build_conn()
      conn = post(conn, "/api/v1/refresh", %{refresh_token: refresh_token})

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "access token stops working after revoke_all_tokens/1", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/v1/login", %{
          email: @valid_email,
          password: @valid_password
        })

      %{"data" => %{"access_token" => access_token}} = json_response(conn, 200)

      authed = fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> get("/api/v1/me")
      end

      assert json_response(authed.(), 200)

      {:ok, {_user, _tokens}} = Gamend.Accounts.revoke_all_tokens(user)

      assert json_response(authed.(), 401)
    end
  end

  defp put_accounts_setting(key, value) do
    existing = Application.get_env(:gamend_core, Gamend.Accounts, [])
    Application.put_env(:gamend_core, Gamend.Accounts, Keyword.put(existing, key, value))
  end

  defmodule FailNotifier do
    def deliver_confirmation_instructions(_user, _url), do: {:error, :smtp_failed}
  end

  describe "POST /api/v1/register" do
    setup do
      accounts = Application.get_env(:gamend_core, Gamend.Accounts, [])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, accounts) end)
      :ok
    end

    test "creates an account and signs it in, and its password logs in", %{conn: conn} do
      created =
        post(conn, "/api/v1/register", %{email: "new@example.com", password: @valid_password})

      assert %{"data" => %{"access_token" => token, "user_id" => user_id}} =
               json_response(created, 201)

      assert is_binary(token)

      login =
        post(build_conn(), "/api/v1/login", %{
          email: "new@example.com",
          password: @valid_password
        })

      assert json_response(login, 200)["data"]["user_id"] == user_id
    end

    test "sends the confirmation email, as browser sign-up does", %{conn: conn} do
      post(conn, "/api/v1/register", %{email: "mailed@example.com", password: @valid_password})

      Swoosh.TestAssertions.assert_email_sent(
        to: "mailed@example.com",
        subject: "Confirmation instructions"
      )
    end

    test "keeps no account when its email cannot be sent", %{conn: conn} do
      notifier = Application.get_env(:gamend_web, :user_notifier)
      Application.put_env(:gamend_web, :user_notifier, __MODULE__.FailNotifier)

      on_exit(fn ->
        if notifier,
          do: Application.put_env(:gamend_web, :user_notifier, notifier),
          else: Application.delete_env(:gamend_web, :user_notifier)
      end)

      failed =
        post(conn, "/api/v1/register", %{email: "bounced@example.com", password: @valid_password})

      assert json_response(failed, 503)["error"] == "email_delivery_failed"
      refute Repo.get_by(User, email: "bounced@example.com")
    end

    test "keeps a username the caller picked", %{conn: conn} do
      created =
        post(conn, "/api/v1/register", %{
          email: "named@example.com",
          password: @valid_password,
          username: "quail"
        })

      assert json_response(created, 201)["data"]["username"] == "quail"
    end

    test "answers 409 for an email already taken", %{conn: conn} do
      taken = post(conn, "/api/v1/register", %{email: @valid_email, password: @valid_password})

      assert %{"error" => "validation_failed", "errors" => %{"email" => _}} =
               json_response(taken, 409)
    end

    test "answers 422 for a password too short", %{conn: conn} do
      short = post(conn, "/api/v1/register", %{email: "short@example.com", password: "x"})

      assert %{"errors" => %{"password" => _}} = json_response(short, 422)
    end

    test "answers 400 without a password", %{conn: conn} do
      missing = post(conn, "/api/v1/register", %{email: "nopass@example.com"})

      assert json_response(missing, 400)["error"] == "missing_param"
    end

    test "keeps an account awaiting activation but signs nobody in", %{conn: conn} do
      put_accounts_setting(:require_activation, true)

      pending =
        post(conn, "/api/v1/register", %{email: "beta@example.com", password: @valid_password})

      assert json_response(pending, 403)["error"] == "account_not_activated"
      assert %User{is_activated: false} = Repo.get_by(User, email: "beta@example.com")
    end
  end

  describe "DELETE /api/v1/logout" do
    test "returns 200 with empty object", %{conn: conn} do
      conn = delete(conn, "/api/v1/logout")

      assert json_response(conn, 200) == %{"ok" => true}
    end
  end
end
