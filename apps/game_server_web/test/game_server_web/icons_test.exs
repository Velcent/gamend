defmodule GameServerWeb.IconsTest do
  use ExUnit.Case, async: true

  alias GameServerWeb.Icons

  test "the whole heroicons catalog is typed" do
    # heroicons v2 ships 324 icons in the 24px solid set.
    assert length(Icons.list()) == 324
    assert :academic_cap in Icons.list()
    assert :trophy in Icons.list()
    assert :currency_dollar in Icons.list()
  end

  test "get/1 maps icon atoms to hero-* class names" do
    assert Icons.get(:trophy) == "hero-trophy-solid"
    assert Icons.get(:currency_dollar) == "hero-currency-dollar-solid"
    assert Icons.get(:user_group) == "hero-user-group-solid"
  end

  test "get/1 and svg/1 raise on unknown atoms — the set is closed" do
    assert_raise FunctionClauseError, fn -> Icons.get(:no_such_icon) end
    assert_raise FunctionClauseError, fn -> Icons.svg(:no_such_icon) end
  end

  test "svg/1 returns embedded inline SVG for every icon" do
    for icon <- Icons.list() do
      assert "<svg " <> _ = Icons.svg(icon)
    end
  end

  test "default/1 gives each entity type one shared icon atom" do
    assert Icons.default(:group) == :user_group
    assert Icons.default(:tournament) == :bolt
    assert Icons.default(:leaderboard) == :chart_bar
    assert Icons.default(:quest) == :trophy
  end
end
