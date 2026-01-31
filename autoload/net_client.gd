# 联机会话层（Client/Server 共用 RPC 节点）
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

signal connected()
signal disconnected(reason: String)
signal room_list_updated(rooms: Array)
signal room_state_updated(room_state: Dictionary)
signal request_rejected(request_id: String, code: String, message: String)
signal game_started(payload: Dictionary)
signal command_applied(cmd_dict: Dictionary, state_hash: String)
signal resync_archive_received(archive: Dictionary)

var _peer: WebSocketMultiplayerPeer = null

var _room_manager = null
var _profile_by_peer_id: Dictionary = {} # peer_id -> profile

var _client_transport_connected: bool = false
var _request_counter: int = 0
var _pending_resync_archive: Dictionary = {}

func _ready() -> void:
	_ensure_signal_connections()

func start_server(port: int, bind_address: String = "*") -> Result:
	shutdown()
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port, bind_address)
	if err != OK:
		_peer = null
		NetContext.reset()
		return Result.failure("WebSocket server create_server failed: %s" % str(err))

	multiplayer.multiplayer_peer = _peer
	_room_manager = RoomManagerClass.new()
	_profile_by_peer_id = {}
	_client_transport_connected = false

	GameLog.info("NetClient", "Server started on %s:%d" % [bind_address, port])
	return Result.success()

func connect_to_server(url: String) -> Result:
	shutdown()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = url

	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(url)
	if err != OK:
		_peer = null
		NetContext.reset()
		return Result.failure("WebSocket client create_client failed: %s" % str(err))

	multiplayer.multiplayer_peer = _peer
	_client_transport_connected = false
	GameLog.info("NetClient", "Connecting to %s" % url)
	return Result.success()

func shutdown() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_room_manager = null
	_profile_by_peer_id = {}
	_client_transport_connected = false
	_pending_resync_archive = {}
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetContext.reset()

func is_online_client_connected() -> bool:
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT and _client_transport_connected

func request_create_room(desired_player_count: int, room_password: String, config: Dictionary = {}) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"desired_player_count": desired_player_count,
		"join_policy": "password",
		"room_password": room_password,
	}
	for k in config.keys():
		payload[str(k)] = config.get(k, null)
	rpc_id(1, "rpc_create_room", payload)
	return request_id

func request_list_rooms() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_list_rooms", payload)
	return request_id

func request_join_room(room_code: String, room_password: String) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"room_code": room_code,
		"room_password": room_password,
	}
	rpc_id(1, "rpc_join_room", payload)
	return request_id

func request_leave_room() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_leave_room", payload)
	NetContext.room_state = {}
	room_state_updated.emit(NetContext.room_state)
	return request_id

func request_update_room_config(config_patch: Dictionary) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"config_patch": config_patch.duplicate(true),
	}
	rpc_id(1, "rpc_update_room_config", payload)
	return request_id

func request_start_game() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_start_game", payload)
	return request_id

func request_action(action_id: String, params: Dictionary) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"action_id": action_id,
		"params": params.duplicate(true),
	}
	rpc_id(1, "rpc_action_request", payload)
	return request_id

func request_resync() -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not is_online_client_connected():
		return
	rpc_id(1, "rpc_resync_request", {})

func request_rewind_to_turn_start() -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	rpc_id(1, "rpc_rewind_to_turn_start", {"request_id": request_id})
	return request_id

func take_pending_resync_archive() -> Dictionary:
	var out: Dictionary = _pending_resync_archive.duplicate(true)
	_pending_resync_archive = {}
	return out

