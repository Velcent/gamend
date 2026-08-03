# Gamend Godot SDK

Talk to a Gamend server from Godot. Three layers:

| Layer | What it is |
|---|---|
| `GamendApi` | Generated REST/WebSocket bindings (one method per endpoint) + realtime socket. You rarely call it directly. |
| `GamendClient` | The facade you actually use: live KV subscriptions, caching, hook RPCs, session snapshots, reconnect watchdog. |
| `client.auth` (`GamendAuth`) | Login flows: session restore, device, browser OAuth, Apple native, Discord embedded. |
| `client.presence` (`GamendPresence`) | Who is around: merged user profiles, lobbies, online/last-seen — self-maintained from realtime events. |

Hand-written files (`GamendClient.gd`, `GamendAuth.gd`, `GamendWebSocket.gd`, …) are maintained in `clients/gamend_template/`; `apis/`, `core/`, `models/` are generated. See the Quickstart comment at the top of `GamendClient.gd` for a complete start-to-finish example.

## GamendClient

Everything returns plain Dictionaries. Nothing here touches UI — errors and state changes leave as signals or return values; the game decides what to show.

### Setup

```gdscript
client.setup(api, user_id_provider)  # user_id_provider: Callable -> String
client.plugin = "my_hook"            # server plugin for rpc_call/rpc_send
```

### Live KV (subscribe once, read any time)

| Member | Purpose |
|---|---|
| `register_kv(name, key_source = "", options = {})` | Declare a key to keep live. `key_source`: the key string, or a Callable for keys that depend on runtime state. Options: `user_scoped` (true), `persist` (false — mirror to disk, reload next login), `subscribe` (true — false = cache-only entry). |
| `refresh_keys()` | Re-evaluate dynamic keys and subscribe anything unconfirmed. Call after login and when a key's inputs change. |
| `get_row(key)` / `has_row(key)` / `clear_row(key)` / `clear_all_rows()` | Read the cache / "do we have an answer" (including known-missing) / forget one / forget everything (logout). |
| `fetch_row(key, user_scoped = true, force = false)` | Cache-first KV read; 404 caches as "no row yet". |
| signals `kv_row_changed(key, row)`, `kv_subscribed(key, row)`, `kv_subscribe_failed(key, error)` | Cache updated / subscribe confirmed / subscribe rejected. |

Subscriptions re-establish on every channel join, verify every reply, and retry transient failures on a backoff (`subscribe_retry_delays_sec`, default 2s/5s/15s; 401/403 never retry). `cache_file_path` ("" disables) holds persisted rows, namespaced per user.

### Caching primitives

| Member | Purpose |
|---|---|
| `fetch_cached(key, fetcher, force = false)` | Cache-first fetch with in-flight dedupe for any async source. Fetcher returns the Dictionary to cache (`{}` = authoritative empty) or `null` (transient failure, nothing cached). Waiters share one request; a hung fetcher is escaped after `fetch_wait_timeout_sec`. |
| `write_deduped(key, value, writer)` | Skip a write when an identical `(key, value)` is already in flight. Returns `{skipped, result}`. |

### Hook RPCs

| Member | Purpose |
|---|---|
| `rpc_call(fn, args)` | Awaited hook call. Returns `{ok, data, error, latency_ms}`. Errors also fire `rpc_failed(fn, error)`. |
| `rpc_send(fn, args)` | Fire-and-forget over the WebSocket. |

### Session snapshots

| Member | Purpose |
|---|---|
| `fetch_current_user()` / `fetch_lobby(id)` | Fresh fetch, normalized: `{ok, data, error}`. |
| `sync_lobby_channel(lobby_id)` | Point the realtime lobby channel ("" = leave). |
| static `user_to_dict(response)` / `lobby_to_dict(response)` | Model/response → plain Dictionary. |

### Network watchdog (opt-in)

```gdscript
client.enable_network_watch({
    # all optional:
    "is_session_active": Callable,  # default: auth.is_online()
    "revalidate": Callable,         # async session check on rejoin
    "retry_login": Callable,        # async re-auth for the Retry button
})
```

States: `connected → reconnecting → connected | failed`; `failed` exits only via `retry_network()`. Automatic drops stay UI-silent for `reconnect_grace_sec`; reconnecting longer than `reconnect_timeout_sec` fails hard.

| Signal | When |
|---|---|
| `network_reconnecting(message)` | Entered reconnecting (don't show UI yet). |
| `network_reconnecting_display(message)` | Still down after the grace window — show UI now. |
| `network_recovered` | Back up — hide UI. |
| `network_rejoined` | Verified channel rejoin — refetch what pushes missed. |
| `network_failed(kind, message)` | Gave up. `kind`: `timeout`/`request`/`revalidate`/`retry`/`external`. |

Also: `fail_network(kind, message)` / `start_network_reconnect(message)` to drive the state from game code, `is_network_failed()` / `is_network_reconnecting()`.

### Presence (client.presence — who is around)

Fills itself from realtime events; games read instead of bookkeeping.

| Member | Purpose |
|---|---|
| `users` / `lobbies` | user_id → merged profile, lobby_id → lobby. Partial pushes merge (sectioned metadata included) so profiles only grow more complete. |
| `online` / `last_seen` / `is_online(id)` / `set_presence(id, online, ts)` | Presence (self is always online). |
| `get_user(id)` / `get_lobby(id)` / `cache_user(id, data)` / `apply_user_update(user)` / `clear()` | Read / merge data learned from API responses / logout. |
| signals `user_changed(user_id)`, `lobby_changed(lobby)` | Something about a person / a lobby changed. |
| static `merge_metadata(existing, patch)` | The sectioned-metadata merge, reusable. |

## client.auth (GamendAuth)

Every flow returns `""` on success or an `"Error: ..."` string. `state_changed(state)` emits `"initial"` / `"online"` / `"offline"`.

| Member | Purpose |
|---|---|
| `restore_session()` | Resume from the stored refresh token (web: the site session's localStorage token). |
| `device_auth()` | Log in as this device (guest). Web device id persists across launches. |
| `provider_auth(provider)` | Browser OAuth for `GamendApi.PROVIDER_*`: opens the URL, polls until the site completes. |
| `apple_native_auth()` | Native Apple dialog (iOS/macOS extension; no-op elsewhere). Captured name in `last_apple_full_name`. |
| `discord_native_auth()` | Embedded-Discord login via the injected `discord_sdk` node. |
| `save_session()` | After any successful login: persist token → start realtime → wait for the profile → `"online"`. |
| `go_offline()` / `reset()` / `is_online()` / `is_offline()` / `state()` | State control and reads. |

Storage: the refresh token and web device id persist to `auth_store_path` (`user://gamend_auth.cfg`) by default; override `secret_get`/`secret_set` (Callables) to use your own settings system or a keychain. Other injection points: `discord_sdk`, `before_session_save` (seed game state before realtime events flow), `provider_timeout_sec`, `user_update_timeout_sec`, `web_device_id_storage_key`.
