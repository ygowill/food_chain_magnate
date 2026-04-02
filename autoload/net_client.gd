# 联机会话层（Client/Server 共用 RPC 节点）
# 日志分级：高频链路（如轮询/命令流）使用 DEBUG，关键状态迁移使用 INFO/WARN/ERROR。
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const CommandClass = preload("res://core/types/command.gd")
const ResultClass = preload("res://core/types/result.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
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
		GameLog.error("NetClient", "start_server failed bind=%s port=%d err=%s" % [bind_address, port, str(err)])
		NetContext.reset()
		return ResultClass.failure("WebSocket server create_server failed: %s" % str(err))

	multiplayer.multiplayer_peer = _peer
	_room_manager = RoomManagerClass.new()
	_profile_by_peer_id = {}
	_client_transport_connected = false

	GameLog.info("NetClient", "Server started on %s:%d" % [bind_address, port])
	return ResultClass.success()

func connect_to_server(url: String, preserve_context: bool = false):
	shutdown(not preserve_context)
	var parsed := _parse_connect_token_from_url(str(url))
	var connect_url: String = str(parsed.get("url", str(url)))
	var connect_token: String = str(parsed.get("connect_token", ""))
	if connect_token.is_empty():
		GameLog.error("NetClient", "connect_to_server missing connect_token url=%s" % _safe_text(connect_url))
		if not preserve_context:
			NetContext.reset()
		return ResultClass.failure("connect_token required")
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = connect_url
	NetContext.connect_token = connect_token

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = 4 * 1024 * 1024
	_peer.outbound_buffer_size = 4 * 1024 * 1024
	var err := _peer.create_client(connect_url)
	if err != OK:
		_peer = null
		GameLog.error("NetClient", "connect_to_server failed url=%s err=%s" % [connect_url, str(err)])
		if not preserve_context:
			NetContext.reset()
		return ResultClass.failure("WebSocket client create_client failed: %s" % str(err))

	multiplayer.multiplayer_peer = _peer
	_client_transport_connected = false
	GameLog.info("NetClient", "Connecting to %s" % connect_url)
	return ResultClass.success()

func _parse_connect_token_from_url(url: String) -> Dictionary:
	var out := {
		"url": str(url),
		"connect_token": "",
	}
	var s := str(url).strip_edges()
	if s.is_empty():
		return out

	var q_idx := s.find("?")
	if q_idx < 0:
		return out
	var base := s.substr(0, q_idx)
	var query := s.substr(q_idx + 1)
	if query.is_empty():
		out["url"] = base
		return out

	var parts: PackedStringArray = query.split("&", false)
	var kept: Array[String] = []
	for part in parts:
		var p := str(part).strip_edges()
		if p.is_empty():
			continue
		var kv := p.split("=", false, 1)
		var key := str(kv[0]).strip_edges()
		var value := str(kv[1]) if kv.size() >= 2 else ""
		if key == "token" or key == "connect_token":
			out["connect_token"] = value.uri_decode()
			continue
		kept.append(p)

	out["url"] = base + ("?" + "&".join(kept) if not kept.is_empty() else "")
	return out

func shutdown(reset_context: bool = true) -> void:
	var prev_mode := _mode_name(int(NetContext.mode))
	var prev_connected := _client_transport_connected
	var prev_server_url := _safe_text(str(NetContext.server_url))
	var prev_room_code := _safe_room_code(NetContext.room_state)
	var prev_room_list_count := NetContext.room_list.size() if NetContext.room_list is Array else 0
	var should_log := _peer != null \
		or prev_mode != "HOTSEAT" \
		or prev_connected \
		or prev_room_code != "-" \
		or prev_room_list_count > 0
	if _peer != null:
		_peer.close()
	_peer = null
	_room_manager = null
	_profile_by_peer_id = {}
	_client_transport_connected = false
	_pending_resync_archive = {}
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if reset_context:
		NetContext.reset()
	if should_log:
		GameLog.info(
			"NetClient",
			"Shutdown complete mode=%s connected=%s room=%s room_list=%d server=%s"
				% [prev_mode, str(prev_connected), prev_room_code, prev_room_list_count, prev_server_url]
		)

func is_online_client_connected() -> bool:
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT and _client_transport_connected

func should_preserve_online_context_on_disconnect() -> bool:
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	return true

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
	GameLog.info(
		"NetClient",
		"TX CreateRoom request_id=%s desired_player_count=%d has_password=%s config_keys=%s"
			% [
				request_id,
				desired_player_count,
				str(not room_password.is_empty()),
				str(Array(config.keys()))
			]
	)
	return request_id

func request_list_rooms() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_list_rooms", payload)
	GameLog.debug("NetClient", "TX ListRooms request_id=%s" % request_id)
	return request_id

func request_join_room(room_code: String, room_password: String) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"room_code": room_code,
		"room_password": room_password,
	}
	rpc_id(1, "rpc_join_room", payload)
	GameLog.info(
		"NetClient",
		"TX JoinRoom request_id=%s room_code=%s has_password=%s"
			% [request_id, _safe_text(str(room_code).to_upper()), str(not room_password.is_empty())]
	)
	return request_id

