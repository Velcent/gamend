# `Gamend.Repo.SlowLog`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/repo/slow_log.ex#L1)

Names what is slow in the database, in the log.

  * **A slow query**: one that ran, or waited for a pool connection, longer
    than `GAMEND_DATABASE_SLOW_QUERY_MS` (default 1000).
  * **A long transaction**: one that held its connection, from `begin` to
    `commit` or `rollback`, longer than `GAMEND_DATABASE_SLOW_TRANSACTION_MS`
    (default 2000). On SQLite that connection holds the one write lock
    (transactions are `IMMEDIATE`), so this is the line that explains a
    "database is locked": those errors name the process that waited, never
    the one it waited for.

Each line has the time, the table, the SQL (trimmed) and where in the code
it came from: the first frames outside Ecto and DBConnection. `0` turns
either off. The settings are read when the handler attaches, at boot
(`GamendWeb.HostSupervision.init_runtime/1`); a change takes a restart.

The handler runs inside every query, in the caller's process, so it only
compares two integers unless something was slow.

# `attach`

```elixir
@spec attach() :: :ok
```

Attach the handler with the current settings (detaching any earlier one).

# `detach`

```elixir
@spec detach() :: :ok
```

Detach the handler.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
