defmodule GamendWeb.PlayLiveTest do
  @moduledoc """
  The game iframe must boot exactly one WASM instance per page.

  `mount/2` runs on the dead render, again on the connected mount, and again on
  every socket reconnect. It mints fresh JWTs each time, so anything derived
  from a token must stay out of the iframe `src` — a changed `src` reloads the
  iframe, a second Godot instance boots alongside the first, and the doubled
  heap gets the tab killed on iOS Safari.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @tag_re ~r/<iframe[^>]*\bid="game-frame"[^>]*>/
  @src_re ~r/<iframe[^>]*\bid="game-frame"[^>]*\bsrc="([^"]*)"/

  defp iframe_tag(html) do
    Regex.run(@tag_re, html) |> hd()
  end

  # Just the src. The dead render and the connected render serialize boolean
  # attributes differently (`allowfullscreen` vs `allowfullscreen=""`), so
  # comparing whole tags would fail on noise.
  defp iframe_src(html) do
    [_, src] = Regex.run(@src_re, html)
    src
  end

  describe "logged out" do
    test "the iframe src carries no token", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/play")
      assert iframe_tag(html) =~ ~s(src="/game/index.html")
      refute iframe_tag(html) =~ "access_token"
    end
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "the iframe src is identical on the dead render and the connected mount",
         %{conn: conn} do
      dead = conn |> get(~p"/play") |> html_response(200)
      {:ok, _live, connected} = live(conn, ~p"/play")

      assert iframe_src(dead) == iframe_src(connected)
    end

    test "the iframe src is a bare path — no fragment, no token", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/play")
      tag = iframe_tag(html)

      assert tag =~ ~s(src="/game/index.html")
      refute tag =~ "#"
      refute tag =~ "access_token"
      refute tag =~ "refresh_token"
    end

    test "tokens still reach the browser, via the GameAuth hook", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/play")

      assert html =~ ~s(phx-hook="GameAuth")
      assert html =~ "data-access-token=\"ey"
      assert html =~ "data-refresh-token=\"ey"
    end
  end
end
