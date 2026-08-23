# GDScript plugins — GDScript transpiled to Elixir source

Design spec for a new roadmap item. Goal: let a Godot developer write server
hooks in **GDScript**, transpiled to readable **Elixir source**, compiled by
`mix` into an ordinary OTP plugin. No Elixir knowledge required, no new runtime,
no sandbox, and native BEAM speed — the compiled output is indistinguishable
from a hand-written plugin.

## Why (the hook API is fine; Elixir is the toll booth)

`Gamend.Hooks` already exposes **80 callbacks** and the SDK exposes **26
contexts** (`Gamend.Economy`, `Gamend.Lobbies`, `Gamend.Quests`, …). The
extension surface is not the problem. The problem is the cost of the first line:
a Godot developer who wants to grant 100 gold on registration must learn Elixir,
the OTP application layout, `mix.exs`, and `mix plugin.bundle`.

Nakama shipped Lua and JavaScript runtimes for exactly this reason. Gamend's
audience is narrower and therefore easier to serve: they already write GDScript.

**This is a front end on the plugin system, not a new one.** Nothing about
hooks, plugin loading, `hooks_module`, or bundling changes. The output is
`.beam` files in `<plugin>/ebin` — byte-for-byte the shape `mix plugin.bundle`
produces today.

## What this is not

- **Not a sandbox.** A GDScript plugin is as trusted as an Elixir plugin — it is
  code the server operator installed. Untrusted third-party scripts are a
  different product (see Deferred).
- **Not Godot.** No nodes, scenes, physics, `Resource`, `preload`, `_process`.
  There is no engine and no frame loop on the server.
- **Not all of GDScript.** A documented subset, rejected at parse time rather
  than failing at runtime.

## Shape

```
shop.gd  →  lexer  →  AST  →  codegen  →  gen/shop.ex  →  mix compile  →  ebin/*.beam
```

The generated `.ex` is **written to disk and kept**. It is `mix format`ted,
readable, diffable, and it is what appears in stack traces. That file is the
debugging story for v1 — a user who hits an error reads generated Elixir that
looks like their GDScript.

## Plugin layout

```
modules/plugins/my_game/
  scripts/
    hooks.gd                     ← author writes this
  gen/
    gamend/modules/my_game.ex    ← generated, committed
  mix.exs                        ← generated once by `mix gamend.gdscript.new`
  ebin/                          ← mix plugin.bundle output, unchanged
```

Two tasks in `sdk_tools/lib/mix/tasks/`, next to `plugin.bundle`:

- `mix gamend.gdscript.new <name>` — scaffolds the directory, `mix.exs` with
  `hooks_module:` already wired, and a `hooks.gd` with one example callback.
- `mix gamend.gdscript.compile` — `scripts/*.gd` → `gen/**/*.ex`. Runs before
  `compile` via a compiler alias so `mix plugin.bundle` is unchanged.

The admin "Build bundle" control gains a GDScript step. Nothing else in the
admin or loader moves.

## The mapping that makes this cheap

GDScript's static-call syntax is Elixir's module-call syntax. That is the whole
trick, and it means the 26 SDK contexts need **zero** translation work — they
are already shaped like GDScript singletons.

```gdscript
func after_user_register(user):
    Economy.grant(user.id, "gold", 100, "welcome_bonus")
    Notifications.create(user.id, "welcome", {"gold": 100})
```

```elixir
def after_user_register(user) do
  Gamend.Economy.grant(user.id, "gold", 100, "welcome_bonus")
  Gamend.Notifications.create(user.id, "welcome", %{"gold" => 100})
  :ok
end
```