func request_leave_room() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_leave_room", payload)
	GameLog.info("NetClient", "TX LeaveRoom request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)])
	if NetContext != null and NetContext.has_method("clear_online_resume_context"):
		NetContext.clear_online_resume_context()
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
	GameLog.info(
		"NetClient",
		"TX UpdateRoomConfig request_id=%s room=%s patch_keys=%s"
			% [request_id, _safe_room_code(NetContext.room_state), str(Array(config_patch.keys()))]
	)
	return request_id

func request_update_player_profile(profile: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not is_online_client_connected():
		return
	if profile is Dictionary:
		NetContext.player_profile = Dictionary(profile).duplicate(true)
	GameLog.debug(
		"NetClient",
		"TX UpdatePlayerProfile name=%s color_index=%d restaurant_logo_id=%d"
			% [
				_safe_text(str(NetContext.player_profile.get("name", ""))),
				int(NetContext.player_profile.get("color_index", -1)),
				int(NetContext.player_profile.get("restaurant_logo_id", -1))
			]
	)
	_send_client_hello()

func request_start_game() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_start_game", payload)
	GameLog.info("NetClient", "TX StartGame request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)])
	return request_id

func request_action(action_id: String, params: Dictionary) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"action_id": action_id,
		"params": params.duplicate(true),
	}
	rpc_id(1, "rpc_action_request", payload)
	GameLog.debug(
		"NetClient",
		"TX ActionRequest request_id=%s action=%s params_keys=%s"
			% [request_id, _safe_text(action_id), str(Array(params.keys()))]
	)
	return request_id

func request_resync() -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not is_online_client_connected():
		return
	rpc_id(1, "rpc_resync_request", {})
	GameLog.warn("NetClient", "TX ResyncRequest room=%s" % _safe_room_code(NetContext.room_state))

func request_rewind_to_turn_start() -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	rpc_id(1, "rpc_rewind_to_turn_start", {"request_id": request_id})
	GameLog.warn(
		"NetClient",
		"TX RewindToTurnStart request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)]
	)
	return request_id

func take_pending_resync_archive() -> Dictionary:
	var out: Dictionary = _pending_resync_archive.duplicate(true)
	_pending_resync_archive = {}
	if not out.is_empty():
		GameLog.debug("NetClient", "take_pending_resync_archive keys=%s" % str(Array(out.keys())))
	return out

@rpc("any_peer", "reliable")
func rpc_client_hello(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_client_hello(request)

@rpc("any_peer", "reliable")
func rpc_list_rooms(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_list_rooms(request)

@rpc("any_peer", "reliable")
func rpc_create_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_create_room(request)

@rpc("any_peer", "reliable")
func rpc_join_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_join_room(request)

@rpc("any_peer", "reliable")
func rpc_update_room_config(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_update_room_config(request)

@rpc("any_peer", "reliable")
func rpc_leave_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_leave_room(request)

@rpc("any_peer", "reliable")
func rpc_start_game(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_start_game(request)

@rpc("any_peer", "reliable")
func rpc_action_request(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_action_request(request)

@rpc("any_peer", "reliable")
func rpc_resync_request(_request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_request(_request)

@rpc("any_peer", "reliable")
func rpc_rewind_to_turn_start(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_rewind_to_turn_start(request)

@rpc("authority", "reliable")
func rpc_room_state(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_room_state(payload)

@rpc("authority", "reliable")
func rpc_room_list(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_room_list(payload)

@rpc("authority", "reliable")
func rpc_game_started(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_game_started(payload)

@rpc("authority", "reliable")
func rpc_command_applied(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_command_applied(payload)

@rpc("authority", "reliable")
func rpc_resync_archive(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_archive(payload)

@rpc("authority", "reliable")
func rpc_request_rejected(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_request_rejected(payload)

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

func _mode_name(mode_value: int) -> String:
	match mode_value:
		NetContext.Mode.ONLINE_CLIENT:
			return "ONLINE_CLIENT"
		NetContext.Mode.ONLINE_SERVER:
			return "ONLINE_SERVER"
		_:
			return "HOTSEAT"

func _safe_text(value: String) -> String:
	var s := str(value).strip_edges()
	if s.is_empty():
		return "-"
	return s

func _safe_room_code(room_state: Dictionary) -> String:
	var code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	if code.is_empty():
		return "-"
	return code
