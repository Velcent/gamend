defmodule Gamend.Accounts.InactivityNotifier do
  @moduledoc """
  Warns a user their account is about to be deleted for inactivity.

  `retention_warned_at` is stamped **after** a successful send, not at enqueue:
  an un-warned account is one the sweep refuses to delete, so a mail outage
  postpones a deletion rather than performing a silent one.
  """
  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [period: {1, :day}, fields: [:worker, :args]]

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.{User, UserNotifier}
  alias Gamend.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "delete_after_days" => days}}) do
    case Accounts.get_user(user_id) do
      %User{email: email} = user when is_binary(email) -> warn(user, days)
      _gone_or_no_address -> :ok
    end
  end

  defp warn(user, days) do
    case UserNotifier.deliver_inactivity_warning(user, days) do
      {:ok, _email} ->
        stamp_warned(user)

      {:error, reason} ->
        Logger.warning("inactivity warning failed user=#{user.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stamp_warned(user) do
    metadata =
      Map.put(
        user.metadata || %{},
        "retention_warned_at",
        DateTime.to_iso8601(DateTime.utc_now())
      )

    user
    |> Ecto.Changeset.change(metadata: metadata)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Accounts.invalidate_user_cache_by_id(updated.id)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
