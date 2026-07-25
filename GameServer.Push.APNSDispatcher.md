# `GameServer.Push.APNSDispatcher`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/push/apns_dispatcher.ex#L1)

Pigeon dispatcher for APNs. Configured by `host_runtime.exs` from the
`APNS_*` env vars; started by `GameServer.Push.Supervisor` only when that
config exists.

# `child_spec`

# `push`

Sends a push notification with given options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