| GDScript | Elixir | Note |
|---|---|---|
| `Economy.grant(...)` | `Gamend.Economy.grant(...)` | prefix the known context list |
| `user.id` | `user.id` | hook payloads are structs; dot access works as-is |
| `{"a": 1}` | `%{"a" => 1}` | Dictionary → string-keyed map |
| `d["k"]` and `d.k` | `d["k"]` | always emit bracket form; `.k` on a map raises |
| `[1, 2, 3]` | `[1, 2, 3]` | Array → list |
| `func f(a, b = 2)` | `def f(a, b \\ 2)` | default args map directly |
| `null` / `true` | `nil` / `true` | |
| `"%s scored %d" % [n, s]` | `GDScript.Runtime.format(...)` | runtime helper |

Unknown identifiers are a **compile error at name resolution**, not a runtime
`UndefinedFunctionError`. The API table is generated from `@sdk_modules`, so it
never drifts from the SDK.

## Mutation — the only genuinely hard part

Elixir allows rebinding (`x = 1; x = x + 1`). What it does not allow is a
rebinding inside a block escaping that block. Codegen needs one analysis pass:
**for each block, the set of variables assigned inside it**, threaded through as
a tuple. Three cases.

**`if` — the assignment becomes the return value**

```gdscript
var bonus = 0
if score > 100:
    bonus = 50
```
```elixir
bonus = 0
bonus = if score > 100, do: 50, else: bonus
```

**`for` — `Enum.reduce` over the assigned set**

```gdscript
var total = 0
var count = 0
for r in rounds:
    total += r
    count += 1
```
```elixir
{total, count} =
  Enum.reduce(rounds, {total, count}, fn r, {total, count} ->
    {total + r, count + 1}
  end)
```

**`while` — one runtime helper plus recursion**

```elixir
# GDScript.Runtime
def while_loop(acc, cond_fn, body_fn) do
  if cond_fn.(acc), do: while_loop(body_fn.(acc), cond_fn, body_fn), else: acc
end
```

Generated binder names are suffixed (`total__1`) rather than reusing the source
name, so nothing depends on Elixir's shadowing rules and the output is
unambiguous to read.

**Mutating methods count as assignment.** `arr.append(x)` and `d[k] = v` mutate
in GDScript and must be lifted to rebinds, then joined into the same assigned
set:

| GDScript | Elixir |
|---|---|
| `arr.append(x)` | `arr = arr ++ [x]` |
| `arr.erase(x)` | `arr = List.delete(arr, x)` |
| `d[k] = v` | `d = Map.put(d, k, v)` |
| `d.erase(k)` | `d = Map.delete(d, k)` |

The mutating-method list is closed and lives in one table; a collection method
outside it is a compile error rather than a silent no-op. That last part
matters — `arr.append(x)` compiling to a discarded value would be the worst
possible failure mode.

## Return, break, continue, await

| Problem | Emission |
|---|---|
| `return` in tail position | plain value, no wrapper |
| `return` anywhere else | body wrapped in `try do … catch {:gd_return, v} -> v end`, emit `throw({:gd_return, v})` |
| `break` / `continue` | `Enum.reduce_while` with `{:halt, acc}` / `{:cont, acc}` |
| `await` | `receive do {:gd_signal, ^ref, v} -> v after t -> nil end` |

`await` deserves a note: the script runs in its own BEAM process, so a
suspended coroutine is a blocked process — a few KB and zero CPU. Ten thousand
scripts can await concurrently, which the engine itself cannot do as cheaply.
The `try/catch` wrapper is emitted **only** when a non-tail `return` exists, so
the common hook pays nothing for it.

## The v1 subset

| Supported | Rejected at parse (with a "not supported server-side" message) |
|---|---|
| `var`, `const`, all assignment operators | `class_name`, `extends`, inner classes, inheritance |
| `if` / `elif` / `else`, `match`, ternary | `signal` declarations (use `Gamend.Realtime`) |
| `for`, `while`, `break`, `continue` | `preload`, `load`, `@onready`, `@tool` |
| `func`, default args, `return` | `_ready`, `_process`, `_physics_process` |
| `Array`, `Dictionary`, `String`, `int`, `float`, `bool` | `Node`, `Resource`, `Object`, any engine type |
| lambdas (`func(x): return x`) | `set`/`get` property accessors |
| `await` | `yield` (4.x removed it anyway) |
| type hints — **parsed and discarded** | static type *enforcement* |
| `Vector2`, `Vector3`, `Color` as value structs | operator overloading beyond those three |

