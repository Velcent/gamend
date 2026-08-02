# `Gamend.Chat.Moderation.Sync`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/moderation/sync.ex#L1)

Keeps the node-local chat-moderation ETS tables in sync with the database and
the other app instances, and sweeps expired mutes.

After init it loads the blocklist and active mutes into ETS; afterwards it
applies changes broadcast by other instances on
`Gamend.Chat.Moderation.Cache.topic/0`. Events originating on this node are
skipped — the writer already applied them locally.

The initial load runs in `handle_continue` and retries rather than failing the
boot: `init/1` must not couple application startup to the database being
reachable (e.g. during a rolling restart on an unmigrated table).

The mute sweep is hygiene only. `Cache.muted?/3` ignores an expired entry as
it reads it, so a mute never outlives its expiry even if this never runs.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
