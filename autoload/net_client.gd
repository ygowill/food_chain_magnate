# 联机会话层（Client/Server 共用 RPC 节点）
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const CommandClass = preload("res://core/types/command.gd")
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
