//// Example Gamend hooks plugin written in Gleam.
////
//// Gleam compiles to BEAM bytecode, so this loads through the exact same
//// plugin path an Elixir plugin uses: `ebin/*.beam` plus an `.app` file whose
//// env names this module as `hooks_module`. Nothing in the server is
//// Elixir-specific -- hook dispatch is `function_exported?/3`.
////
//// The server calls into gamend contexts as ordinary Erlang module calls
//// (`Elixir.Gamend.Economy` is just an atom), declared with `@external`.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode

// ── Erlang / Elixir FFI ─────────────────────────────────────────────────────

@external(erlang, "erlang", "binary_to_atom")
fn atom(name: String) -> Dynamic

@external(erlang, "maps", "get")
fn map_get(key: Dynamic, map: Dynamic) -> Dynamic

@external(erlang, "logger", "info")
fn log_info(message: String) -> Dynamic

// gamend SDK contexts. An Elixir module is the atom `Elixir.<Name>`, so calling
// one from Gleam needs no shim -- only a type signature.
@external(erlang, "Elixir.Gamend.Economy", "grant")
fn economy_grant(
  user_id: String,
  currency: String,
  amount: Int,
  opts: List(#(Dynamic, String)),
) -> Dynamic

// `Gamend.KV.put/2` guards on `is_map(value)`. A Gleam `Dict` *is* an Erlang
// map, so it crosses the boundary with no conversion.
@external(erlang, "Elixir.Gamend.KV", "put")
fn kv_put(key: String, value: Dict(String, String)) -> Dynamic

@external(erlang, "Elixir.Gamend.KV", "get")
fn kv_get(key: String) -> Dynamic

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Read a field off an Elixir struct. A struct is a map with atom keys, so
/// this is `maps:get/2` plus a decode back into a Gleam type.
fn string_field(record: Dynamic, field: String) -> String {
  case decode.run(map_get(atom(field), record), decode.string) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

// ── Hooks ───────────────────────────────────────────────────────────────────

/// Called once when the plugin loads. Returning an empty list declares no
/// dynamic hooks; the Elixir example returns a list of maps here instead.
pub fn after_startup() -> List(Dynamic) {
  log_info("[ExampleGleam] after_startup called")
  let _ =
    kv_put(
      "example_gleam_welcome",
      dict.from_list([#("message", "Hello from Gleam!")]),
    )
  []
}

/// Grant a starter bonus to every new account.
pub fn after_user_register(user: Dynamic) -> Dynamic {
  let user_id = string_field(user, "id")
  let username = string_field(user, "username")

  log_info("[ExampleGleam] after_user_register user=" <> username)

  let _ =
    economy_grant(user_id, "gold", 250, [
      #(atom("reason"), "gleam_starter_kit"),
      #(atom("idempotency_key"), "gleam_starter:" <> user_id),
    ])

  atom("ok")
}

/// Log every login. Two hooks are enough to prove fan-out reaches a Gleam
/// module the same way it reaches an Elixir one.
pub fn after_user_logged_in(user: Dynamic) -> Dynamic {
  log_info("[ExampleGleam] after_user_logged_in user=" <> string_field(
    user,
    "username",
  ))
  atom("ok")
}

/// A plain function the server can expose as a callable RPC.
pub fn hello(name: String) -> String {
  "Hello from Gleam, " <> name <> "!"
}

/// Reads back what `after_startup` wrote, to prove SDK calls work in both
/// directions.
pub fn welcome_message() -> Dynamic {
  kv_get("example_gleam_welcome")
}
