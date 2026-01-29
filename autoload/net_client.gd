# 联机会话层（Client/Server 共用 RPC 节点）
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const CommandClass = preload("res://core/types/command.gd")

signal connected()
signal disconnected(reason: String)
signal room_state_updated(room_state: Dictionary)
signal request_rejected(request_id: String, code: String, message: String)
signal game_started(payload: Dictionary)
signal command_applied(cmd_dict: Dictionary, state_hash: String)

var _peer: WebSocketMultiplayerPeer = null

var _room_manager = null
var _profile_by_peer_id: Dictionary = {} # peer_id -> profile

var _client_transport_connected: bool = false
var _request_counter: int = 0

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

	var cr: Result = _room_manager.create_room(peer_id, profile, room_password, config)
	if not cr.ok:
		_send_request_rejected(peer_id, request_id, "create_room_failed", cr.error)
		return

	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		_send_request_rejected(peer_id, request_id, "create_room_failed", "Missing room in result")
		return

	_broadcast_room_state(room)

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

	var ur: Result = room.update_config(patch)
	if not ur.ok:
		_send_request_rejected(peer_id, request_id, "update_config_failed", ur.error)
		return

	_broadcast_room_state(room)

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

	if room != null and not bool(lr.value.get("removed", false)):
		_broadcast_room_state(room)

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

	var cmd = CommandClass.create(action_id, actor_id, params)
	var r: Result = room.game_engine.execute_command(cmd)
	if not r.ok:
		_send_request_rejected(peer_id, request_id, "action_failed", r.error)
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

@rpc("authority", "reliable")
func rpc_room_state(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	NetContext.room_state = payload.duplicate(true)
	room_state_updated.emit(NetContext.room_state)

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
	var lr: Result = _room_manager.leave_room(peer_id)
	if lr.ok and room != null and not bool(lr.value.get("removed", false)):
		_broadcast_room_state(room)

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
		"config": {},
		"status": "Lobby",
	}

func _next_request_id() -> String:
	_request_counter += 1
	return "%d-%d" % [Time.get_unix_time_from_system(), _request_counter]
