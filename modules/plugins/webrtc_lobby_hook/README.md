# WebRTC Lobby Hook

Turns WebRTC signaling on for every lobby, and tells a star host when to connect.

A signaling room **is** a lobby — same id. `GameServer.Signaling` reads
configuration from the lobby's server-owned `webrtc_*` columns, membership from
presence, and relays over PubSub, all cluster-wide. This plugin only sets policy
and sends one notification.

## Callbacks

| Callback | Purpose |
|---|---|
| `after_lobby_create/1` | Enables star signaling on the new lobby, then notifies the host. |
| `after_lobby_updated/1` | Closes the room if WebRTC was switched off. |
| `after_lobby_deleted/1` | Closes the room. |
| `after_lobby_host_change/2` | Re-notifies the new star host. |

Membership is checked against the lobby at join time (`Signaling.authorize/2`).

## Topologies

| Topology | Behaviour |
|---|---|
| `star` | Every exchange involves the host; only the host may broadcast. The host is notified on `user:<id>` with `webrtc:room_ready`. |
| `mesh` | Any peer may signal any other. |

Roles are `:host` and `:user`, assigned by the server in the join reply. The
star host is always `lobby.host_id`.

## Configuration

Through `GameServer.Signaling.configure/2`, the only writer of the `webrtc_*`
columns:

```elixir
GameServer.Signaling.configure(lobby, enabled: true, topology: :star)
```

| Option | Default | Meaning |
|---|---|---|
| `:enabled` | `false` | Whether the room exists at all. |
| `:topology` | — | `:star` or `:mesh`. |
| `:late_join` | `true` | Whether a non-member of the lobby may connect. |
| `:reconnect_timeout` | `30_000` | Grace period in ms before a dropped peer is announced gone. |

## Star host notification

When a star room is ready the host receives, on `user:<host_user_id>`:

```elixir
%{
  "lobby_id" => lobby_id,
  "topology" => "star",
  "host_user_id" => host_user_id,
  "signaling_topic" => "signaling:#{lobby_id}"
}
```

`signaling_topic` is the channel to join, so a headless server-as-host connects
without knowing how topics are named.

## Dropping the plugin

Remove it and call `Signaling.configure/2` yourself — e.g. mesh rooms, or
signaling enabled only once a match starts.
