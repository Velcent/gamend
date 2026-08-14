# `Gamend.Settings.Provider`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/settings/provider.ex#L1)

Declares a group of settings on a module.

    defmodule Gamend.Retention do
      use Gamend.Settings.Provider,
        app: :gamend_core,
        group: :retention,
        label: "Retention"

      setting :chat_messages_days, :integer,
        default: 0,
        doc: "Delete chat messages older than N days. 0 keeps forever."
    end

The declaration is the only place a setting is written down. Its environment
variable name is **derived** — `<ROOT>_<GROUP>_<KEY>`, e.g.
`GAMEND_RETENTION_CHAT_MESSAGES_DAYS` — so the key and its env var can never
disagree. There is no way to pin a different name: every setting follows the
convention, without exception.

A variable that *other* software reads (`RELEASE_COOKIE` for the release boot
script, `FLY_REGION` from the platform) is not a setting and does not belong
here — renaming our declaration would not rename what that software reads.
Report those separately; `Gamend.Cluster.environment/0` is the example.

Values are read back with `Gamend.Settings.get/2`, which checks
`Application.get_env(app, module)` and falls back to the compiled default. A
host configures them the ordinary Elixir way and never needs an env var:

    config :gamend_core, Gamend.Retention, chat_messages_days: 90

## Options for `use`

- `:app` (required) — the OTP app the values live under.
- `:group` (required) — the middle segment of the env name, and the grouping
  the admin viewer renders. One word.
- `:root` — first segment of the env name. Defaults to `"GAMEND"`; a plugin
  passes its own (`root: "MY_GAME"`). Each definition carries it back, so
  tooling can check the naming convention without knowing which hosts exist.
- `:label` — display name for the group. Defaults to a capitalised `:group`.

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

# `derive_env`

```elixir
@spec derive_env(String.t(), atom(), atom()) :: String.t()
```

The environment variable name for a group and key: `<ROOT>_<GROUP>_<KEY>`.

The only way a setting gets a name. There is no override.

# `setting`
*macro* 

Declares one setting. See the module doc for the accepted options.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
