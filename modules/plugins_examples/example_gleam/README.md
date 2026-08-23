# example_gleam

A Gamend hooks plugin written in [Gleam](https://gleam.run) instead of Elixir.

Gleam compiles to BEAM bytecode, so this loads through the **same plugin path an
Elixir plugin uses** — no runtime, no bridge, no interpreter. Hook dispatch in
`Gamend.Hooks` is `function_exported?/3`, so a plugin only has to *export* the
callbacks it implements; it never has to be an Elixir module.

## Build

```sh
./bundle.sh
```

That runs `gleam export erlang-shipment` and assembles the layout
`Gamend.Hooks.PluginManager` expects:

```
example_gleam/
  ebin/example_gleam.app      # + {env, [{hooks_module, example_gleam}]}
  ebin/*.beam
  deps/gleam_stdlib/ebin/*.beam
```

`bundle.sh` is the Gleam counterpart of `mix plugin.bundle`. The one thing
`gleam.toml` cannot express is the `hooks_module` application env key, so the
script patches the generated `.app` by consulting and rewriting the term.

## Run it

```sh
GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples mix dev.start
```

The startup banner lists `example_gleam` among the loaded plugins, and
registering a user logs `[ExampleGleam] after_user_register` and grants 250
gold.

## Calling gamend from Gleam

An Elixir module is just the atom `Elixir.<Name>` on the BEAM, so a gamend
context needs no shim — only a type signature:

```gleam
@external(erlang, "Elixir.Gamend.Economy", "grant")
fn economy_grant(
  user_id: String,
  currency: String,
  amount: Int,
  opts: List(#(Dynamic, String)),
) -> Dynamic
```

Hook payloads arrive as Elixir structs, which on the BEAM are maps with atom
keys. `maps:get/2` plus a `gleam/dynamic/decode` decoder reads a field out —
see `string_field` in `src/example_gleam.gleam`.

A Gleam `Dict` *is* an Erlang map, so anything gamend guards with `is_map/1`
(`Gamend.KV.put/2`, metadata maps) takes a `Dict` directly.

## Trade-offs vs an Elixir plugin

- **You get** static types across your own hook code, and the whole BEAM
  ecosystem (Hex, OTP, gamend's contexts) is callable.
- **You lose** the `Gamend.Hooks` SDK stubs, which are Elixir modules with
  Elixir typespecs. Every context call is a hand-written `@external`
  declaration, and nothing checks the arity or argument types against the real
  function until it runs. Elixir plugins get `mix gen.sdk` stubs and Dialyzer
  for free; Gleam plugins do not.
