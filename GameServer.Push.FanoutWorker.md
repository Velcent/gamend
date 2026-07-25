# `GameServer.Push.FanoutWorker`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/push/fanout_worker.ex#L1)

Expands a multi-user send into per-token `DeliveryWorker` jobs, in chunks,
off the caller's request path. `GameServer.Push.send_to_users/3` enqueues
this above its inline threshold so a large broadcast never holds a long
transaction (SQLite is single-writer) and survives restarts. Identical args
within a minute dedupe via Oban uniqueness (double-broadcast guard).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
