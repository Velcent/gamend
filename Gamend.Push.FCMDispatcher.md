# `Gamend.Push.FCMDispatcher`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/fcm_dispatcher.ex#L1)

Pigeon dispatcher for FCM. Configured by `host_runtime.exs` from the
`PUSH_FCM_*` env vars; started by `Gamend.Push.Supervisor` only when
that config exists.

# `child_spec`

# `push`

Sends a push notification with given options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
