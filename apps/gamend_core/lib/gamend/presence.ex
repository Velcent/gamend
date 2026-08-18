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

  # Connected users are spread over this many topics rather than tracked on one.
  #
  # `Phoenix.Tracker` shards its work by topic, so a single "users" topic pins
  # every presence diff in the cluster to one shard no matter how large
  # :pool_size is, and puts every connected user in one CRDT state. Bucketing
  # by user id is what lets the pool actually spread.
  #
  # Compile-time constant on purpose: every node must bucket identically, so
  # this is not configurable (a rolling deploy that changed it would split the
  # tracker). :pool_size is configurable and carries the same constraint —
  # see `config :gamend_core, Gamend.Presence, pool_size: n`, which needs a
  # full restart rather than a rolling one.
  @users_buckets 64

  @doc "Topic this user is tracked on."
  @spec users_topic(Ecto.UUID.t()) :: String.t()
  def users_topic(user_id), do: "users:#{:erlang.phash2(user_id, @users_buckets)}"

  @doc "Number of topics connected users are spread over."
  @spec users_buckets() :: pos_integer()
  def users_buckets, do: @users_buckets

  @doc """
  Whether the calling process holds this user's only tracked socket.

  Cluster-wide, unlike the per-node registry count it replaces.
  """
  @spec last_socket?(Ecto.UUID.t()) :: boolean()
  def last_socket?(user_id) do
    # `get_by_key/2`, not `list/1`: listing the topic built a map of every user
    # tracked in it just to read one key, on every disconnect.
    user_id |> users_topic() |> get_by_key(user_id) |> meta_count() <= 1
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
