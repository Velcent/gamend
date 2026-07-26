# `mix gamend.api.lint`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/mix/tasks/gamend.api.lint.ex#L1)

Enforces the naming and serialization conventions mechanically.

    mix gamend.api.lint          # report violations, exit 1 if any
    mix gamend.api.lint --list   # list the rules and exit

Run from the umbrella root; CI runs it alongside credo. See
`GameServer.ApiConventions` for what each rule checks and why.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
