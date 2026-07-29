# `GameServer.Signaling.Server`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/signaling/server.ex#L1)

Signaling relay for WebRTC user-to-user and client-server topologies.

Rooms are created explicitly by a worker process (e.g. a lobby worker) and
are keyed by the lobby id. Each room stores its topology and, for :star,
the designated host user id. The server validates membership and topology
rules on every relay.

Does not create PeerConnections or handle media; only routes SDP offers,
answers, and ICE candidates between registered users in a room.

## Topologies

  * `:mesh` — any member may send an offer/answer/ICE to any other member.
  * `:star` — one host user (the Godot headless server) and client users.
    Clients may only signal to the host; the host may signal to any client.
    Non-host users cannot exchange messages directly.

Each user is monitored via `Process.monitor/1`. When a user crashes or
disconnects it enters a grace period so that reconnections keep the same
user_id. If the grace period expires, the remaining users are notified.

# `allow_user`

Allows a user to join a room after it has been created (late join).
Called by the lobby hook when a new user joins the lobby.

# `broadcast_message`

Broadcasts a signaling message to every other user in the room.

In `:star` mode only the host may broadcast.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `close_room`

Closes a signaling room. Existing users are notified with a room_closed
event so their channels can stop gracefully.

# `create_room`

Creates a signaling room. `room_id` is typically the lobby id.

For `:star` topology `host_user_id` is required and designates the user
that will act as the authoritative server user.

`allowed_users` is a map of `user_id => role` populated by the lobby hook.
`late_join` controls whether users not in the initial list may join later.
`reconnect_timeout` is the grace period in milliseconds before a
disconnected user is removed.

# `disallow_user`

Removes a user from the allowed list and kicks them if connected.
Called by the lobby hook when a user leaves the lobby.

# `exists_room?`

# `get_room`

# `join_room`

Registers a user in a room using the authenticated `user_id`.

Returns `{:ok, role}` where `role` is derived from the room topology and
the provided `user_id`. Returns `{:error, :room_not_found}` if the room
does not exist, `{:error, :not_allowed}` if the user is not in the
allowed list and late join is disabled, and `{:ok, role}` on
reconnection.

# `leave_room`

# `list_users`

# `relay_message`

Routes a signaling message from one user to a specific target.

Enforces topology rules: in `:star` mode a non-host user may only relay
to the host.

# `room_host?`

# `start_link`

# `update_room_host`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
