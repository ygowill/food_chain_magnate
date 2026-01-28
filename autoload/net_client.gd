# 联机会话层（Client/Server 共用 RPC 节点）
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")

signal connected()
signal disconnected(reason: String)
signal room_state_updated(room_state: Dictionary)
signal request_rejected(request_id: String, code: String, message: String)

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

func request_create_room(desired_player_count: int, room_password: String) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"desired_player_count": desired_player_count,
		"join_policy": "password",
		"room_password": room_password,
	}
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
	var config := {"desired_player_count": desired_player_count}

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

@rpc("authority", "reliable")
func rpc_room_state(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	NetContext.room_state = payload.duplicate(true)
	room_state_updated.emit(NetContext.room_state)

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
