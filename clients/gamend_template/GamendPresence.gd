class_name GamendPresence
extends Node
## Who is around: merged user profiles, lobbies, and presence — maintained
## automatically from the realtime events GamendApi emits. Games read instead
## of bookkeeping: wire the client and `client.presence.users` fills itself as
## people log in, join lobbies, change hats, go online and offline.
##
## Updates arrive as partial patches (sometimes wrapped in "u", metadata as
## sparse sections); they are merged so a profile only ever grows more
## complete. Owned by GamendClient (client.presence).

## A user's merged profile changed (any source: push, member event, cache_user).
signal user_changed(user_id: String)
## A lobby was created/updated or its state flipped.
signal lobby_changed(lobby: Dictionary)

## user_id -> merged profile. Read freely; treat as owned by the presence.
var users: Dictionary[String, Dictionary] = {}
## lobby_id -> lobby (with members folded in when the server sent them).
var lobbies: Dictionary[String, Dictionary] = {}
## user_id -> currently online (others only; self is always online).
var online: Dictionary = {}
## user_id -> unix timestamp they were last seen (offline users).
var last_seen: Dictionary = {}

var _api: GamendApi


func setup(api: GamendApi) -> void:
	_api = api
	_api.user_updated.connect(apply_user_update)
	_api.lobby_updated.connect(_on_lobby_updated)
	_api.lobby_state_changed.connect(_on_lobby_state_changed)
	_api.party_member_updated.connect(_on_member_event)
	_api.lobby_member_joined.connect(_on_member_event)
	_api.lobby_member_updated.connect(_on_member_event)
	_api.group_member_updated.connect(_on_member_event)
	_api.lobby_member_online.connect(_on_member_online)
	_api.lobby_member_offline.connect(_on_member_offline)


func get_user(user_id: String) -> Dictionary:
	return users.get(user_id, {})


func get_lobby(lobby_id: String) -> Dictionary:
	return lobbies.get(lobby_id, {})


func is_online(user_id: String) -> bool:
	# The local user is always "online" from their own client's perspective;
	# the presence map only tracks other users.
	if user_id == _api._user_id:
		return true
	return bool(online.get(user_id, false))


## Record presence learned out of band (search results, friend lists).
func set_presence(user_id: String, is_user_online: bool, last_seen_ts := 0.0) -> void:
	online[user_id] = is_user_online
	if not is_user_online and last_seen_ts > 0.0:
		last_seen[user_id] = last_seen_ts


## Merge a full or partial user payload into the profile (the push path; also
## public for data learned from API responses).
func apply_user_update(user: Dictionary) -> void:
	var uid := str(user.get("id", _api._user_id))
	if uid.is_empty():
		return
	users[uid] = _merge_user(uid, user)
	# The current user's lobby_id is the truth: drop every other lobby so
	# stale entries can't answer for the one lobby that matters.
	if uid == _api._user_id:
		var current_lobby_id := str(users[uid].get("lobby_id", ""))
		for lid in lobbies.keys():
			if lid != current_lobby_id:
				lobbies.erase(lid)
	user_changed.emit(uid)


## Merge partial user data (search results, member lists) without treating it
## as a full profile push.
func cache_user(user_id: String, data: Dictionary) -> void:
	if user_id.is_empty():
		return
	var existing: Dictionary = users.get(user_id, {})
	if existing.is_empty():
		users[user_id] = data
	else:
		for key in data:
			if key == "metadata" and data[key] is Dictionary:
				existing["metadata"] = merge_metadata(existing.get("metadata", {}), data[key])
			else:
				existing[key] = data[key]
	user_changed.emit(user_id)


## Forget everything (logout).
func clear() -> void:
	users.clear()
	lobbies.clear()
	online.clear()
	last_seen.clear()


## Merge sectioned metadata: one level of sub-Dictionaries merges key-wise so a
## sparse patch ({"player": {"hat": "x"}}) can't wipe its section's siblings.
static func merge_metadata(existing_metadata: Dictionary, patch_metadata: Dictionary) -> Dictionary:
	var merged := existing_metadata.duplicate(true)
	for key in patch_metadata:
		var patch_value = patch_metadata[key]
		var existing_value = merged.get(key, {})
		if patch_value is Dictionary and existing_value is Dictionary:
			var section := (existing_value as Dictionary).duplicate(true)
			for section_key in patch_value:
				section[section_key] = patch_value[section_key]
			merged[key] = section
		else:
			merged[key] = patch_value
	return merged


func _merge_user(uid: String, user: Dictionary) -> Dictionary:
	var existing: Dictionary = users.get(uid, {}).duplicate(true)
	var patch: Dictionary = user
	if user.get("u", null) is Dictionary:
		patch = user["u"] as Dictionary
	if existing.is_empty():
		existing = {"id": uid}
	for key in patch:
		if key == "metadata" and patch[key] is Dictionary:
			existing["metadata"] = merge_metadata(existing.get("metadata", {}), patch[key])
		else:
			existing[key] = patch[key]
	return existing


func _on_lobby_updated(lobby: Dictionary) -> void:
	lobbies[str(lobby.get("id", ""))] = lobby
	lobby_changed.emit(lobby)


## The server transitions lobby.state out of band ({from, to, lobby_id}) — the
## `updated` payloads in flight may still carry the old state, so the flip is
## patched into the cache and re-announced: everything keyed off lobby.state
## re-evaluates.
func _on_lobby_state_changed(payload: Dictionary) -> void:
	var lobby_id := str(payload.get("lobby_id", ""))
	if lobby_id.is_empty():
		return
	var lobby: Dictionary = lobbies.get(lobby_id, {"id": lobby_id})
	lobby["state"] = str(payload.get("to", ""))
	lobbies[lobby_id] = lobby
	lobby_changed.emit(lobby)


func _on_member_event(payload: Dictionary) -> void:
	cache_user(str(payload.get("user_id", payload.get("id", ""))), payload)


func _on_member_online(payload: Dictionary) -> void:
	var uid := str(payload.get("user_id", payload.get("id", "")))
	if uid.is_empty():
		return
	set_presence(uid, true)


func _on_member_offline(payload: Dictionary) -> void:
	var uid := str(payload.get("user_id", payload.get("id", "")))
	if uid.is_empty():
		return
	set_presence(uid, false, Time.get_unix_time_from_system())
