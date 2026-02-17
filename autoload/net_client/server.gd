# NetClient：Server-only 逻辑（room 管理 + 广播 + forfeit 自动推进）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

var _net = null

func setup(net_client) -> void:
	_net = net_client

func on_peer_connected(peer_id: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode == NetContext.Mode.ONLINE_SERVER:
		GameLog.info("NetClient", "Peer connected: %d" % peer_id)

func on_peer_disconnected(peer_id: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	_net._profile_by_peer_id.erase(peer_id)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	var in_game := room != null and str(room.status) == "InGame"
	var actor_id := -1
	if room != null and (room.player_id_by_peer_id is Dictionary):
		if room.player_id_by_peer_id.has(peer_id):
			actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
			room.player_id_by_peer_id.erase(peer_id)
		elif room.player_id_by_peer_id.has(str(peer_id)):
			actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
			room.player_id_by_peer_id.erase(str(peer_id))

	var removed := false
	var rr = _net._room_manager.disconnect_peer(peer_id) if in_game else _net._room_manager.leave_room(peer_id)
	if rr.ok:
		removed = bool(rr.value.get("removed", false))

	if in_game and actor_id >= 0 and room.game_engine != null:
		var cmd = CommandClass.create("forfeit_player", actor_id, {})
		var fr = room.game_engine.execute_command(cmd)
		if fr.ok:
			broadcast_command_applied(room, cmd)
			server_drain_forfeited_auto_steps(room)
		else:
			GameLog.error("NetClient", "forfeit_player failed: %s" % fr.error)

	if rr.ok and room != null and not removed:
		broadcast_room_state(room)
		broadcast_room_list("")
	elif rr.ok and removed:
		broadcast_room_list("")

func send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	_net.rpc_id(peer_id, "rpc_request_rejected", {
		"request_id": request_id,
		"code": code,
		"message": message,
	})

func broadcast_room_state(room) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var state: Dictionary = room.to_room_state_dict()
	for peer_id in room.get_peer_ids():
		_net.rpc_id(peer_id, "rpc_room_state", state)

func empty_room_state() -> Dictionary:
	return {
		"room_code": "",
		"host_peer_id": 0,
		"players": [],
		"spectators": [],
		"password_required": false,
		"allow_spectators": true,
		"config": {},
		"status": "Lobby",
	}

func send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var rooms: Array[Dictionary] = []
	if _net._room_manager != null and _net._room_manager.has_method("list_room_summaries"):
		rooms = _net._room_manager.list_room_summaries()
	_net.rpc_id(peer_id, "rpc_room_list", {
		"request_id": request_id,
		"rooms": rooms,
	})

func broadcast_room_list(request_id: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	for peer_id_val in _net._profile_by_peer_id.keys():
		send_room_list_to_peer(int(peer_id_val), request_id)

func handle_rpc_client_hello(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var protocol_version := int(request.get("protocol_version", 0))
	if protocol_version != NetContext.PROTOCOL_VERSION:
		send_request_rejected(peer_id, request_id, "protocol_version_mismatch", "Protocol version mismatch")
		return

	var profile: Dictionary = Dictionary(request.get("player_profile", {}))
	_net._profile_by_peer_id[peer_id] = {
		"name": str(profile.get("name", "玩家")),
		"color_index": int(profile.get("color_index", 0)),
	}
	# 允许已在房间中的客户端更新自己的 profile（昵称/颜色）。
	# 重要：不新增 @rpc 方法，避免 dedicated server 与客户端版本不一致时触发 checksum mismatch。
	var room = _net._room_manager.get_room_by_peer(peer_id) if _net._room_manager != null else null
	if room != null and room.has_method("update_peer_profile"):
		var ur = room.update_peer_profile(peer_id, Dictionary(_net._profile_by_peer_id[peer_id]))
		if ur.ok:
			broadcast_room_state(room)
			broadcast_room_list("")
	send_room_list_to_peer(peer_id, "")

func handle_rpc_list_rooms(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before ListRooms")
		return

	send_room_list_to_peer(peer_id, request_id)

func handle_rpc_create_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before CreateRoom")
		return

	var desired_player_count := int(request.get("desired_player_count", 0))
	if desired_player_count < Globals.MIN_PLAYERS or desired_player_count > Globals.MAX_PLAYERS:
		send_request_rejected(peer_id, request_id, "invalid_player_count", "desired_player_count out of range")
		return

	var room_password := str(request.get("room_password", ""))
	var config := {
		"desired_player_count": desired_player_count,
		"seed_mode": "random",
		"seed": 0,
		"allow_spectators": true,
		"enabled_modules_v2": Array(Globals.enabled_modules_v2, TYPE_STRING, "", null),
		"modules_v2_base_dir": str(Globals.modules_v2_base_dir),
	}

	if request.has("seed_mode"):
		var sm := str(request.get("seed_mode", "")).strip_edges()
		if sm != "random" and sm != "fixed":
			send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		config["seed_mode"] = sm
	if request.has("seed"):
		var sv = request.get("seed", null)
		if not (sv is int or sv is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		config["seed"] = int(sv)
	if str(config.get("seed_mode", "random")) == "fixed":
		if not request.has("seed"):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
			return

	if request.has("allow_spectators"):
		var av = request.get("allow_spectators", null)
		if not (av is bool):
			send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		config["allow_spectators"] = bool(av)

	if request.has("enabled_modules_v2"):
		var mv = request.get("enabled_modules_v2", null)
		if not (mv is Array):
			send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
			return
		var mods: Array[String] = []
		for it in Array(mv):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			mods.append(s)
		config["enabled_modules_v2"] = mods

	if request.has("modules_v2_base_dir"):
		var bd := str(request.get("modules_v2_base_dir", "")).strip_edges()
		if bd.is_empty():
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		var bd_read := ModuleDirSpecClass.parse_base_dirs(bd)
		if not bd_read.ok:
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir must use res:// paths")
			return
		config["modules_v2_base_dir"] = bd

	# seed_mode=random：由 server 固定生成 seed，以便大厅展示与可复现。
	if str(config.get("seed_mode", "random")) == "random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		config["seed"] = int(rng.randi())

	var cr = _net._room_manager.create_room(peer_id, profile, room_password, config)
	if not cr.ok:
		send_request_rejected(peer_id, request_id, "create_room_failed", cr.error)
		return

	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		send_request_rejected(peer_id, request_id, "create_room_failed", "Missing room in result")
		return

	broadcast_room_state(room)
	broadcast_room_list("")

func handle_rpc_join_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before JoinRoom")
		return

	var room_code := str(request.get("room_code", "")).strip_edges().to_upper()
	var room_password := str(request.get("room_password", ""))

	var jr = _net._room_manager.join_room(peer_id, profile, room_code, room_password)
	if not jr.ok:
		send_request_rejected(peer_id, request_id, "join_room_failed", jr.error)
		return

	var room = Dictionary(jr.value).get("room", null)
	if room == null:
		send_request_rejected(peer_id, request_id, "join_room_failed", "Missing room in result")
		return

	broadcast_room_state(room)
	broadcast_room_list("")
	if str(room.status) == "InGame" and room.game_engine != null:
		var payload := {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
		}
		_net.rpc_id(peer_id, "rpc_game_started", payload)
		var archive_r = room.game_engine.create_archive()
		if archive_r.ok:
			_net.rpc_id(peer_id, "rpc_resync_archive", {
				"archive": Dictionary(archive_r.value).duplicate(true),
			})

func handle_rpc_update_room_config(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		send_request_rejected(peer_id, request_id, "not_host", "Only host can update config")
		return

	var patch_raw = request.get("config_patch", null)
	if not (patch_raw is Dictionary):
		send_request_rejected(peer_id, request_id, "invalid_params", "config_patch must be Dictionary")
		return
	var patch: Dictionary = Dictionary(patch_raw)

	if patch.has("desired_player_count"):
		var v = patch.get("desired_player_count", null)
		if not (v is int or v is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count must be int")
			return
		var n := int(v)
		if n < Globals.MIN_PLAYERS or n > Globals.MAX_PLAYERS:
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count out of range")
			return
		if n < int(room.get_player_count()):
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count < current players")
			return
		patch["desired_player_count"] = n

	if patch.has("seed_mode"):
		var sm := str(patch.get("seed_mode", "")).strip_edges()
		if sm != "random" and sm != "fixed":
			send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		patch["seed_mode"] = sm

	if patch.has("seed"):
		var sv = patch.get("seed", null)
		if not (sv is int or sv is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		patch["seed"] = int(sv)

	if patch.has("allow_spectators"):
		var av = patch.get("allow_spectators", null)
		if not (av is bool):
			send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		patch["allow_spectators"] = bool(av)

	if patch.has("enabled_modules_v2"):
		var mv = patch.get("enabled_modules_v2", null)
		if not (mv is Array):
			send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
			return
		var mods: Array[String] = []
		for it in Array(mv):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			mods.append(s)
		patch["enabled_modules_v2"] = mods

	if patch.has("modules_v2_base_dir"):
		var bd := str(patch.get("modules_v2_base_dir", "")).strip_edges()
		if bd.is_empty():
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		var bd_read := ModuleDirSpecClass.parse_base_dirs(bd)
		if not bd_read.ok:
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir must use res:// paths")
			return
		patch["modules_v2_base_dir"] = bd

	# seed_mode=random：保持一个 server 选定的 seed（不在 StartGame 时再重掷），便于大厅展示/复现。
	var old_seed_mode := str(room.config.get("seed_mode", "random")).strip_edges()
	var new_seed_mode := old_seed_mode
	if patch.has("seed_mode"):
		new_seed_mode = str(patch.get("seed_mode", "random")).strip_edges()

	if new_seed_mode == "fixed":
		if not patch.has("seed"):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
			return
	elif new_seed_mode == "random":
		var seed_cur := int(room.config.get("seed", 0))
		if old_seed_mode != "random":
			seed_cur = 0
		if seed_cur <= 0:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			seed_cur = int(rng.randi())
		patch["seed"] = seed_cur

	var ur = room.update_config(patch)
	if not ur.ok:
		send_request_rejected(peer_id, request_id, "update_config_failed", ur.error)
		return

	broadcast_room_state(room)
	broadcast_room_list("")

func handle_rpc_leave_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)

	var lr = _net._room_manager.leave_room(peer_id)
	if not lr.ok:
		send_request_rejected(peer_id, request_id, "leave_room_failed", lr.error)
		return

	var removed := bool(lr.value.get("removed", false))
	if room != null and not removed:
		broadcast_room_state(room)
	broadcast_room_list("")

	_net.rpc_id(peer_id, "rpc_room_state", empty_room_state())

func handle_rpc_start_game(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		send_request_rejected(peer_id, request_id, "not_host", "Only host can start game")
		return

	var sr = room.start_game()
	if not sr.ok:
		send_request_rejected(peer_id, request_id, "start_game_failed", sr.error)
		return

	broadcast_room_state(room)
	broadcast_room_list("")

	var payload_val: Dictionary = Dictionary(sr.value)
	var payload := {
		"player_id_by_peer_id": Dictionary(payload_val.get("player_id_by_peer_id", {})),
		"config": Dictionary(payload_val.get("config", {})),
	}

	for pid in room.get_peer_ids():
		_net.rpc_id(int(pid), "rpc_game_started", payload)

func handle_rpc_action_request(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "actor_missing", "No player mapping for peer")
		return

	var action_id := str(request.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		send_request_rejected(peer_id, request_id, "invalid_params", "action_id is empty")
		return
	var params_val = request.get("params", null)
	var params: Dictionary = {}
	if params_val is Dictionary:
		params = Dictionary(params_val)

	var state = room.game_engine.get_state()
	if server_is_player_forfeited(state, actor_id):
		send_request_rejected(peer_id, request_id, "forfeited_readonly", "Player has forfeited (spectator, read-only)")
		return

	var cmd = CommandClass.create(action_id, actor_id, params)
	var r = room.game_engine.execute_command(cmd)
	if not r.ok:
		send_request_rejected(peer_id, request_id, "action_failed", r.error)
		return

	broadcast_command_applied(room, cmd)
	server_drain_forfeited_auto_steps(room)

func handle_rpc_resync_request(_request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, "", "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, "", "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, "", "engine_missing", "Room engine missing")
		return

	var archive_r = room.game_engine.create_archive()
	if not archive_r.ok:
		send_request_rejected(peer_id, "", "resync_failed", archive_r.error)
		return

	_net.rpc_id(peer_id, "rpc_resync_archive", {
		"archive": Dictionary(archive_r.value).duplicate(true),
	})

func handle_rpc_rewind_to_turn_start(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	# Spectator：只读，不允许发起回退（避免影响对局）
	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot request rewind")
		return

	# 仅允许“当前玩家”发起回退（避免旁观/非当前回合玩家影响对局）。
	var state = room.game_engine.get_state()
	if state == null:
		send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING and int(state.get_current_player_id()) != actor_id:
		send_request_rejected(peer_id, request_id, "not_current_player", "Only current player can request rewind")
		return

	if not room.has_method("rewind_to_current_player_turn_start"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rewind")
		return

	var rr = room.rewind_to_current_player_turn_start(false)
	if not rr.ok:
		send_request_rejected(peer_id, request_id, "rewind_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		send_request_rejected(peer_id, request_id, "rewind_failed", "rewind result type invalid")
		return

	var payload: Dictionary = Dictionary(rr.value)
	var out := {
		"request_id": request_id,
		"target_index": int(payload.get("target_index", -1)),
		"before_index": int(payload.get("before_index", payload.get("current_index", -1))),
		"history_size": int(payload.get("history_size", -1)),
		"state_hash": str(payload.get("state_hash", "")),
		"noop": bool(payload.get("noop", false)),
	}

	# 广播元数据：各客户端本地 rewind + truncate，避免发送大 archive 导致 WebSocket buffer 溢出。
	if room.has_method("get_peer_ids"):
		for pid in Array(room.get_peer_ids()):
			var target_peer_id := int(pid)
			if target_peer_id <= 0:
				continue
			_net.rpc_id(target_peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})
	else:
		_net.rpc_id(peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})

	broadcast_room_state(room)

func broadcast_command_applied(room, cmd) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null or cmd == null:
		return
	if room.game_engine == null:
		return
	var state_hash := ""
	var state = room.game_engine.get_state()
	if state != null and state.has_method("compute_hash"):
		state_hash = str(state.compute_hash())
	var payload := {
		"cmd": cmd.to_dict(),
		"state_hash": state_hash,
	}
	for pid in room.get_peer_ids():
		_net.rpc_id(int(pid), "rpc_command_applied", payload)

func server_is_player_forfeited(state, player_id: int) -> bool:
	if state == null:
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	return bool(Dictionary(p_val).get("forfeited", false))

func server_pick_order_of_business_position(state) -> int:
	if state == null or not (state.round_state is Dictionary):
		return -1
	var oob_val = Dictionary(state.round_state).get("order_of_business", null)
	if not (oob_val is Dictionary):
		return -1
	var oob: Dictionary = oob_val
	var picks_val = oob.get("picks", null)
	if not (picks_val is Array):
		return -1
	var picks: Array = picks_val
	for pos in range(picks.size() - 1, -1, -1):
		if int(picks[pos]) == -1:
			return pos
	return -1

func server_try_auto_submit_forfeited_restructuring(room) -> bool:
	if room == null or room.game_engine == null:
		return false
	var state = room.game_engine.get_state()
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return false
	if int(state.round_number) <= 1:
		return false
	if not (state.round_state is Dictionary):
		return false
	var r_val = Dictionary(state.round_state).get("restructuring", null)
	if not (r_val is Dictionary):
		return false
	var r: Dictionary = r_val
	var submitted_val = r.get("submitted", null)
	if not (submitted_val is Dictionary):
		return false
	var submitted: Dictionary = submitted_val

	var any := false
	for pid in range(state.players.size()):
		if not server_is_player_forfeited(state, pid):
			continue
		if bool(submitted.get(pid, false)):
			continue
		var cmd = CommandClass.create("submit_restructuring", pid, {})
		var exec_r = room.game_engine.execute_command(cmd)
		if not exec_r.ok:
			GameLog.error("NetClient", "auto submit_restructuring failed: %s" % exec_r.error)
			return any
		broadcast_command_applied(room, cmd)
		any = true
	return any

func server_drain_forfeited_auto_steps(room) -> void:
	if room == null or room.game_engine == null:
		return

	var safety := 0
	while safety < 128:
		safety += 1
		var state = room.game_engine.get_state()
		if state == null:
			return

		if server_try_auto_submit_forfeited_restructuring(room):
			continue

		var current_pid := int(state.get_current_player_id())
		if current_pid < 0:
			return
		if not server_is_player_forfeited(state, current_pid):
			return

		var cmd = null
		if str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			cmd = CommandClass.create("select_reserve_card", current_pid, {"selected_index": 0})
		elif str(state.phase) == DefsClass.PHASE_RESTRUCTURING and int(state.round_number) > 1:
			cmd = CommandClass.create("submit_restructuring", current_pid, {})
		elif str(state.phase) == DefsClass.PHASE_ORDER_OF_BUSINESS:
			var pos := server_pick_order_of_business_position(state)
			if pos < 0:
				return
			cmd = CommandClass.create("choose_turn_order", current_pid, {"position": pos})
		elif str(state.phase) == DefsClass.PHASE_WORKING:
			cmd = CommandClass.create(ActionIdsClass.SKIP_SUB_PHASE, current_pid, {})
		else:
			cmd = CommandClass.create(ActionIdsClass.SKIP, current_pid, {})

		var exec_r2 = room.game_engine.execute_command(cmd)
		if not exec_r2.ok:
			GameLog.error("NetClient", "auto step failed: %s (action=%s)" % [exec_r2.error, str(cmd.action_id)])
			return
		broadcast_command_applied(room, cmd)

	GameLog.error("NetClient", "auto steps exceeded safety limit")
