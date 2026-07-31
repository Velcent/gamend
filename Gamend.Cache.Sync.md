# `Gamend.Cache.Sync`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/cache/sync.ex#L1)

Applies cache invalidations broadcast by other app instances.

`Gamend.Cache.invalidate/1` deletes a key locally and broadcasts it on
`Gamend.Cache.invalidation_topic/0`; this process evicts the key from
this node's L1 so all instances converge immediately instead of waiting for
the entry's TTL. Events originating on this node are skipped — the caller
already deleted the key locally.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
