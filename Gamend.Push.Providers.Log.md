# `Gamend.Push.Providers.Log`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/providers/log.ex#L1)

Zero-config default provider: logs each delivery instead of calling out —
the `Storage.Local` of push. Every token routed here (nothing configured,
`PUSH_ADAPTER=log`, or a provider whose dispatcher is down) reports success,
so the whole flow is exercisable with no credentials.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
