# `Gamend.Tournaments.Ticker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/tournaments/ticker.ex#L1)

Periodic driver for tournament lifecycles: state transitions, match-ready
firing, deadline_at sweeps and recurrence spawns (`Gamend.Tournaments.tick/0`).

Safe in multi-instance deployments: the tick body is serialized cluster-wide
via `Gamend.Lock`.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
