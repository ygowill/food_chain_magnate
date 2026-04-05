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
		"join_policy": "password",
		"password_hash": "platform-password-hash",
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
	if str(room.join_policy) != "password":
		_reset_net_context()
		return Result.failure("平台建房失败：join_policy 错误: %s" % str(room.join_policy))
	if str(room.password_hash) != "platform-password-hash":
		_reset_net_context()
		return Result.failure("平台建房失败：password_hash 未透传")
	if not room.is_password_required():
		_reset_net_context()
		return Result.failure("平台建房失败：密码房间应标记为需要密码")

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

	# Same user reopens the lobby before old transport closes: new peer should take over the seat.
	mock_net.multiplayer.remote_sender_id = 12
	server.handle_rpc_client_hello({
		"request_id": "r_p2_takeover",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Takeover", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if str(rm.peer_to_room.get(12, "")) != room_code:
		_reset_net_context()
		return Result.failure("平台接管失败：new peer_to_room 未绑定到 %s" % room_code)
	if rm.peer_to_room.has(11):
		_reset_net_context()
		return Result.failure("平台接管失败：old peer_to_room 未清理")
	var peers_after: Array[int] = room.get_peer_ids()
	if peers_after.size() != 2 or not peers_after.has(10) or not peers_after.has(12) or peers_after.has(11):
		_reset_net_context()
		return Result.failure("平台接管失败：get_peer_ids=%s" % str(peers_after))
	if not _has_empty_room_state_push(mock_net.sent, 11):
		_reset_net_context()
		return Result.failure("平台接管失败：old peer 未收到 empty room_state")

	var start_r: Result = room.start_game()
	if not start_r.ok:
		_reset_net_context()
		return Result.failure("平台自动入房测试开局失败: %s" % start_r.error)

	var spectator_payload := {
		"user_id": "u_spec_1",
		"room_code": room_code,
		"role": "spectator",
		"display_name": "Spec1",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var spectator_token_r: Result = ConnectTokenClass.create_token(spectator_payload, server.connect_token_secret_override)
	if not spectator_token_r.ok:
		_reset_net_context()
		return Result.failure("create_token(spectator1) 失败: %s" % spectator_token_r.error)

	mock_net.multiplayer.remote_sender_id = 20
	server.handle_rpc_client_hello({
		"request_id": "r_spec_1",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec1Local", "color_index": 3, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r.value),
	})

	if str(rm.peer_to_room.get(20, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战自动入房失败：spectator1 peer_to_room 未绑定到 %s" % room_code)

	var spectator_payload2 := {
		"user_id": "u_spec_2",
		"room_code": room_code,
		"role": "spectator",
		"display_name": "Spec2",
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}
	var spectator_token_r2: Result = ConnectTokenClass.create_token(spectator_payload2, server.connect_token_secret_override)
	if not spectator_token_r2.ok:
		_reset_net_context()
		return Result.failure("create_token(spectator2) 失败: %s" % spectator_token_r2.error)

	mock_net.multiplayer.remote_sender_id = 21
	server.handle_rpc_client_hello({
		"request_id": "r_spec_2",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec2Local", "color_index": 4, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r2.value),
	})

	if str(rm.peer_to_room.get(21, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战自动入房失败：spectator2 peer_to_room 未绑定到 %s" % room_code)
	var in_game_peers: Array[int] = room.get_peer_ids()
	if in_game_peers.size() != 4 or not in_game_peers.has(10) or not in_game_peers.has(12) or not in_game_peers.has(20) or not in_game_peers.has(21):
		_reset_net_context()
		return Result.failure("多观战者未同时存在：get_peer_ids=%s" % str(in_game_peers))

	mock_net.multiplayer.remote_sender_id = 22
	server.handle_rpc_client_hello({
		"request_id": "r_spec_1_takeover",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Spec1Takeover", "color_index": 3, "restaurant_logo_id": -1},
		"connect_token": str(spectator_token_r.value),
	})

	if str(rm.peer_to_room.get(22, "")) != room_code:
		_reset_net_context()
		return Result.failure("观战接管失败：new spectator peer_to_room 未绑定到 %s" % room_code)
	if rm.peer_to_room.has(20):
		_reset_net_context()
		return Result.failure("观战接管失败：old spectator peer_to_room 未清理")
	var peers_after_spectator_takeover: Array[int] = room.get_peer_ids()
	if peers_after_spectator_takeover.size() != 4 \
		or not peers_after_spectator_takeover.has(10) \
		or not peers_after_spectator_takeover.has(12) \
		or not peers_after_spectator_takeover.has(21) \
		or not peers_after_spectator_takeover.has(22) \
		or peers_after_spectator_takeover.has(20):
		_reset_net_context()
		return Result.failure("观战接管失败：get_peer_ids=%s" % str(peers_after_spectator_takeover))
	if not _has_empty_room_state_push(mock_net.sent, 20):
		_reset_net_context()
		return Result.failure("观战接管失败：old spectator 未收到 empty room_state")

	mock_net._peer = _MockPeer.new(128)
	mock_net.multiplayer.remote_sender_id = 13
	server.handle_rpc_client_hello({
		"request_id": "r_p2_ingame_fail",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2ReconnectFail", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if rm.peer_to_room.has(13):
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应绑定新 peer")
	if str(rm.peer_to_room.get(12, "")) != room_code:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应破坏旧 peer 绑定")
	if int(room.player_id_by_peer_id.get(12, -1)) != 1:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时旧 seat 控制权丢失")
	if room.player_id_by_peer_id.has(13):
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应留下新 peer 的 player_id 映射")
	if _find_request_rejected(mock_net.sent, 13, "r_p2_ingame_fail", "platform_join_failed") < 0:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时应返回 platform_join_failed")
	if _find_sent_method(mock_net.sent, 13, "rpc_game_started") >= 0:
		_reset_net_context()
		return Result.failure("InGame 自动恢复快照构建失败时不应提前发送 GameStarted")

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

class _MockPeer:
	extends RefCounted

	var outbound_buffer_size: int = 0

	func _init(buffer_size: int) -> void:
		outbound_buffer_size = int(buffer_size)

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var sent: Array[Dictionary] = []
	var _peer = _MockPeer.new(16 * 1024 * 1024)

	func _init(room_manager) -> void:
		_room_manager = room_manager

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})

static func _has_empty_room_state_push(sent: Array[Dictionary], peer_id: int) -> bool:
	for item in sent:
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_room_state":
			continue
		var payload = item.get("payload", null)
		if not (payload is Dictionary):
			continue
		var room_state: Dictionary = Dictionary(payload)
		if str(room_state.get("room_code", "")).strip_edges().is_empty():
			return true
	return false

static func _find_sent_method(sent: Array[Dictionary], peer_id: int, method: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		return i
	return -1

static func _find_request_rejected(sent: Array[Dictionary], peer_id: int, request_id: String, code: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_request_rejected":
			continue
		var payload_val = item.get("payload", null)
		if not (payload_val is Dictionary):
			continue
		var payload: Dictionary = Dictionary(payload_val)
		if str(payload.get("request_id", "")) != str(request_id):
			continue
		if str(payload.get("code", "")) != str(code):
			continue
		return i
	return -1
