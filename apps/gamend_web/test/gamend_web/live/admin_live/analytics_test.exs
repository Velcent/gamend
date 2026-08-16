defmodule GamendWeb.AdminLive.AnalyticsTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Analytics
  alias Gamend.Repo

  defp admin_conn(conn) do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    log_in_user(conn, admin)
  end

  test "renders the summary tiles and the per-day table", %{conn: conn} do
    conn = admin_conn(conn)
    user = AccountsFixtures.user_fixture()
    :ok = Analytics.record_activity(user.id, DateTime.utc_now())

    {:ok, lv, html} = live(conn, ~p"/admin/analytics")

    assert html =~ "Analytics"
    assert html =~ "DAU"
    assert html =~ "D30"
    assert html =~ Date.to_iso8601(Date.utc_today())
    # Nothing has reached a D7 yet: rendered as a dash, never as 0%.
    assert html =~ "—"

    html = lv |> element("button[phx-value-days='90']") |> render_click()
    assert html =~ "btn-active"
    assert length(Regex.scan(~r/<td class="font-mono">/, html)) == 90
  end
end
