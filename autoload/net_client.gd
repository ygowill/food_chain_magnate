# 联机会话层（Client/Server 共用 RPC 节点）
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const NetClientInternalClass = preload("res://autoload/net_client_internal.gd")

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
var _internal = null

func _ready() -> void:
	_ensure_internal()
	_ensure_signal_connections()

func _ensure_internal() -> void:
	if _internal == null or not is_instance_valid(_internal):
		_internal = NetClientInternalClass.new()
		_internal.setup(self)

func start_server(port: int, bind_address: String = "0.0.0.0"):
	shutdown()
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = 4 * 1024 * 1024
	_peer.outbound_buffer_size = 4 * 1024 * 1024
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

func connect_to_server(url: String):
	shutdown()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = url

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = 4 * 1024 * 1024
	_peer.outbound_buffer_size = 4 * 1024 * 1024
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

func request_update_player_profile(profile: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not is_online_client_connected():
		return
	if profile is Dictionary:
		NetContext.player_profile = Dictionary(profile).duplicate(true)
	_send_client_hello()

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
	# 允许已在房间中的客户端更新自己的 profile（昵称/颜色）。
	# 重要：不新增 @rpc 方法，避免 dedicated server 与客户端版本不一致时触发 checksum mismatch。
	var room = _room_manager.get_room_by_peer(peer_id) if _room_manager != null else null
	if room != null and room.has_method("update_peer_profile"):
		var ur = room.update_peer_profile(peer_id, Dictionary(_profile_by_peer_id[peer_id]))
		if ur.ok:
			_broadcast_room_state(room)
			_broadcast_room_list("")
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
	_ensure_internal()
	_internal.handle_rpc_create_room(request)

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

	var jr = _room_manager.join_room(peer_id, profile, room_code, room_password)
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
		var archive_r = room.game_engine.create_archive()
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

	var ur = room.update_config(patch)
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

	var lr = _room_manager.leave_room(peer_id)
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

	var sr = room.start_game()
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

	var state = room.game_engine.get_state()
	if _server_is_player_forfeited(state, actor_id):
		_send_request_rejected(peer_id, request_id, "forfeited_readonly", "Player has forfeited (spectator, read-only)")
		return

	var cmd = CommandClass.create(action_id, actor_id, params)
	var r = room.game_engine.execute_command(cmd)
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

	var archive_r = room.game_engine.create_archive()
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
	var state = room.game_engine.get_state()
	if state == null:
		_send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING and int(state.get_current_player_id()) != actor_id:
		_send_request_rejected(peer_id, request_id, "not_current_player", "Only current player can request rewind")
		return

	if not room.has_method("rewind_to_current_player_turn_start"):
		_send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rewind")
		return

	var rr = room.rewind_to_current_player_turn_start(false)
	if not rr.ok:
		_send_request_rejected(peer_id, request_id, "rewind_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		_send_request_rejected(peer_id, request_id, "rewind_failed", "rewind result type invalid")
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
			rpc_id(target_peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})
	else:
		rpc_id(peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})

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
	var init_r = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
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
	_ensure_internal()
	_internal.ensure_signal_connections()

func _on_peer_connected(peer_id: int) -> void:
	_ensure_internal()
	_internal.on_peer_connected(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_ensure_internal()
	_internal.on_peer_disconnected(peer_id)

func _on_connected_to_server() -> void:
	_ensure_internal()
	_internal.on_connected_to_server()

func _on_connection_failed() -> void:
	_ensure_internal()
	_internal.on_connection_failed()

func _on_server_disconnected() -> void:
	_ensure_internal()
	_internal.on_server_disconnected()

func _send_client_hello() -> void:
	_ensure_internal()
	_internal.send_client_hello()

func _send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	_ensure_internal()
	_internal.send_request_rejected(peer_id, request_id, code, message)

func _broadcast_room_state(room) -> void:
	_ensure_internal()
	_internal.broadcast_room_state(room)

func _empty_room_state() -> Dictionary:
	_ensure_internal()
	return _internal.empty_room_state()

func _send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	_ensure_internal()
	_internal.send_room_list_to_peer(peer_id, request_id)

func _broadcast_room_list(request_id: String) -> void:
	_ensure_internal()
	_internal.broadcast_room_list(request_id)

func _broadcast_command_applied(room, cmd) -> void:
	_ensure_internal()
	_internal.broadcast_command_applied(room, cmd)

func _server_is_player_forfeited(state, player_id: int) -> bool:
	_ensure_internal()
	return _internal.server_is_player_forfeited(state, player_id)

func _server_pick_order_of_business_position(state) -> int:
	_ensure_internal()
	return _internal.server_pick_order_of_business_position(state)

func _server_try_auto_submit_forfeited_restructuring(room) -> bool:
	_ensure_internal()
	return _internal.server_try_auto_submit_forfeited_restructuring(room)

func _server_drain_forfeited_auto_steps(room) -> void:
	_ensure_internal()
	_internal.server_drain_forfeited_auto_steps(room)

func _next_request_id() -> String:
	_request_counter += 1
	return "%d-%d" % [Time.get_unix_time_from_system(), _request_counter]
