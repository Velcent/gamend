defmodule Gamend.Accounts.PresenceStatus do
  @moduledoc """
  How recently a user was seen, as the three states the UI actually draws.

  Distinct from `Gamend.Presence`, which tracks live socket membership across
  the cluster. This is the durable, per-user view derived from `is_online` and
  `last_seen_at` — the thing a friends list or a chat sidebar wants when the
  user is not connected to *this* node at all.

  The rule already existed twice, in two shapes: `Gamend.Parties` kept a private
  `@online_grace_seconds` with a boolean active/not check, and the Godot client
  kept its own `RECENT_THRESHOLD_SECONDS` with a three-state version. They
  happened to agree on 300 seconds, which is exactly the kind of agreement that
  quietly stops being true. This module is the authority; clients may mirror the
  constant, but the server decides it.

  `:recent` is the state the web has never drawn — every surface had a boolean
  `online`, so someone who closed the tab a minute ago looked identical to
  someone who has not played in a week.
  """

  alias Gamend.Accounts.User

  @typedoc "Online now, seen within the grace window, or neither."
  @type t :: :online | :recent | :offline

  @recent_threshold_seconds 300

  @doc """
  Seconds after `last_seen_at` during which a signed-off user still counts as
  `:recent`. Authoritative — mirror it in clients, do not redefine it.
  """
  @spec recent_threshold_seconds() :: pos_integer()
  def recent_threshold_seconds, do: @recent_threshold_seconds

  @doc """
  Presence state for a user.

  Accepts a `User`, or any map carrying `is_online`/`last_seen_at` (a serialized
  payload, say) so a caller does not have to reload the struct just to draw a
  dot. Anything else is `:offline` — an unknown user is not an online one.
  """
  @spec status(User.t() | map() | nil) :: t()
  def status(%User{is_online: true}), do: :online
  def status(%User{last_seen_at: last_seen}), do: from_last_seen(last_seen)

  def status(%{} = attrs) do
    if truthy?(get_field(attrs, :is_online)) do
      :online
    else
      from_last_seen(get_field(attrs, :last_seen_at))
    end
  end

  def status(_), do: :offline

  @doc """
  Whether the user counts as present at all — `:online` or `:recent`.

  The boolean `Gamend.Parties` needs when deciding whether a member has gone
  quiet, defined in terms of `status/1` so the two cannot diverge.
  """
  @spec active?(User.t() | map() | nil) :: boolean()
  def active?(user), do: status(user) != :offline

  defp get_field(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp from_last_seen(%DateTime{} = last_seen) do
    if DateTime.diff(DateTime.utc_now(), last_seen, :second) <= @recent_threshold_seconds,
      do: :recent,
      else: :offline
  end

  defp from_last_seen(last_seen) when is_binary(last_seen) do
    case DateTime.from_iso8601(last_seen) do
      {:ok, dt, _offset} -> from_last_seen(dt)
      _ -> :offline
    end
  end

  defp from_last_seen(_), do: :offline

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
