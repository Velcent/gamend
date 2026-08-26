defmodule GamendWeb.AdminLive.SystemTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  test "renders VM stats and links to the retention page", %{conn: conn, admin: admin} do
    {:ok, _view, html} = conn |> log_in_user(admin) |> live(~p"/admin/system")

    assert html =~ "Memory (BEAM VM)"
    assert html =~ "Data Retention"
    assert html =~ "/admin/retention"
  end
end
