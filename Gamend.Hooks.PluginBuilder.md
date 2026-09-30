# `Gamend.Hooks.PluginBuilder`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/plugin_builder.ex#L1)

Builds an OTP plugin bundle (`ebin/*.beam` + `ebin/<app>.app`) from plugin
source code on disk, for the admin Config page and the command line.

Two ways, picked per build:

  * **Mix**, when a `mix` executable is on the PATH (development, the
    Dockerfile's `full` image): `mix deps.get`, `mix gamend.gdscript.compile`
    for a GDScript plugin, `mix compile`, `mix plugin.bundle`, each in the
    plugin's directory.
  * **In-process**, when it is not (a release: the downloadable engine, the
    `release` image): `Gamend.Hooks.PluginBuilder.InProcess` compiles the
    plugin inside the running VM with the Elixir compiler the release ships.
    It handles Elixir and GDScript plugins whose dependencies the engine
    already ships or the plugin carries prebuilt under `deps/<dep>/ebin`.

Either way the result loads through `Gamend.Hooks.PluginManager` exactly as
a hand-built bundle does. Building runs the plugin's code (its `mix.exs`
under Mix, its module bodies in both), so this is for admins and the
operator's shell only.

# `build_result`

```elixir
@type build_result() :: %{
  ok?: boolean(),
  plugin: String.t(),
  source_dir: String.t(),
  mode: mode(),
  started_at: DateTime.t(),
  finished_at: DateTime.t(),
  steps: [step_result()]
}
```

# `mode`

```elixir
@type mode() :: :mix | :in_process
```

# `step_result`

```elixir
@type step_result() :: %{
  cmd: String.t(),
  status: non_neg_integer(),
  output: String.t()
}
```

# `available?`

```elixir
@spec available?() :: boolean()
```

Whether this image can build plugin bundles at all: with `mix`, or in-process
with the Elixir compiler.

The in-process build needs only the `elixir` and `compiler` applications,
which every release carries (`elixir` depends on `compiler`), so this is
true in a release too. Callers still check it so an image without either
presents a disabled control with a reason rather than a failed build.

# `build`

```elixir
@spec build(String.t(), keyword()) :: {:ok, build_result()} | {:error, term()}
```

Builds one plugin from `sources_dir/0`.

Returns `{:ok, result}` for every build that ran, successful or not
(`result.ok?` tells, and `result.steps` carries each step's output: compiler
errors, missing dependencies), and `{:error, reason}` when none could run:
`{:unknown_plugin, name}`, `:mix_unavailable`, `:build_unavailable`.

Options:

  * `:mode` - `:auto` (default: Mix when on the PATH, else in-process),
    `:mix` or `:in_process`.

A plugin the manager has loaded is stopped for an in-process build and
started again when it ends (see `Gamend.Hooks.PluginBuilder.InProcess`). A
Mix build leaves it running; `PluginManager.reload/0` picks the new bundle up.

# `build_all`

```elixir
@spec build_all(keyword()) :: [{String.t(), {:ok, build_result()} | {:error, term()}}]
```

Builds every plugin `list_buildable_plugins/0` offers, one after another,
and returns `[{name, build_result}]` in that order. Takes the options of
`build/2`.

# `list_buildable_plugins`

```elixir
@spec list_buildable_plugins() :: [String.t()]
```

# `mode`

```elixir
@spec mode() :: mode() | nil
```

How `build/1` would build here: `:mix` when this server itself runs under
Mix and a `mix` executable is on the PATH, else `:in_process` when the
compiler is loadable, else `nil`.

A release builds in-process even with a `mix` on the PATH: that one belongs
to some other Elixir install, and started from a release it inherits the
release's ERTS environment (`ROOTDIR`, `BINDIR`) and fails to boot.

# `sources_dir`

```elixir
@spec sources_dir() :: String.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
