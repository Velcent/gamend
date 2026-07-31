# `Gamend.Push.Supervisor`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/supervisor.ex#L1)

Supervises the push delivery processes: the Goth worker (FCM OAuth) and the
two Pigeon dispatchers.

Children are built from config, so with nothing configured (or with
`PUSH_ADAPTER=log`) this supervises nothing and every delivery routes to
the `Log` provider. Its own restart budget also isolates the app: a
dispatcher that somehow crash-loops exhausts this supervisor, provider
`configured?/0` checks start returning false, and push degrades to `Log`
while the rest of the server runs on.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
