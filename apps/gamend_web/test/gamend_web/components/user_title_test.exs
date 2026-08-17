defmodule GamendWeb.Components.UserTitleTest do
  @moduledoc """
  `user_title/1` is the one line every player-naming surface draws under a name.
  Core does not know what a rank is; it reads a metadata path the host names.
  What must hold: unset config or a blank value renders NOTHING — a fresh
  account gets a bare name, never an empty badge — and the path is honoured as
  the host wrote it, nested.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GamendWeb.CoreComponents

  setup do
    original = Application.get_env(:gamend_web, :user_title_meta_path)
    on_exit(fn -> restore(original) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:gamend_web, :user_title_meta_path)
  defp restore(value), do: Application.put_env(:gamend_web, :user_title_meta_path, value)

  defp render_title(user) do
    render_component(&CoreComponents.user_title/1, user: user)
  end

  test "reads the host's nested metadata path" do
    Application.put_env(:gamend_web, :user_title_meta_path, ["player", "rank"])
    user = %{metadata: %{"player" => %{"rank" => "Sailor 3", "hat" => "crown"}}}

    assert render_title(user) =~ "Sailor 3"
    refute render_title(user) =~ "crown"
    assert CoreComponents.user_title_text(user) == "Sailor 3"
  end

  test "renders nothing when the host has not configured a path" do
    Application.delete_env(:gamend_web, :user_title_meta_path)
    user = %{metadata: %{"player" => %{"rank" => "Sailor 3"}}}

    assert String.trim(render_title(user)) == ""
    assert CoreComponents.user_title_text(user) == nil
  end

  test "renders nothing for a blank value, missing metadata, or nil user" do
    Application.put_env(:gamend_web, :user_title_meta_path, ["player", "rank"])

    for user <- [
          %{metadata: %{"player" => %{"rank" => ""}}},
          %{metadata: %{"player" => %{}}},
          %{metadata: %{}},
          %{metadata: nil},
          nil
        ] do
      assert String.trim(render_title(user)) == "", "rendered a title for #{inspect(user)}"
    end
  end

  test "accepts a %User{}, a map with :metadata, or a bare metadata map" do
    Application.put_env(:gamend_web, :user_title_meta_path, ["player", "rank"])
    metadata = %{"player" => %{"rank" => "Navigator 1"}}

    assert CoreComponents.user_title_text(%Gamend.Accounts.User{metadata: metadata}) == "Navigator 1"
    assert CoreComponents.user_title_text(%{metadata: metadata}) == "Navigator 1"
    assert CoreComponents.user_title_text(%{"metadata" => metadata}) == "Navigator 1"
    assert CoreComponents.user_title_text(metadata) == "Navigator 1"
  end
end
