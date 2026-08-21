defmodule GamendWeb.AdminLive.PluginBuildGateTest do
  @moduledoc """
  The admin Config page offers a "Build bundle" control that shells out to
  `mix`. An image built from Dockerfile.release ships no `mix`, so the control
  has to explain itself rather than fail on click.
  """
  # Manipulates PATH, which is process-global.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  @unavailable_notice "which this image does not ship"

  defp admin_conn(conn) do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    log_in_user(conn, user)
  end

  # System.find_executable/1 resolves a bare name through PATH, so emptying it
  # stands in for a release image with no mix on it.
  defp without_mix_on_path(fun) do
    original = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      fun.()
    after
      System.put_env("PATH", original || "")
    end
  end

  test "explains itself and disables the control when mix is absent", %{conn: conn} do
    conn = admin_conn(conn)

    html =
      without_mix_on_path(fn ->
        {:ok, _lv, html} = live(conn, ~p"/admin/config")
        html
      end)

    assert html =~ @unavailable_notice
    assert html =~ "plugins-build-btn"
    # The button carries `disabled` regardless of whether plugin sources exist.
    assert html =~ ~r/id="plugins-build-btn"[^>]*disabled/s
  end

  test "says nothing about it when mix is present", %{conn: conn} do
    {:ok, _lv, html} = live(admin_conn(conn), ~p"/admin/config")

    refute html =~ @unavailable_notice
  end

  test "submitting the form with mix absent flashes instead of erroring", %{conn: conn} do
    conn = admin_conn(conn)

    without_mix_on_path(fn ->
      {:ok, lv, _html} = live(conn, ~p"/admin/config")

      render =
        lv
        |> element("#plugins-build-form")
        |> render_submit(%{"plugin_build" => %{"name" => "anything"}})

      assert render =~ "cannot build plugin bundles"
    end)
  end
end
