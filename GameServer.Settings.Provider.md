# `GameServer.Settings.Provider`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/settings/provider.ex#L1)

Declares a group of settings on a module.

    defmodule GameServer.Retention do
      use GameServer.Settings.Provider,
        app: :game_server_core,
        group: :retention,
        label: "Retention"

      setting :chat_messages_days, :integer,
        default: 0,
        doc: "Delete chat messages older than N days. 0 keeps forever."
    end

The declaration is the only place a setting is written down. Its environment
variable name is **derived** — `<ROOT>_<GROUP>_<KEY>`, e.g.
`GAMEND_RETENTION_CHAT_MESSAGES_DAYS` — so the key and its env var can never
disagree. Pass `env:` only for the handful of names other software owns
(`PORT`, `DATABASE_URL`), which should also carry `external: true`.

Values are read back with `GameServer.Settings.get/2`, which checks
`Application.get_env(app, module)` and falls back to the compiled default. A
host configures them the ordinary Elixir way and never needs an env var:

    config :game_server_core, GameServer.Retention, chat_messages_days: 90

## Options for `use`

- `:app` (required) — the OTP app the values live under.
- `:group` (required) — the middle segment of the env name, and the grouping
  the admin viewer renders. One word.
- `:root` — first segment of the env name. Defaults to `"GAMEND"`; a plugin
  passes its own (`root: "POLYGLOT"`).
- `:label` — display name for the group. Defaults to a capitalised `:group`.
- `:env_prefix` — replaces the derived `<ROOT>_<GROUP>_` prefix for every
  setting in the provider, so `LIMIT_MAX_PAGE_SIZE` can keep its name while
  the group is `:limits`. A transitional escape hatch for names that predate
  the convention; a per-setting `env:` still wins over it.

## Options for `setting/3`

- `:default` — the compiled default. Defaults to `nil`.
- `:doc` — one-line description, shown in the admin viewer and generated docs.
- `:secret` — mask the value everywhere it is displayed.
- `:required` — `:prod` (boot fails in prod, warns in dev) or `:warn` (logs in
  prod). Omit for optional. Never enforced in test.
- `:when` — `{path, value}` gating the requirement on another setting, e.g.
  `when: {[:storage, :adapter], :s3}`. A list of such tuples requires all of
  them to hold.
- `:with` — sibling keys forming a complete-or-empty group. All unset is
  silent; a partial set trips `:required`.
- `:env` — override the derived env var name. For inherited names only.
- `:external` — this name belongs to other software; the viewer files it
  under "Inherited" rather than implying we own it.

# `derive_env`

```elixir
@spec derive_env(String.t(), atom(), atom(), String.t() | nil) :: String.t()
```

The environment variable name for a group and key: `<ROOT>_<GROUP>_<KEY>`.

A provider-level `env_prefix` replaces the `<ROOT>_<GROUP>_` part.

# `setting`
*macro* 

Declares one setting. See the module doc for the accepted options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
