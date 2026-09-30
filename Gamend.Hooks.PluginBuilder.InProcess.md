# `Gamend.Hooks.PluginBuilder.InProcess`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/plugin_builder/in_process.ex#L1)

Builds a plugin bundle inside the running VM, without Mix.

A release (the downloadable engine, the Dockerfile's `release` image) ships
the Elixir compiler but no `mix` executable, so `Gamend.Hooks.PluginBuilder`
falls back to this. It produces what `mix plugin.bundle` does for the
plugin's own code: `ebin/*.beam` plus `ebin/<app>.app`, loadable by
`Gamend.Hooks.PluginManager` unchanged.

Steps, each reported as a `t:Gamend.Hooks.PluginBuilder.step_result/0`:

  1. Read `mix.exs` without evaluating it (`Gamend.Hooks.PluginBuilder.Project`).
  2. GDScript plugins (`scripts/*.gd`): transpile into `gen/` with
     `Gamend.GDScript`, as `mix gamend.gdscript.compile` does.
  3. Check dependencies. One the engine ships (phoenix, jason, req, ecto…)
     or that sits prebuilt in `deps/<dep>/ebin` is fine; `gamend_sdk` and
     `gamend_plugin_tools` are compile-time only and ignored. Anything else
     fails the build naming it: there is no Hex here to fetch it.
  4. Compile `elixirc_paths/**/*.ex` with `Kernel.ParallelCompiler` into a
     temporary directory, then write the `.app` and swap it in as `ebin/`.
     A failed build leaves the previous `ebin/` untouched.

The compiler runs in this VM, so a plugin that is loaded is stopped for the
build (`PluginManager.suspend/1`) and started again afterwards
(`PluginManager.resume/1`), on the new bundle when the build succeeded and on
the old one when it failed. Unloading first matters: the compiler takes a
module that is already loaded as the one to compile against, so a sibling's
old macros and structs would end up in the new build.

Limits: no Hex dependencies beyond what the engine ships or the plugin
carries prebuilt, no Erlang sources (`src/*.erl`), no Gleam, no
`config/config.exs`, and the engine's protocols are consolidated, so a
`defimpl` of an engine protocol (`Jason.Encoder`, `String.Chars`…) has no
effect; the compiler's warning saying so is in the compile step's output.
The compiler also prints its diagnostics to the server's stderr.

# `available?`

```elixir
@spec available?() :: boolean()
```

Whether this VM can compile Elixir: the `elixir` and `compiler` applications
are loadable. True in any release, since `elixir` depends on `compiler`.

# `run`

```elixir
@spec run(String.t(), Path.t()) :: [Gamend.Hooks.PluginBuilder.step_result()]
```

Builds the plugin in `plugin_dir` (named `plugin_name` by the loader).
Returns the steps it ran; the build succeeded when every status is `0`.

Builds of one plugin directory run one at a time on this node.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
