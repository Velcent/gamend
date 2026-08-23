#!/usr/bin/env sh
# Builds this Gleam plugin into the layout Gamend's PluginManager loads:
#
#   example_gleam/ebin/example_gleam.app   (+ {env, [{hooks_module, ...}]})
#   example_gleam/ebin/*.beam
#   example_gleam/deps/<dep>/ebin/*.beam
#
# This is the Gleam equivalent of `mix plugin.bundle`. `gleam export
# erlang-shipment` already produces one directory per OTP app with a real
# `.app` file -- the only thing it cannot express is the `hooks_module` env
# key, so that is patched in below.
set -eu

APP=example_gleam
HOOKS_MODULE=example_gleam

gleam export erlang-shipment

rm -rf ebin deps
mkdir -p ebin deps

cp -R "build/erlang-shipment/$APP/ebin/." ebin/

# Every other app in the shipment is a runtime dependency (gleam_stdlib, ...).
for dir in build/erlang-shipment/*/; do
  name=$(basename "$dir")
  [ "$name" = "$APP" ] && continue
  mkdir -p "deps/$name/ebin"
  cp -R "$dir/ebin/." "deps/$name/ebin/"
  # `if`, not `[ -d ] && cp` -- under `set -e` a false test as the last
  # command of the loop body is a shell-dependent exit.
  if [ -d "$dir/priv" ]; then
    cp -R "$dir/priv" "deps/$name/priv"
  fi
done

# Add {env, [{hooks_module, ...}]} to the generated .app. Done by consulting
# and rewriting the term rather than by text substitution, so a change in
# Gleam's .app formatting cannot silently break it.
erl -noshell -eval "
  {ok, [{application, App, Props}]} = file:consult(\"ebin/$APP.app\"),
  Props2 = lists:keystore(env, 1, Props, {env, [{hooks_module, $HOOKS_MODULE}]}),
  ok = file:write_file(\"ebin/$APP.app\",
                       io_lib:format(\"~p.~n\", [{application, App, Props2}])),
  halt(0).
"

echo "bundled $APP -> ebin/ + deps/"