Type hints parse but do not check in v1. They are kept in the AST so a later
pass can turn them into guards without a grammar change.

## Errors and debugging

v1: stack traces point at `gen/my_game.ex`, and every generated file carries a
header naming its source `.gd` plus a `# gd: hooks.gd:42` comment on each
emitted statement group. A user reading the trace lands on generated Elixir
next to a comment naming their line.

v2 (deferred): parse the generated source back with `Code.string_to_quoted/2`,
rewrite `line:` metadata from a side-map, and `Code.compile_quoted(quoted,
"hooks.gd")`. Traces then name the `.gd` file and line directly. This is
strictly additive — the emitted `.ex` stays the artifact of record.

## Testing

- **Golden files** — `test/fixtures/gdscript/<case>.gd` +
  `<case>.ex.expected`. The suite compiles and diffs. Cheap to add, and the
  diff is the review surface for every codegen change.
- **Behavioural** — each fixture is compiled, loaded, and *called*, asserting
  the returned value. Golden output that compiles to the wrong semantics is the
  failure mode golden tests alone miss.
- **The mutation matrix explicitly** — nested `if` inside `for` inside `while`,
  each mutating a different overlapping variable set. That is where the
  assigned-set analysis breaks, and nowhere else.
- **One real plugin** — port `modules/plugins_examples/example_hook` to
  `modules/plugins_examples/example_gdscript` and assert identical behaviour
  against the existing test.

## "Update everywhere" — file list

- **README** Features: "Server scripting — Elixir **or GDScript**".
  **CHANGELOG** `[added]` GDScript plugins.
