defmodule Gamend.Presence do
  @moduledoc """
  Cluster-wide tracking of who is connected where.

  Backed by `Phoenix.Presence`, so entries are tied to process liveness and
  replicated between nodes by CRDT: a node that dies takes its entries with it,
  with no sweeper to notice. That is the property node-local ETS and database
  flags both lack.

  Used for signaling room membership and lobby spectators. Not for anything
  queried in SQL — presence lives in memory and cannot be joined against a
  table — and not for anything durable, since a full cluster restart empties it.

  During a netsplit each side sees only its own members until they heal.
  """
  use Phoenix.Presence,
    otp_app: :gamend_core,
    pubsub_server: Gamend.PubSub

  @users_topic "users"

  @doc "Topic every connected user is tracked on."
  @spec users_topic() :: String.t()
  def users_topic, do: @users_topic

  @doc """
  Whether the calling process holds this user's only tracked socket.

  Cluster-wide, unlike the per-node registry count it replaces.
  """
  @spec last_socket?(Ecto.UUID.t()) :: boolean()
  def last_socket?(user_id) do
    @users_topic |> list() |> Map.get(user_id) |> meta_count() <= 1
  end

  defp meta_count(nil), do: 0
  defp meta_count(%{metas: metas}), do: length(metas)
  defp meta_count(metas) when is_list(metas), do: length(metas)
  defp meta_count(_), do: 0

  # Deliberately no `handle_metas/4` here. Writing `users.is_online` from the
  # tracker process means a database hiccup exits the tracker and takes every
  # room's presence with it. The channel owns that write instead, using
  # `last_socket?/1` to get the cluster-wide answer.
end
