defmodule GamendWeb.Auth.Tokens do
  @moduledoc """
  The tokens a sign-in answers, whatever it signed in with: email and
  password, a device, registration, or a provider. One place, so every
  sign-in carries the same `Session` and the same side effects.
  """

  alias Gamend.Accounts.User
  alias GamendWeb.Auth.Guardian

  @access_ttl_seconds 900

  @doc """
  A new access and refresh token for `user`, as `GamendWeb.Schemas.Session`
  describes them, after the login side effects: `last_seen_at`, the
  `after_user_logged_in` hook and the `login` quest event.
  """
  @spec sign_in(User.t()) :: map()
  def sign_in(%User{} = user) do
    # `touch_last_seen/1` joins them rather than running inline: it is two more
    # writes (the `last_seen_at` update, and the activity-day insert behind it)
    # on a path that already wrote the user row, and both are fire-and-forget by
    # construction — nothing in the response depends on either. On SQLite's
    # single writer those writes were the difference between a login returning
    # and a login waiting, and signup throughput fell as concurrency rose
    # because of them. The work still happens, and still costs the same; the
    # caller no longer holds a connection while it does.
    #
    # Tests run `Gamend.Async` inline, so anything asserting on `last_seen_at`
    # straight after a login still sees it.
    Gamend.Async.run(fn ->
      Gamend.Accounts.touch_last_seen(user)
      Gamend.Hooks.internal_call(:after_user_logged_in, [user])
      Gamend.Quests.report_event(user.id, "login")
    end)

    {:ok, access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")

    {:ok, refresh_token, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {30, :days})

    session(user, access_token, refresh_token)
  end

  @doc "The `Session` fields for tokens already issued (a refresh keeps its refresh token)."
  @spec session(User.t(), String.t(), String.t()) :: map()
  def session(%User{} = user, access_token, refresh_token) do
    %{
      access_token: access_token,
      refresh_token: refresh_token,
      expires_in: @access_ttl_seconds,
      user_id: user.id,
      username: user.username || "",
      display_name: user.display_name || ""
    }
  end
end
