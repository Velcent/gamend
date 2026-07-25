# `GameServer.Cluster`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/cluster.ex#L1)

Erlang distribution, needed for multi-node deployments and the partitioned
L2 cache.

Every name here is inherited: `RELEASE_*` and `ERL_AFLAGS` are read by the
BEAM and by Elixir's release scripts before any of our code runs, and the
`FLY_*` values are injected by the platform. They are declared so the admin
page can show what the node actually came up with.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
