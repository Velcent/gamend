defmodule GameServer.Cluster do
  @moduledoc """
  Erlang distribution, needed for multi-node deployments and the partitioned
  L2 cache.

  Every name here is inherited: `RELEASE_*` and `ERL_AFLAGS` are read by the
  BEAM and by Elixir's release scripts before any of our code runs, and the
  `FLY_*` values are injected by the platform. They are declared so the admin
  page can show what the node actually came up with.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :cluster,
    label: "Clustering"

  setting(:dns_query, :string,
    doc: "DNS name whose A/AAAA records list the other nodes, polled at boot."
  )

  setting(:release_distribution, :string,
    env: "RELEASE_DISTRIBUTION",
    external: true,
    doc: "name (long names) or sname. Read by the release boot script."
  )

  setting(:release_node, :string,
    env: "RELEASE_NODE",
    external: true,
    doc: "This node's name. Must be unique across the cluster."
  )

  setting(:release_cookie, :string,
    env: "RELEASE_COOKIE",
    external: true,
    secret: true,
    doc: "Shared secret every node in the cluster must match."
  )

  setting(:erl_aflags, :string,
    env: "ERL_AFLAGS",
    external: true,
    doc: "Extra BEAM flags, e.g. -proto_dist inet6_tcp for IPv6-only networking."
  )

  setting(:redis_url, :string,
    env: "REDIS_URL",
    external: true,
    doc: "Shared fallback URL used by the cache and rate limiter when neither sets its own."
  )

  setting(:fly_app_name, :string, env: "FLY_APP_NAME", external: true)
  setting(:fly_private_ip, :string, env: "FLY_PRIVATE_IP", external: true)
  setting(:fly_region, :string, env: "FLY_REGION", external: true)
end