- **priv/docs/40-gameplay/** — new `95-gdscript-hooks.md` guide: the subset
  table, the two mix tasks, one worked hook. The existing
  `90-server-scripting.md` gains a pointer, not a rewrite.
- **sdk_tools** — the two new mix tasks; `plugin.bundle` moduledoc mentions the
  GDScript pre-step.
- **api_spec.ex** feature list; **runtime_introspection.ex** — report which
  plugins are GDScript-sourced on the admin Runtime page.
- **Godot SDK** — ship the `.gd` syntax as-is; no editor plugin in v1 (the
  Godot editor already highlights and lints `.gd` files sitting in a folder).
- **i18n** — the admin Runtime label only; no user-facing strings.

## Deferred / rejected

- **Tree-walking interpreter: rejected.** Same front end, 10–100× slower, and
  it needs a runtime that the compiled path does not. The only thing it buys is
  easier error messages, and the generated-source approach already gives those.
- **Sandboxing: rejected for v1**, per the "not a sandbox" scope above. If
  gamend ever hosts other people's scripts this returns as a *codegen*
  whitelist (only ever emit calls in the API table) plus `max_heap_size` and a
  watchdog process — cheap to add later precisely because name resolution
  already goes through one table. Nothing in v1 forecloses it.
- **`@export` → admin-editable settings: defer, but this is the highest-value
  follow-up.** `@export var daily_reward := 100` surfacing as a hot-editable
  field in the admin portal is a LiveOps feature (it is roughly what Heroic
  Labs sells as Satori). It is deferred because it does not fit
  `Gamend.Settings.Provider` — that is env-var-derived and read-only at
  runtime, and `@export` needs a runtime-writable store. That is a KV-backed
  settings surface, which is its own spec.
- **Classes and inheritance: defer.** Hooks are a flat set of functions. Revisit
  when a real plugin has duplicated logic that only inheritance would remove.
- **Array index performance: accept for v1.** `arr[i]` emits `Enum.at/2` (O(n))
  and `append` emits `++` (O(n)). Document "use a Dictionary for hot lookups"
  and revisit with `:array` only if a profile demands it.
- **libgodot / real Godot types: explicitly not this spec.** Running actual
  scenes and physics server-side is a separate, much larger product. Coupling
  it here would sink both.

## Definition of done (CONTRIBUTING)

- [ ] `mix gamend.gdscript.new` scaffolds a plugin that compiles and loads
      without hand-editing.
- [ ] `mix gamend.gdscript.compile` emits `mix format`-clean Elixir; a
      `--check` form fails when `gen/` is stale (CI gate, mirroring
      `gamend.settings.env_example`).
- [ ] Every one of the 80 `Gamend.Hooks` callbacks is expressible; the arity
      table is generated from the behaviour, not hand-listed.
- [ ] API table generated from `@sdk_modules` — adding an SDK context requires
      no GDScript-side edit.
- [ ] Unknown identifier, unsupported syntax, and unknown mutating method are
      **compile errors** with the source line, never runtime failures.
- [ ] Mutation matrix tests green: nested `if`/`for`/`while` with overlapping
      assigned sets, `break`/`continue`, non-tail `return`, `await`.
- [ ] `example_gdscript` plugin ports `example_hook` and passes its tests
      unchanged; both adapters.
- [ ] Boot the server, drop the bundled plugin in `modules/plugins/`, and
      trigger a real hook — per CONTRIBUTING, run it, don't only test it.
- [ ] Guide, README, CHANGELOG, `api_spec.ex`, runtime introspection.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green.

## Appendix — why GDScript first, and what a second language would cost

GDScript is unusually cheap to transpile, and the reasons are specific:
Python-like surface syntax, no `this`, no prototypes, no metaclasses,
decorators or generators, a small stdlib, and — the decisive one —
`ClassName.method()` maps 1:1 onto `Module.function()`. Almost nothing else on
the shortlist has that property.

| Language | Route | Cost | Verdict |
|---|---|---|---|
| **GDScript** | transpile → Elixir source | low | **this spec** |
| **Lua** | embed [Luerl](https://github.com/rvirding/luerl) — Lua 5.x written *in Erlang* | very low (no compiler at all) | best second language. Each state is an Erlang term in a normal process; no NIF, no port. Nakama's scripting language, so it doubles as a migration story. Cost: interpreted, and Godot devs don't write Lua |
| **Wasm** | `wasmex` (Wasmtime NIF) | medium | the generic answer — unlocks Rust/Go/AssemblyScript at once. But every API call marshals across the boundary, which is the wrong shape for I/O-bound hooks that mostly call back into gamend |
| **JavaScript** | embed QuickJS via NIF, or a Deno port process | high | biggest audience, worst fit. Transpiling is hard (`this`, prototypes, async, closures over mutable locals); embedding means either an immature NIF or Supabase's edge-runtime shape — a separate process and IPC per call |
| **Python** | Pythonx / erlport (separate OS process) | high | transpiling is hardest of the set (dynamic everything); embedding CPython in BEAM is a non-starter (GIL, blocking). Worst ROI |
| **Gleam / LFE** | already compile to BEAM | **zero — verified** | shipped as `modules/plugins_examples/example_gleam`. Loads through the unmodified plugin path; the only change core needed was one RPC name lookup that used Elixir's `__info__/1`. Free, but nobody in this audience writes them |

Effort ranking: **GDScript ≪ Lua < Wasm < JavaScript ≪ Python.**

Gleam is already done — see the row above. It cost one line of core and a
bundling script, because hook dispatch was never Elixir-specific. That is worth
noting here because it sets the bar: any route that needs *more* than a
front-end and a bundler is buying something, and the appendix is how you check
what.

The strategic read: you do not need many. GDScript is both the easiest to build
and the one your audience already writes — do it first and alone. Lua via
Luerl is the natural second *if* Nakama refugees show up asking, because it
needs zero compiler work. Everything else should wait for someone to actually
ask twice.
