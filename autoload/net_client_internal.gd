# NetClient：内部实现（信号连接 + server/client 模块编排）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
extends RefCounted

const NetClientServerClass = preload("res://autoload/net_client/server.gd")
const NetClientClientClass = preload("res://autoload/net_client/client.gd")

var _net = null
var _server = null
var _client = null

func setup(net_client) -> void:
	_net = net_client
	_ensure_modules()

func _ensure_modules() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if _server == null or not is_instance_valid(_server):
		_server = NetClientServerClass.new()
		_server.setup(_net)
	if _client == null or not is_instance_valid(_client):
		_client = NetClientClientClass.new()
		_client.setup(_net)

func ensure_signal_connections() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if not _net.multiplayer.peer_connected.is_connected(_net._on_peer_connected):
		_net.multiplayer.peer_connected.connect(_net._on_peer_connected)
	if not _net.multiplayer.peer_disconnected.is_connected(_net._on_peer_disconnected):
		_net.multiplayer.peer_disconnected.connect(_net._on_peer_disconnected)
	if not _net.multiplayer.connected_to_server.is_connected(_net._on_connected_to_server):
		_net.multiplayer.connected_to_server.connect(_net._on_connected_to_server)
	if not _net.multiplayer.connection_failed.is_connected(_net._on_connection_failed):
		_net.multiplayer.connection_failed.connect(_net._on_connection_failed)
	if not _net.multiplayer.server_disconnected.is_connected(_net._on_server_disconnected):
		_net.multiplayer.server_disconnected.connect(_net._on_server_disconnected)

func on_peer_connected(peer_id: int) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.on_peer_connected(peer_id)

func on_peer_disconnected(peer_id: int) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.on_peer_disconnected(peer_id)

func on_connected_to_server() -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.on_connected_to_server()

func on_connection_failed() -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.on_connection_failed()

func on_server_disconnected() -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.on_server_disconnected()

func send_client_hello() -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.send_client_hello()

func handle_rpc_room_state(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_room_state(payload)

func handle_rpc_room_list(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_room_list(payload)

func handle_rpc_game_started(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_game_started(payload)

func handle_rpc_command_applied(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_command_applied(payload)

func handle_rpc_resync_archive(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_resync_archive(payload)

func handle_rpc_rewind_to_turn_start_meta(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_rewind_to_turn_start_meta(payload)

func handle_rpc_resync_snapshot_manifest(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_resync_snapshot_manifest(payload)

func handle_rpc_resync_snapshot_chunk(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_resync_snapshot_chunk(payload)

func handle_rpc_resync_delta(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_resync_delta(payload)

func handle_rpc_request_rejected(payload: Dictionary) -> void:
	_ensure_modules()
	if _client != null and is_instance_valid(_client):
		_client.handle_rpc_request_rejected(payload)

func send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.send_request_rejected(peer_id, request_id, code, message)

func broadcast_room_state(room) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.broadcast_room_state(room)

func empty_room_state() -> Dictionary:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		return _server.empty_room_state()
	return {}

func send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.send_room_list_to_peer(peer_id, request_id)

func broadcast_room_list(request_id: String) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.broadcast_room_list(request_id)

func handle_rpc_client_hello(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_client_hello(request)

func handle_rpc_list_rooms(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_list_rooms(request)

func handle_rpc_create_room(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_create_room(request)

func handle_rpc_join_room(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_join_room(request)

func handle_rpc_update_room_config(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_update_room_config(request)

func handle_rpc_assign_room_seat(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_assign_room_seat(request)

func handle_rpc_leave_room(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_leave_room(request)

func handle_rpc_forfeit_and_leave_room(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_forfeit_and_leave_room(request)

func handle_rpc_start_game(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_start_game(request)

func handle_rpc_action_request(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_action_request(request)

func handle_rpc_resync_request(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_resync_request(request)

func handle_rpc_rewind_to_turn_start(request: Dictionary) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.handle_rpc_rewind_to_turn_start(request)

func broadcast_command_applied(room, cmd) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.broadcast_command_applied(room, cmd)

func server_is_player_forfeited(state, player_id: int) -> bool:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		return _server.server_is_player_forfeited(state, player_id)
	return false

func server_pick_order_of_business_position(state) -> int:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		return _server.server_pick_order_of_business_position(state)
	return -1

func server_try_auto_submit_forfeited_restructuring(room) -> bool:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		return _server.server_try_auto_submit_forfeited_restructuring(room)
	return false

func server_drain_forfeited_auto_steps(room) -> void:
	_ensure_modules()
	if _server != null and is_instance_valid(_server):
		_server.server_drain_forfeited_auto_steps(room)
