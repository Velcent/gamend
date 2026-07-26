# `GameServer.Cluster`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/cluster.ex#L1)

Erlang distribution, needed for multi-node deployments and the partitioned
L2 cache.

Only `dns_query` and `redis_url` are settings — values this server reads.
The rest of a clustered deployment is configured through variables *other
software* reads before any of our code runs: `RELEASE_DISTRIBUTION`,
`RELEASE_NODE` and `RELEASE_COOKIE` are consumed by the release boot script,
`ERL_AFLAGS` by `erl` itself, and the `FLY_*` values are injected by the
platform.

Declaring those as settings would be a lie: renaming them onto our convention
would not rename what the BEAM and the platform read, it would leave the
settings permanently empty. `environment/0` reports them for the admin page
as observations rather than settings.

# `environment`

```elixir
@spec environment() :: [
  %{name: String.t(), value: String.t() | nil, secret: boolean()}
]
```

The clustering variables other software reads, with their current values,
for display only.

These are not settings and cannot be renamed onto our convention — the BEAM
and the platform read these exact names.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
