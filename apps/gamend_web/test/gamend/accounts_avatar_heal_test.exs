defmodule Gamend.AccountsAvatarHealTest do
  @moduledoc """
  A mirrored/uploaded avatar whose storage object disappears (wiped volume,
  pruned bucket) must not block the provider avatar forever: sign-in should
  heal the dangling URL from the provider, while an *intact* stored avatar
  keeps winning over the provider one.
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User

  import Gamend.AccountsFixtures

  @provider_url "https://lh3.googleusercontent.com/a/fresh-avatar=s96-c"

  defp stored_avatar_url(user), do: "/storage/avatars/#{user.id}/abc123"
  defp stored_avatar_key(user), do: "avatars/#{user.id}/abc123"

  defp set_profile_url(user, url) do
    {:ok, user} =
      user |> Ecto.Changeset.change(profile_url: url) |> Gamend.Repo.update()

    user
  end

  defp link_google(user) do
    Accounts.link_account(
      user,
      %{google_id: "google-#{System.unique_integer([:positive])}", profile_url: @provider_url},
      :google_id,
      &User.google_oauth_changeset/2
    )
  end

  test "sign-in heals a stored avatar whose object is gone" do
    user = user_fixture()
    user = set_profile_url(user, stored_avatar_url(user))

    {:ok, updated} = link_google(user)

    assert updated.profile_url == @provider_url
  end

  test "an intact stored avatar still wins over the provider avatar" do
    user = user_fixture()
    user = set_profile_url(user, stored_avatar_url(user))
    {:ok, _key} = Gamend.Storage.put(stored_avatar_key(user), "png-bytes")

    {:ok, updated} = link_google(user)

    assert updated.profile_url == stored_avatar_url(user)
  end

  test "an external provider URL is not overwritten either" do
    user = user_fixture()
    user = set_profile_url(user, "https://cdn.discordapp.com/avatars/1/old.png")

    {:ok, updated} = link_google(user)

    assert updated.profile_url == "https://cdn.discordapp.com/avatars/1/old.png"
  end
end
