defmodule GameServer.UserRetentionTest do
  @moduledoc """
  Account retention.

  An anonymous account costs one unauthenticated request to create, so without a
  sweep the only bound on how much a bot can accumulate is how long it keeps
  asking. These cover both windows and, more importantly, the accounts the sweep
  must never touch.
  """
  use GameServer.DataCase, async: false
  use Oban.Testing, repo: GameServer.Repo

  import Ecto.Query

  alias GameServer.Accounts
  alias GameServer.Accounts.{InactivityNotifier, User}
  alias GameServer.AccountsFixtures
  alias GameServer.Repo
  alias GameServer.Retention

  setup do
    old = Application.get_env(:game_server_core, Retention, [])
    on_exit(fn -> Application.put_env(:game_server_core, Retention, old) end)
    :ok
  end

  defp configure(opts) do
    existing = Application.get_env(:game_server_core, Retention, [])
    Application.put_env(:game_server_core, Retention, Keyword.merge(existing, opts))
  end

  defp anonymous_user(last_seen_days_ago) do
    {:ok, user} =
      Accounts.find_or_create_from_device("device-#{System.unique_integer([:positive])}")

    backdate(user, last_seen_days_ago)
  end

  defp registered_user(last_seen_days_ago) do
    AccountsFixtures.user_fixture() |> backdate(last_seen_days_ago)
  end

  # `is_admin` is forced off because the very first account in a fresh database
  # is auto-promoted, which would otherwise silently exempt every fixture here
  # from the sweep it is meant to exercise.
  defp backdate(user, days) do
    at = DateTime.add(DateTime.utc_now(:second), -days, :day)

    user
    |> Ecto.Changeset.change(last_seen_at: at, is_admin: false)
    |> Repo.update!()
  end

  defp exists?(user), do: Repo.exists?(from(u in User, where: u.id == ^user.id))

  defp stamp_warned(user, days_ago) do
    at = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.to_iso8601()

    user
    |> Ecto.Changeset.change(metadata: Map.put(user.metadata, "retention_warned_at", at))
    |> Repo.update!()
  end

  describe "anonymous accounts" do
    test "an anonymous account past the window is deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(120)

      Retention.prune_all()

      refute exists?(user)
    end

    test "an anonymous account inside the window is kept" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(30)

      Retention.prune_all()

      assert exists?(user)
    end

    test "0 disables the sweep entirely" do
      configure(anonymous_users_days: 0)
      user = anonymous_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account that has never connected is dated from when it was created" do
      configure(anonymous_users_days: 90)

      {:ok, user} = Accounts.find_or_create_from_device("never-seen-#{System.unique_integer()}")

      user =
        user
        |> Ecto.Changeset.change(
          last_seen_at: nil,
          is_admin: false,
          inserted_at: DateTime.add(DateTime.utc_now(:second), -120, :day)
        )
        |> Repo.update!()

      Retention.prune_all()

      refute exists?(user)
    end

    test "a registered account is not touched by the anonymous sweep" do
      configure(anonymous_users_days: 90, inactive_users_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end
  end

  describe "exclusions" do
    test "an admin is never deleted" do
      configure(anonymous_users_days: 90)

      user =
        anonymous_user(9999)
        |> Ecto.Changeset.change(is_admin: true)
        |> Repo.update!()

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account holding a purchase is never deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(9999)

      Repo.insert!(%GameServer.Payments.Purchase{
        user_id: user.id,
        provider: "stripe",
        order_id: "order-#{System.unique_integer([:positive])}",
        status: "completed"
      })

      Retention.prune_all()

      assert exists?(user)
    end

    test "an account holding an entitlement is never deleted" do
      configure(anonymous_users_days: 90)
      user = anonymous_user(9999)

      Repo.insert!(%GameServer.Payments.Entitlement{
        user_id: user.id,
        key: "monthly_pass",
        status: "active"
      })

      Retention.prune_all()

      assert exists?(user)
    end
  end

  describe "storage" do
    # Object storage has no foreign key to cascade, so a deleted account used to
    # leave its avatars behind indefinitely - which defeats both the sweep above
    # and an erasure request.
    test "deleting an account removes its stored objects" do
      dir =
        Path.join(System.tmp_dir!(), "gs_retention_storage_#{System.unique_integer([:positive])}")

      old = Application.get_env(:game_server_core, GameServer.Storage.Local)
      Application.put_env(:game_server_core, GameServer.Storage.Local, dir: dir)

      on_exit(fn ->
        File.rm_rf(dir)
        if old, do: Application.put_env(:game_server_core, GameServer.Storage.Local, old)
      end)

      configure(anonymous_users_days: 90)
      user = anonymous_user(120)
      other = anonymous_user(1)

      {:ok, _} = GameServer.Storage.put("avatars/#{user.id}/a.png", "x")
      {:ok, _} = GameServer.Storage.put("avatars/#{user.id}/b.png", "y")
      {:ok, _} = GameServer.Storage.put("avatars/#{other.id}/a.png", "z")

      Retention.prune_all()

      refute exists?(user)
      refute GameServer.Storage.exists?("avatars/#{user.id}/a.png")
      refute GameServer.Storage.exists?("avatars/#{user.id}/b.png")
      assert GameServer.Storage.exists?("avatars/#{other.id}/a.png")
    end
  end

  describe "inactive registered accounts" do
    test "off by default" do
      configure(inactive_users_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)
    end

    test "is warned first, and not deleted on the same pass" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)
      user = registered_user(9999)

      Retention.prune_all()

      assert exists?(user)

      assert Repo.exists?(
               from(j in Oban.Job,
                 where: j.worker == "GameServer.Accounts.InactivityNotifier",
                 where: fragment("json_extract(?, '$.user_id')", j.args) == ^user.id
               )
             )
    end

    test "is deleted once the warning has been delivered" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)
      user = registered_user(9999)

      assert :ok =
               perform_job(InactivityNotifier, %{"user_id" => user.id, "delete_after_days" => 730})

      Retention.prune_all()

      refute exists?(user)
    end

    # Warned, came back, went quiet again. That old warning was notice of a
    # deletion the sign-in cancelled, so it must not license the next one - the
    # user is entitled to a fresh warning first.
    test "a warning older than the last sign-in does not count" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 30)

      user =
        registered_user(800)
        |> stamp_warned(900)

      Retention.prune_all()

      assert exists?(user)
    end

    test "with warnings disabled the account is deleted directly" do
      configure(inactive_users_days: 730, inactive_users_warn_days: 0)
      user = registered_user(9999)

      Retention.prune_all()

      refute exists?(user)
    end
  end
end
