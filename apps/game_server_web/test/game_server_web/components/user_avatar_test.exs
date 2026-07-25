defmodule GameServerWeb.Components.UserAvatarTest do
  @moduledoc """
  `/play` and `/game/*` are served cross-origin isolated for Godot's
  `SharedArrayBuffer` (`GameServerWeb.Plugs.GameHeaders`). Under
  `Cross-Origin-Embedder-Policy: require-corp` a cross-origin image is blocked
  unless it carries `Cross-Origin-Resource-Policy` or is fetched in CORS mode —
  and the OAuth avatar CDNs send no CORP header.

  So the `crossorigin` attribute is what keeps avatars visible on those pages.
  Drop it and every OAuth avatar silently vanishes on the play page only, which
  no page-level test would catch.
  """
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias GameServer.Accounts.User
  alias GameServerWeb.CoreComponents

  test "an avatar is fetched in CORS mode so COEP pages can display it" do
    user = %User{profile_url: "https://lh3.googleusercontent.com/a/abc=s96-c"}

    html = render_component(&CoreComponents.user_avatar/1, user: user)

    assert html =~ ~s(crossorigin="anonymous")
    assert html =~ ~s(src="https://lh3.googleusercontent.com/a/abc=s96-c")
  end

  test "a broken image swaps to a hidden icon fallback via onerror" do
    user = %User{profile_url: "https://example.com/not-ready-yet.png"}

    html = render_component(&CoreComponents.user_avatar/1, user: user)

    assert html =~ "onerror="
    assert html =~ ~s(class="hero-user-circle-solid hidden w-6 h-6")
  end

  test "a user without one falls back to the icon" do
    html = render_component(&CoreComponents.user_avatar/1, user: %User{profile_url: nil})

    refute html =~ "<img"
    assert html =~ "hero-user-circle-solid"
  end

  test "the size class is applied to whichever branch renders" do
    with_avatar =
      render_component(&CoreComponents.user_avatar/1,
        user: %User{profile_url: "https://example.com/a.png"},
        class: "w-16 h-16"
      )

    without = render_component(&CoreComponents.user_avatar/1, user: nil, class: "w-16 h-16")

    assert with_avatar =~ "w-16 h-16"
    assert without =~ "w-16 h-16"
  end
end
