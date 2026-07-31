# `Gamend.Settings`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/settings.ex#L1)

The declared configuration surface: every setting core, the host and its
plugins expose, with its type, default, group, env var name and required
level.

Settings are declared with `Gamend.Settings.Provider` and read with
`get/2`, which checks `Application.get_env(app, module)` and falls back to
the compiled default. That means a host configures the ordinary Elixir way:

    config :gamend_core, Gamend.Retention, chat_messages_days: 90

Environment variables are one *input method* into that, not a second source.
A host that wants them writes one line in `config/runtime.exs`:

    for {app, module, opts} <- Gamend.Settings.from_env() do
      config app, module, opts
    end

A host that prefers a JSON file, or plain Elixir, writes its own equivalent.
Every route ends at `Application` config, so no two sources compete.

## Discovery

Providers are found by scanning the modules of `apps/0` for `__settings__/0`
and cached in `:persistent_term`. Plugins load after config is resolved, so
`Gamend.Hooks.PluginManager` registers theirs on load via `add_app/1`.

# `definition`

```elixir
@type definition() :: %{
  key: atom(),
  module: module(),
  app: atom(),
  group: atom(),
  label: String.t(),
  type: atom(),
  default: term(),
  env: String.t(),
  doc: String.t(),
  secret: boolean(),
  external: boolean(),
  required: :prod | :warn | nil,
  when: {[atom()], term()} | nil,
  with: [atom()]
}
```

# `add_app`

```elixir
@spec add_app(atom()) :: :ok
```

Registers another app's providers — the host application, or a plugin loaded
after boot. Clears the cache so the next read picks them up.

# `add_provider`

```elixir
@spec add_provider(module()) :: :ok
```

Registers one provider module directly, for code that is not in a scanned
app's module list — a plugin compiled at runtime, or a test.

# `all`

```elixir
@spec all() :: [definition()]
```

Every declared setting, across every registered app.

# `apps`

```elixir
@spec apps() :: [atom()]
```

Apps scanned for providers.

# `cast`

```elixir
@spec cast(String.t(), atom()) :: {:ok, term()} | :error
```

Casts a raw string to a declared type. Returns `:error` when it does not
parse, so the caller decides whether that is fatal.

# `describe`

```elixir
@spec describe(definition()) :: map()
```

A setting's declaration, with its effective value and where that came from:
`:config` when the host set one, `:default` otherwise.

The admin viewer renders this; `:env` never appears as a source because env
vars are resolved into `Application` config at boot rather than read live.

# `env_name`

```elixir
@spec env_name(String.t(), atom(), atom()) :: String.t()
```

The env var name a group/key derives to. Exposed for docs and the
`.env.example` generator.

# `from_env`

```elixir
@spec from_env() :: [{atom(), module(), keyword()}]
```

Reads every declared setting from the environment, as `{app, module, opts}`
ready to splat into `config/2`.

Only variables that are actually set contribute; the rest fall through to
the compiled default. A value that does not parse as its declared type is
skipped with a warning rather than taking the boot down.

# `get`

```elixir
@spec get(module(), atom()) :: term()
```

The current value of a setting: the host's `Application` config if it set
one, otherwise the compiled default.

Raises for a key the module does not declare — an undeclared read is a bug,
not a runtime condition.

# `group`

```elixir
@spec group(atom()) :: [definition()]
```

Declared settings for one group.

# `groups`

```elixir
@spec groups() :: [{atom(), String.t()}]
```

Every group, as `{group, label}`, in display order.

# `providers`

```elixir
@spec providers() :: [module()]
```

Provider modules, discovered once and cached.

# `reload`

```elixir
@spec reload() :: :ok
```

Drops the cached provider list. Call after loading code that declares settings.

# `remove_provider`

```elixir
@spec remove_provider(module()) :: :ok
```

Undoes `add_provider/1`.

# `resolve`

```elixir
@spec resolve() :: %{required({module(), atom()}) =&gt; term()}
```

Every setting's resolved value, keyed by `{module, key}`: the environment
when it is set, the compiled default otherwise.

For `config/runtime.exs`, which needs values *while* it is still building the
configuration. `config/2` only applies after the whole file is evaluated, so
`get/2` cannot see what `from_env/0` just contributed — this can.

# `validate`

```elixir
@spec validate(atom()) :: {[String.t()], [String.t()]}
```

Checks every declared requirement against the resolved configuration.

Returns `{failures, warnings}`, each a list of human-readable lines. Nothing
is raised here — `validate!/1` decides what is fatal, so a caller that wants
to render the state instead (the admin viewer) can.

Severity by environment:

| Level | `:prod` | `:dev` | `:test` |
| --- | --- | --- | --- |
| `required: :prod` | failure | warning | silent |
| `required: :warn` | warning | silent | silent |

The dev warning on a prod requirement is deliberate: it says the deployment
will not boot in production while the developer is still at the keyboard.
Test is silent because the suite boots hundreds of times.

# `validate!`

```elixir
@spec validate!(atom()) :: :ok
```

Runs `validate/1`, logging warnings and raising on failures.

Called once at boot. Returns `:ok` when nothing is fatal.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
