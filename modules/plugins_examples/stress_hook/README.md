# Stress hook plugin

The server-side half of the load-test harness in [`stress/`](../../../stress).
It exists so a k6 run can (a) time each layer of the stack in isolation and
(b) trigger the writes a player cannot make over HTTP — quest progress, score
submission, wallet credits — which in a real game are the game server's job.

Nothing here is meant for production. It lives in `modules/plugins_examples/`,
which a real deployment does not point at: a game sets
`GAMEND_CONTENT_PLUGINS_DIR` to its own plugin directory.

## RPCs

Called as `POST /api/v1/hooks/call` with `{"plugin":"stress_hook","fn":…,"args":[…]}`.

| Function | Args | What it isolates |
|---|---|---|
| `stress_noop` | — | HTTP → plug → plugin manager overhead, nothing else |
| `stress_memory_read` | `key` | + an ETS lookup |
| `stress_kv_read` | `key` | + a cached DB read |
| `stress_kv_write` | `key` | + a DB write |
| `stress_kv_write_locked` | `key` | + an advisory lock around a read-modify-write |
| `stress_echo` | `size` | serialization/transport cost per byte |
| `stress_setup` | `key` | idempotent seed: ETS table + one KV entry |
| `stress_quest_event` | `amount` | the quest progress path, for the calling user |
| `stress_submit_score` | `score` | the leaderboard write path |
| `stress_credit` | `amount` | a locked wallet read-modify-write |
| `stress_seed_users` | `count`, `prefix`, `password` | creates login-able email users (no mailer) |

`after_startup` creates the `stress_score` leaderboard and the `stress_play`
quest (`reset: "repeat"`, target 1 — every event completes an objective, so the
quest path stays at its heaviest).

## Build

From the repo root:

```sh
cd modules/plugins_examples/stress_hook && mix deps.get && mix compile
```

## Run

```sh
GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples ./start.sh
```

Then see [`stress/README.md`](../../../stress/README.md).
