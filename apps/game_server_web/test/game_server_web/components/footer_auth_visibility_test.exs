defmodule GameServerWeb.Components.FooterAuthVisibilityTest do
  @moduledoc """
  Footer links accept the same `"auth"` key as nav links. The gate reads the
  user through `Scope.user/1`: `Scope` is `%{user_id, authenticated_at}` with
  no `:user` field, so a `%{user: user}` match silently sees every visitor as
  logged out — which hid `auth: "authenticated"` footer links from everyone.
  """
  use GameServerWeb.ConnCase, async: true

  alias GameServer.Accounts.Scope
  alias GameServerWeb.HostLayoutNavigation

  import GameServer.AccountsFixtures

  test "an authenticated-only entry is visible to a signed-in user" do
    scope = Scope.for_user(user_fixture())

    assert HostLayoutNavigation.entry_visible?(%{"auth" => "authenticated"}, scope)
  end

  test "an authenticated-only entry is hidden from a guest" do
    refute HostLayoutNavigation.entry_visible?(%{"auth" => "authenticated"}, nil)
  end

  test "entries without an auth key stay public" do
    assert HostLayoutNavigation.entry_visible?(%{"href" => "/blog"}, nil)

    assert HostLayoutNavigation.entry_visible?(
             %{"href" => "/blog"},
             Scope.for_user(user_fixture())
           )
  end

  test "admin-only entries need an admin, not just a session" do
    # `user_fixture/0` can hand back an admin (core promotes the first user),
    # so pin the flag rather than trusting the fixture.
    {:ok, plain} =
      user_fixture() |> Ecto.Changeset.change(is_admin: false) |> GameServer.Repo.update()

    refute HostLayoutNavigation.entry_visible?(%{"auth" => "admin"}, Scope.for_user(plain))
    refute HostLayoutNavigation.entry_visible?(%{"admin_only" => true}, nil)

    assert HostLayoutNavigation.entry_visible?(
             %{"auth" => "authenticated"},
             Scope.for_user(plain)
           )
  end
end
