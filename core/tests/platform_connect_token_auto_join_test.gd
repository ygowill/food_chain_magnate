# Platform：connect_token 验签 + ClientHello 自动建房/入房
class_name PlatformConnectTokenAutoJoinTest
extends RefCounted

const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rm = RoomManagerClass.new(rng)

	var mock_net := _MockNetClient.new(rm)
	var server = ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"

	var room_code := "Q1W2E3"

	# Host: create room with fixed code
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var host_payload := {
		"user_id": "u_host",
		"room_code": room_code,
		"role": "host",
		"display_name": "HostUser",
		"seat_index": 0,
		"config_json": JSON.stringify(cfg),
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var host_token_r: Result = ConnectTokenClass.create_token(host_payload, server.connect_token_secret_override)
	if not host_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(host) 失败: %s" % host_token_r.error)

	mock_net.multiplayer.remote_sender_id = 10
	server.handle_rpc_client_hello({
		"request_id": "r_host",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Host", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
	})

	if not rm.rooms.has(room_code):
		_reset_net_context()
		return Result.failure("平台建房失败：rooms 未包含 %s" % room_code)
	if str(rm.peer_to_room.get(10, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台建房失败：host peer_to_room 未绑定到 %s" % room_code)
	var room = rm.rooms.get(room_code, null)
	if room == null:
		_reset_net_context()
		return Result.failure("平台建房失败：room 为空")
	if int(room.host_peer_id) != 10:
		_reset_net_context()
		return Result.failure("平台建房失败：host_peer_id 错误: %d" % int(room.host_peer_id))

	# Player: auto join existing room
	var player_payload := {
		"user_id": "u_p2",
		"room_code": room_code,
		"role": "player",
		"display_name": "P2",
		"seat_index": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var player_token_r: Result = ConnectTokenClass.create_token(player_payload, server.connect_token_secret_override)
	if not player_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(player) 失败: %s" % player_token_r.error)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_client_hello({
		"request_id": "r_p2",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Local", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if str(rm.peer_to_room.get(11, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台入房失败：player peer_to_room 未绑定到 %s" % room_code)
	var peers: Array[int] = room.get_peer_ids()
	if peers.size() != 2 or not peers.has(10) or not peers.has(11):
		_reset_net_context()
		return Result.failure("平台入房失败：get_peer_ids=%s" % str(peers))

	_reset_net_context()
	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

class _MockMultiplayer:
	extends RefCounted
	var remote_sender_id: int = 0

	func get_remote_sender_id() -> int:
		return int(remote_sender_id)

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var sent: Array[Dictionary] = []

	func _init(room_manager) -> void:
		_room_manager = room_manager

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})

