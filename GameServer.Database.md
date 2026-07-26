# `GameServer.Database`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/database.ex#L1)

Connection and tuning settings for `GameServer.Repo`.

The adapter is chosen at **compile** time (see `config/host_config.exs`), so
`adapter` here is documentation and admin display rather than something a
restart can change — the app refuses to start on a stale build and says so.

`GAMEND_DB_URL` and the `POSTGRES_*` family are inherited names: platforms
provision them, and renaming them would break every managed-database
attachment.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
