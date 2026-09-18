extends SceneTree

# Calls a live server through the generated addon and checks each answer
# lands in its named model class. Argument after `--`: the server URL.
#
# It signs in with a fresh device id, so the server needs device login on,
# and it writes: a user, a lobby and a party it leaves, and a group it keeps.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(result: GamendResult, label: String, model) -> Variant:
	if result.error:
		failures += 1
		print("FAIL ", label, ": ", result.error.message)
		return null
	var data = result.response.data
	if not is_instance_of(data, model):
		failures += 1
		print("FAIL ", label, ": got ", data)
		return null
	print("ok   ", label, " -> ", data.get_script().get_global_name())
	return data


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var url := args[0] if args.size() > 0 else "http://127.0.0.1:4000"
	var parts := url.split("://")
	var tls := parts[0] == "https"
	var host_port := parts[1].trim_suffix("/").split(":")
	var port := int(host_port[1]) if host_port.size() > 1 else (443 if tls else 80)

	var api := GamendApi.new(host_port[0], port, tls)
	root.add_child(api)
	await process_frame

	var device_id := "godot-check-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_expect(await api.authenticate_device_login(device_id), "device_login", GamendSessionResponse)
	if api.get_access_token() == "":
		failures += 1
		print("FAIL device_login: no token captured")

	_expect(await api.users_get_current_user(), "get_current_user", GamendCurrentUser)

	var join := GamendQuickJoinRequest.new()
	join.title = "godot-check"
	join.max_users = 2
	var lobby = _expect(await api.lobbies_quick_join(join), "quick_join", GamendLobby)
	if lobby:
		var detail := await api.lobbies_get_lobby(lobby.id)
		if _expect(detail, "get_lobby", GamendLobbyResponse):
			var as_dict := GamendClient.lobby_to_dict(detail.response)
			if as_dict.get("id") != lobby.id or (as_dict.get("members", []) as Array).is_empty():
				failures += 1
				print("FAIL lobby_to_dict: ", as_dict)

	_expect(await api.lobbies_list_lobbies(), "list_lobbies", GamendLobbyPage)
	_expect(await api.lobbies_lobby_stats(), "lobby_stats", GamendLobbyStatsResponse)
	_expect(await api.users_search_users("godot-check"), "search_users", GamendPublicUserPage)
	_expect(await api.friends_list_friends(), "list_friends", GamendFriendPage)
	_expect(await api.friends_list_friend_requests(), "list_friend_requests", GamendFriendRequestsResponse)
	_expect(await api.friends_list_blacklisted_users(), "list_blacklisted_users", GamendUserBriefPage)

	var providers = _expect(await api.authenticate_list_auth_providers(), "list_auth_providers", GamendAuthProvidersResponse)
	if providers and not providers.__data__was__set:
		failures += 1
		print("FAIL list_auth_providers: data was dropped")

	var left := await api.lobbies_leave_lobby()
	if left.error:
		failures += 1
		print("FAIL leave_lobby: ", left.error.message)
	else:
		print("ok   leave_lobby")

	var new_group := GamendCreateGroupRequest.new()
	new_group.title = "godot-check-%d" % randi()
	var group = _expect(await api.groups_create_group(new_group), "create_group", GamendGroup)
	if group:
		_expect(await api.groups_get_group(group.id), "get_group", GamendGroup)
		_expect(await api.groups_list_group_members(group.id), "list_group_members", GamendGroupMemberPage)
	_expect(await api.groups_list_groups(), "list_groups", GamendGroupPage)
	_expect(await api.groups_list_my_groups(), "list_my_groups", GamendGroupPage)

	var new_party := GamendCreatePartyRequest.new()
	new_party.max_size = 4
	var party = _expect(await api.parties_create_party(new_party), "create_party", GamendParty)
	if party and (party.members as Array).is_empty():
		failures += 1
		print("FAIL create_party: no members")
	_expect(await api.parties_show_party(), "show_party", GamendParty)
	_expect(await api.parties_party_stats(), "party_stats", GamendPartyStatsResponse)
	var left_party := await api.parties_leave_party()
	if left_party.error:
		failures += 1
		print("FAIL leave_party: ", left_party.error.message)
	else:
		print("ok   leave_party")

	print("failures=", failures)
	quit(1 if failures > 0 else 0)