@rpc("any_peer", "reliable")
func rpc_client_hello(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var protocol_version := int(request.get("protocol_version", 0))
	if protocol_version != NetContext.PROTOCOL_VERSION:
		_send_request_rejected(peer_id, request_id, "protocol_version_mismatch", "Protocol version mismatch")
		return

	var profile: Dictionary = Dictionary(request.get("player_profile", {}))
	_profile_by_peer_id[peer_id] = {
		"name": str(profile.get("name", "玩家")),
		"color_index": int(profile.get("color_index", 0)),
	}
	_send_room_list_to_peer(peer_id, "")

@rpc("any_peer", "reliable")
func rpc_list_rooms(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		_send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before ListRooms")
		return

	_send_room_list_to_peer(peer_id, request_id)

@rpc("any_peer", "reliable")
func rpc_create_room(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		_send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before CreateRoom")
		return

	var desired_player_count := int(request.get("desired_player_count", 0))
	if desired_player_count < Globals.MIN_PLAYERS or desired_player_count > Globals.MAX_PLAYERS:
		_send_request_rejected(peer_id, request_id, "invalid_player_count", "desired_player_count out of range")
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
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		config["seed_mode"] = sm
	if request.has("seed"):
		var sv = request.get("seed", null)
		if not (sv is int or sv is float):
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		config["seed"] = int(sv)
	if str(config.get("seed_mode", "random")) == "fixed":
		if not request.has("seed"):
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
			return

	if request.has("allow_spectators"):
		var av = request.get("allow_spectators", null)
		if not (av is bool):
			_send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		config["allow_spectators"] = bool(av)

	if request.has("enabled_modules_v2"):
		var mv = request.get("enabled_modules_v2", null)
		if not (mv is Array):
			_send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
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
			_send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		config["modules_v2_base_dir"] = bd

	# seed_mode=random：由 server 固定生成 seed，以便大厅展示与可复现。
	if str(config.get("seed_mode", "random")) == "random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		config["seed"] = int(rng.randi())

	var cr: Result = _room_manager.create_room(peer_id, profile, room_password, config)
	if not cr.ok:
		_send_request_rejected(peer_id, request_id, "create_room_failed", cr.error)
		return

	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		_send_request_rejected(peer_id, request_id, "create_room_failed", "Missing room in result")
		return

	_broadcast_room_state(room)
	_broadcast_room_list("")

@rpc("any_peer", "reliable")
func rpc_join_room(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		_send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before JoinRoom")
		return

	var room_code := str(request.get("room_code", "")).strip_edges().to_upper()
	var room_password := str(request.get("room_password", ""))

	var jr: Result = _room_manager.join_room(peer_id, profile, room_code, room_password)
	if not jr.ok:
		_send_request_rejected(peer_id, request_id, "join_room_failed", jr.error)
		return

	var room = Dictionary(jr.value).get("room", null)
	if room == null:
		_send_request_rejected(peer_id, request_id, "join_room_failed", "Missing room in result")
		return

	_broadcast_room_state(room)
	_broadcast_room_list("")
	if str(room.status) == "InGame" and room.game_engine != null:
		var payload := {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
		}
		rpc_id(peer_id, "rpc_game_started", payload)
		var archive_r: Result = room.game_engine.create_archive()
		if archive_r.ok:
			rpc_id(peer_id, "rpc_resync_archive", {
				"archive": Dictionary(archive_r.value).duplicate(true),
			})

@rpc("any_peer", "reliable")
func rpc_update_room_config(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var room = _room_manager.get_room_by_peer(peer_id)
	if room == null:
		_send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		_send_request_rejected(peer_id, request_id, "not_host", "Only host can update config")
		return

	var patch_raw = request.get("config_patch", null)
	if not (patch_raw is Dictionary):
		_send_request_rejected(peer_id, request_id, "invalid_params", "config_patch must be Dictionary")
		return
	var patch: Dictionary = Dictionary(patch_raw)

	if patch.has("desired_player_count"):
		var v = patch.get("desired_player_count", null)
		if not (v is int or v is float):
			_send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count must be int")
			return
		var n := int(v)
		if n < Globals.MIN_PLAYERS or n > Globals.MAX_PLAYERS:
			_send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count out of range")
			return
		if n < int(room.get_player_count()):
			_send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count < current players")
			return
		patch["desired_player_count"] = n

	if patch.has("seed_mode"):
		var sm := str(patch.get("seed_mode", "")).strip_edges()
		if sm != "random" and sm != "fixed":
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		patch["seed_mode"] = sm

	if patch.has("seed"):
		var sv = patch.get("seed", null)
		if not (sv is int or sv is float):
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		patch["seed"] = int(sv)

	if patch.has("allow_spectators"):
		var av = patch.get("allow_spectators", null)
		if not (av is bool):
			_send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		patch["allow_spectators"] = bool(av)

	if patch.has("enabled_modules_v2"):
		var mv = patch.get("enabled_modules_v2", null)
		if not (mv is Array):
			_send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
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
			_send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		patch["modules_v2_base_dir"] = bd

	# seed_mode=random：保持一个 server 选定的 seed（不在 StartGame 时再重掷），便于大厅展示/复现。
	var old_seed_mode := str(room.config.get("seed_mode", "random")).strip_edges()
	var new_seed_mode := old_seed_mode
	if patch.has("seed_mode"):
		new_seed_mode = str(patch.get("seed_mode", "random")).strip_edges()

	if new_seed_mode == "fixed":
		if not patch.has("seed"):
			_send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
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

	var ur: Result = room.update_config(patch)
	if not ur.ok:
		_send_request_rejected(peer_id, request_id, "update_config_failed", ur.error)
		return

	_broadcast_room_state(room)
	_broadcast_room_list("")

@rpc("any_peer", "reliable")
func rpc_leave_room(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var room = _room_manager.get_room_by_peer(peer_id)

	var lr: Result = _room_manager.leave_room(peer_id)
	if not lr.ok:
		_send_request_rejected(peer_id, request_id, "leave_room_failed", lr.error)
		return

	var removed := bool(lr.value.get("removed", false))
	if room != null and not removed:
		_broadcast_room_state(room)
	_broadcast_room_list("")

	rpc_id(peer_id, "rpc_room_state", _empty_room_state())

@rpc("any_peer", "reliable")
func rpc_start_game(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var room = _room_manager.get_room_by_peer(peer_id)
	if room == null:
		_send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		_send_request_rejected(peer_id, request_id, "not_host", "Only host can start game")
		return

	var sr: Result = room.start_game()
	if not sr.ok:
		_send_request_rejected(peer_id, request_id, "start_game_failed", sr.error)
		return

	_broadcast_room_state(room)
	_broadcast_room_list("")

	var payload_val: Dictionary = Dictionary(sr.value)
	var payload := {
		"player_id_by_peer_id": Dictionary(payload_val.get("player_id_by_peer_id", {})),
		"config": Dictionary(payload_val.get("config", {})),
	}

	for pid in room.get_peer_ids():
		rpc_id(int(pid), "rpc_game_started", payload)

@rpc("any_peer", "reliable")
func rpc_action_request(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var room = _room_manager.get_room_by_peer(peer_id)
	if room == null:
		_send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		_send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		_send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
	if actor_id < 0:
		_send_request_rejected(peer_id, request_id, "actor_missing", "No player mapping for peer")
		return

	var action_id := str(request.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		_send_request_rejected(peer_id, request_id, "invalid_params", "action_id is empty")
		return
	var params_val = request.get("params", null)
	var params: Dictionary = {}
	if params_val is Dictionary:
		params = Dictionary(params_val)

	var state: GameState = room.game_engine.get_state()
	if _server_is_player_forfeited(state, actor_id):
		_send_request_rejected(peer_id, request_id, "forfeited_readonly", "Player has forfeited (spectator, read-only)")
		return

	var cmd = CommandClass.create(action_id, actor_id, params)
	var r: Result = room.game_engine.execute_command(cmd)
	if not r.ok:
		_send_request_rejected(peer_id, request_id, "action_failed", r.error)
		return

	_broadcast_command_applied(room, cmd)
	_server_drain_forfeited_auto_steps(room)

@rpc("any_peer", "reliable")
func rpc_resync_request(_request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var room = _room_manager.get_room_by_peer(peer_id)
	if room == null:
		_send_request_rejected(peer_id, "", "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		_send_request_rejected(peer_id, "", "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		_send_request_rejected(peer_id, "", "engine_missing", "Room engine missing")
		return

	var archive_r: Result = room.game_engine.create_archive()
	if not archive_r.ok:
		_send_request_rejected(peer_id, "", "resync_failed", archive_r.error)
		return

	rpc_id(peer_id, "rpc_resync_archive", {
		"archive": Dictionary(archive_r.value).duplicate(true),
	})

@rpc("any_peer", "reliable")
func rpc_rewind_to_turn_start(request: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var request_id := str(request.get("request_id", ""))
	var room = _room_manager.get_room_by_peer(peer_id)
	if room == null:
		_send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		_send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		_send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	# Spectator：只读，不允许发起回退（避免影响对局）
	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
	if actor_id < 0:
		_send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot request rewind")
		return

	# 仅允许“当前玩家”发起回退（避免旁观/非当前回合玩家影响对局）。
	var state: GameState = room.game_engine.get_state()
	if state == null:
		_send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING and int(state.get_current_player_id()) != actor_id:
		_send_request_rejected(peer_id, request_id, "not_current_player", "Only current player can request rewind")
		return

	if not room.has_method("rewind_to_current_player_turn_start"):
		_send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rewind")
		return

	var rr: Result = room.rewind_to_current_player_turn_start()
	if not rr.ok:
		_send_request_rejected(peer_id, request_id, "rewind_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		_send_request_rejected(peer_id, request_id, "rewind_failed", "rewind result type invalid")
		return

	var payload: Dictionary = Dictionary(rr.value)
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		_send_request_rejected(peer_id, request_id, "rewind_failed", "archive missing")
		return
	var archive: Dictionary = Dictionary(archive_val).duplicate(true)

	# 广播 archive：所有在线成员一起回退，保证状态一致。
	if room.has_method("get_peer_ids"):
		for pid in Array(room.get_peer_ids()):
			var target_peer_id := int(pid)
			if target_peer_id <= 0:
				continue
			rpc_id(target_peer_id, "rpc_resync_archive", {"archive": archive})
	else:
		# Fallback：至少把结果发给请求方（避免卡死）。
		rpc_id(peer_id, "rpc_resync_archive", {"archive": archive})

	_broadcast_room_state(room)

@rpc("authority", "reliable")
func rpc_room_state(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	NetContext.room_state = payload.duplicate(true)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state)
	room_state_updated.emit(NetContext.room_state)

@rpc("authority", "reliable")
func rpc_room_list(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var rooms_val = payload.get("rooms", null)
	if not (rooms_val is Array):
		return
	NetContext.room_list = Array(rooms_val).duplicate(true)
	room_list_updated.emit(NetContext.room_list.duplicate(true))

@rpc("authority", "reliable")
func rpc_game_started(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var mapping_val = payload.get("player_id_by_peer_id", null)
	if not (mapping_val is Dictionary):
		return
	var cfg_val = payload.get("config", null)
	if not (cfg_val is Dictionary):
		return
	var mapping: Dictionary = Dictionary(mapping_val)
	var config: Dictionary = Dictionary(cfg_val)

	var my_peer_id := int(multiplayer.get_unique_id())
	var local_pid := -1
	if mapping.has(my_peer_id):
		local_pid = int(mapping.get(my_peer_id, -1))
	elif mapping.has(str(my_peer_id)):
		local_pid = int(mapping.get(str(my_peer_id), -1))
	NetContext.local_player_id = local_pid

	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()

	var player_count := int(config.get("desired_player_count", 0))
	var seed := int(config.get("seed", 0))
	var base_dir := str(config.get("modules_v2_base_dir", "")).strip_edges()
	var enabled_modules: Array[String] = []
	var mods_val = config.get("enabled_modules_v2", null)
	if mods_val is Array:
		for it in Array(mods_val):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			enabled_modules.append(s)

	var logo_choices: Array[int] = []
	var lc_val = config.get("restaurant_logo_choices_by_player", null)
	if lc_val is Array:
		for it2 in Array(lc_val):
			if it2 is int or it2 is float:
				logo_choices.append(int(it2))
	while logo_choices.size() < player_count:
		logo_choices.append(-1)

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
	if not init_r.ok:
		GameLog.error("NetClient", "Online client engine initialize failed: %s" % init_r.error)
		return

	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state if NetContext != null else {})

	game_started.emit(payload.duplicate(true))

@rpc("authority", "reliable")
func rpc_command_applied(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var cmd_dict_val = payload.get("cmd", null)
	if not (cmd_dict_val is Dictionary):
		return
	var state_hash := str(payload.get("state_hash", ""))
	command_applied.emit(Dictionary(cmd_dict_val), state_hash)

@rpc("authority", "reliable")
func rpc_resync_archive(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		return
	_pending_resync_archive = Dictionary(archive_val).duplicate(true)
	resync_archive_received.emit(_pending_resync_archive.duplicate(true))

@rpc("authority", "reliable")
func rpc_request_rejected(payload: Dictionary) -> void:
	var request_id := str(payload.get("request_id", ""))
	var code := str(payload.get("code", ""))
	var message := str(payload.get("message", ""))
	request_rejected.emit(request_id, code, message)

func _ensure_signal_connections() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if NetContext.mode == NetContext.Mode.ONLINE_SERVER:
		GameLog.info("NetClient", "Peer connected: %d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	_profile_by_peer_id.erase(peer_id)
	var room = _room_manager.get_room_by_peer(peer_id)
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
	var rr: Result = _room_manager.disconnect_peer(peer_id) if in_game else _room_manager.leave_room(peer_id)
	if rr.ok:
		removed = bool(rr.value.get("removed", false))

	if in_game and actor_id >= 0 and room.game_engine != null:
		var cmd = CommandClass.create("forfeit_player", actor_id, {})
		var fr: Result = room.game_engine.execute_command(cmd)
		if fr.ok:
			_broadcast_command_applied(room, cmd)
			_server_drain_forfeited_auto_steps(room)
		else:
			GameLog.error("NetClient", "forfeit_player failed: %s" % fr.error)

	if rr.ok and room != null and not removed:
		_broadcast_room_state(room)
		_broadcast_room_list("")
	elif rr.ok and removed:
		_broadcast_room_list("")

func _on_connected_to_server() -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_client_transport_connected = true
	_send_client_hello()
	connected.emit()

func _on_connection_failed() -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_client_transport_connected = false
	disconnected.emit("connection_failed")
	shutdown()

func _on_server_disconnected() -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_client_transport_connected = false
	disconnected.emit("server_disconnected")
	shutdown()

func _send_client_hello() -> void:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": Globals.get_version(),
		"schema_version": Globals.SCHEMA_VERSION,
		"player_profile": NetContext.player_profile.duplicate(true),
	}
	rpc_id(1, "rpc_client_hello", payload)

func _send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	rpc_id(peer_id, "rpc_request_rejected", {
		"request_id": request_id,
		"code": code,
		"message": message,
	})

func _broadcast_room_state(room) -> void:
	var state: Dictionary = room.to_room_state_dict()
	for peer_id in room.get_peer_ids():
		rpc_id(peer_id, "rpc_room_state", state)

func _empty_room_state() -> Dictionary:
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

func _send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var rooms: Array[Dictionary] = []
	if _room_manager != null and _room_manager.has_method("list_room_summaries"):
		rooms = _room_manager.list_room_summaries()
	rpc_id(peer_id, "rpc_room_list", {
		"request_id": request_id,
		"rooms": rooms,
	})

func _broadcast_room_list(request_id: String) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	for peer_id_val in _profile_by_peer_id.keys():
		_send_room_list_to_peer(int(peer_id_val), request_id)

func _broadcast_command_applied(room, cmd: Command) -> void:
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
		rpc_id(int(pid), "rpc_command_applied", payload)

func _server_is_player_forfeited(state: GameState, player_id: int) -> bool:
	if state == null:
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	return bool(Dictionary(p_val).get("forfeited", false))

func _server_pick_order_of_business_position(state: GameState) -> int:
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

func _server_try_auto_submit_forfeited_restructuring(room) -> bool:
	if room == null or room.game_engine == null:
		return false
	var state: GameState = room.game_engine.get_state()
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
		if not _server_is_player_forfeited(state, pid):
			continue
		if bool(submitted.get(pid, false)):
			continue
		var cmd = CommandClass.create("submit_restructuring", pid, {})
		var exec_r: Result = room.game_engine.execute_command(cmd)
		if not exec_r.ok:
			GameLog.error("NetClient", "auto submit_restructuring failed: %s" % exec_r.error)
			return any
		_broadcast_command_applied(room, cmd)
		any = true
	return any

func _server_drain_forfeited_auto_steps(room) -> void:
	if room == null or room.game_engine == null:
		return

	var safety := 0
	while safety < 128:
		safety += 1
		var state: GameState = room.game_engine.get_state()
		if state == null:
			return

		if _server_try_auto_submit_forfeited_restructuring(room):
			continue

		var current_pid := int(state.get_current_player_id())
		if current_pid < 0:
			return
		if not _server_is_player_forfeited(state, current_pid):
			return

		var cmd: Command = null
		if str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			cmd = CommandClass.create("select_reserve_card", current_pid, {"selected_index": 0})
		elif str(state.phase) == DefsClass.PHASE_RESTRUCTURING and int(state.round_number) > 1:
			cmd = CommandClass.create("submit_restructuring", current_pid, {})
		elif str(state.phase) == DefsClass.PHASE_ORDER_OF_BUSINESS:
			var pos := _server_pick_order_of_business_position(state)
			if pos < 0:
				return
			cmd = CommandClass.create("choose_turn_order", current_pid, {"position": pos})
		elif str(state.phase) == DefsClass.PHASE_WORKING:
			cmd = CommandClass.create(ActionIdsClass.SKIP_SUB_PHASE, current_pid, {})
		else:
			cmd = CommandClass.create(ActionIdsClass.SKIP, current_pid, {})

		var exec_r2: Result = room.game_engine.execute_command(cmd)
		if not exec_r2.ok:
			GameLog.error("NetClient", "auto step failed: %s (action=%s)" % [exec_r2.error, str(cmd.action_id)])
			return
		_broadcast_command_applied(room, cmd)

	GameLog.error("NetClient", "auto steps exceeded safety limit")

func _next_request_id() -> String:
	_request_counter += 1
	return "%d-%d" % [Time.get_unix_time_from_system(), _request_counter]
