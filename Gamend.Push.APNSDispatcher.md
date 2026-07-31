# `Gamend.Push.APNSDispatcher`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/apns_dispatcher.ex#L1)

Pigeon dispatcher for APNs. Configured by `host_runtime.exs` from the
`APNS_*` env vars; started by `Gamend.Push.Supervisor` only when that
config exists.

# `child_spec`

# `push`

Sends a push notification with given options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
