# `Gamend.Release`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/release.ex#L1)

Release-time equivalents of the `host.*` mix tasks.

A release ships compiled `.beam` files and nothing else — no Mix, no project
tree, no `mix` binary — so `mix db.migrate` cannot run inside an image built
from `Dockerfile.release`. These functions are what the release's own
entrypoint calls instead:

    bin/gamend_host eval "Gamend.Release.createdb()"
    bin/gamend_host eval "Gamend.Release.migrate()"

Under Mix the `host.*` tasks stay the entry point. Both funnel through
`Gamend.Repo.MigrationPaths`, so the two cannot drift on which migrations
they consider.

`eval` starts a fresh node, applies `config/runtime.exs` and runs the
expression **without starting the application**, which is the point: a
migration that fails takes the command down instead of half-booting an
endpoint against a database it does not match.

# `createdb`

```elixir
@spec createdb() :: :ok
```

Creates the database when it does not exist yet, mirroring `mix ecto.create`.

Idempotent: an existing database is left alone. Postgres deployments where
the server provisions the database already can skip this entirely.

# `migrate`

```elixir
@spec migrate() :: :ok
```

Runs every pending migration — core's and the host's — on each repo.

# `rollback`

```elixir
@spec rollback(module(), integer()) :: :ok
```

Rolls `repo` back down to `version`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
