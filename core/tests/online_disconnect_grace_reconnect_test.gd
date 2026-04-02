# 联机：掉线 grace period + token 重连（平台模式）
class_name OnlineDisconnectGraceReconnectTest
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

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		_reset_net_context()
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop

	var rm = RoomManagerClass.new()
	var mock_net := _MockNetClient.new(rm)

	var server = ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"
	server.disconnect_grace_period_sec_override = 0.05

	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	# Case A: 不重连 → grace 后 forfeit
	var room_code_a := "GRACE1"
	var setup_a: Result = await _platform_create_and_start_game(server, mock_net, rm, room_code_a, cfg, 10, 11)
	if not setup_a.ok:
		return _finish(setup_a, mock_net, server)
	var room_a = rm.rooms.get(room_code_a, null)
	if room_a == null:
		return _finish(Result.failure("room_a missing"), mock_net, server)

	server.on_peer_disconnected(11)
	var state_a0 = room_a.game_engine.get_state()
	if state_a0 != null and bool(state_a0.players[1].get("forfeited", false)):
		return _finish(Result.failure("掉线不应立刻 forfeit"), mock_net, server)

	await tree.create_timer(0.12).timeout
	var state_a1 = room_a.game_engine.get_state()
	if state_a1 == null or not bool(state_a1.players[1].get("forfeited", false)):
		return _finish(Result.failure("grace 后应 forfeit"), mock_net, server)

	# Case B: grace 内 token 重连 → 不 forfeit
	var room_code_b := "GRACE2"
	var setup_b: Result = await _platform_create_and_start_game(server, mock_net, rm, room_code_b, cfg, 20, 21)
	if not setup_b.ok:
		return _finish(setup_b, mock_net, server)
	var room_b = rm.rooms.get(room_code_b, null)
	if room_b == null:
		return _finish(Result.failure("room_b missing"), mock_net, server)

	server.on_peer_disconnected(21)
	await tree.process_frame

	var reconnect_token_r: Result = _issue_token({
		"user_id": "u_p2_%s" % room_code_b,
		"room_code": room_code_b,
		"role": "player",
		"display_name": "P2B",
		"seat_index": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not reconnect_token_r.ok:
		return _finish(Result.failure("create_token(reconnect) 失败: %s" % reconnect_token_r.error), mock_net, server)

	mock_net.multiplayer.remote_sender_id = 31
	server.handle_rpc_client_hello({
		"request_id": "r_reconnect",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2BLocal", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(reconnect_token_r.value),
	})

	if str(rm.peer_to_room.get(31, "")) != room_code_b:
		return _finish(Result.failure("重连失败：peer_to_room 未绑定到 %s" % room_code_b), mock_net, server)
	if int(room_b.player_id_by_peer_id.get(31, -1)) != 1:
		return _finish(Result.failure("重连失败：player_id_by_peer_id 未恢复到 seat=1"), mock_net, server)

	await tree.create_timer(0.12).timeout
	var state_b1 = room_b.game_engine.get_state()
	if state_b1 == null:
		return _finish(Result.failure("state_b1 missing"), mock_net, server)
	if bool(state_b1.players[1].get("forfeited", false)):
		return _finish(Result.failure("grace 内重连后不应 forfeit"), mock_net, server)

	# Case C: host reconnects on a new transport before the old one closes -> seat takeover should keep host authority.
	var room_code_c := "GRACE3"
	var setup_c: Result = await _platform_create_and_start_game(server, mock_net, rm, room_code_c, cfg, 40, 41)
	if not setup_c.ok:
		return _finish(setup_c, mock_net, server)
	var room_c = rm.rooms.get(room_code_c, null)
	if room_c == null:
		return _finish(Result.failure("room_c missing"), mock_net, server)

	var host_takeover_token_r: Result = _issue_token({
		"user_id": "u_host_%s" % room_code_c,
		"room_code": room_code_c,
		"role": "host",
		"display_name": "HostC",
		"seat_index": 0,
		"config_json": JSON.stringify(cfg),
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not host_takeover_token_r.ok:
		return _finish(Result.failure("create_token(host_takeover) 失败: %s" % host_takeover_token_r.error), mock_net, server)

	mock_net.multiplayer.remote_sender_id = 42
	server.handle_rpc_client_hello({
		"request_id": "r_host_takeover",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "HostCTakeover", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_takeover_token_r.value),
	})

	if str(rm.peer_to_room.get(42, "")) != room_code_c:
		return _finish(Result.failure("host 接管失败：new peer_to_room 未绑定到 %s" % room_code_c), mock_net, server)
	if rm.peer_to_room.has(40):
		return _finish(Result.failure("host 接管失败：old peer_to_room 未清理"), mock_net, server)
	if int(room_c.host_peer_id) != 42:
		return _finish(Result.failure("host 接管失败：host_peer_id=%d" % int(room_c.host_peer_id)), mock_net, server)
	if int(room_c.player_id_by_peer_id.get(42, -1)) != 0:
		return _finish(Result.failure("host 接管失败：player_id_by_peer_id 未恢复到 seat=0"), mock_net, server)
	if room_c.player_id_by_peer_id.has(40):
		return _finish(Result.failure("host 接管失败：old player_id_by_peer_id 未清理"), mock_net, server)
	var peers_c: Array[int] = room_c.get_peer_ids()
	if peers_c.size() != 2 or not peers_c.has(41) or not peers_c.has(42) or peers_c.has(40):
		return _finish(Result.failure("host 接管失败：get_peer_ids=%s" % str(peers_c)), mock_net, server)
	if not _has_empty_room_state_push(mock_net.sent, 40):
		return _finish(Result.failure("host 接管失败：old peer 未收到 empty room_state"), mock_net, server)

	return _finish(Result.success(), mock_net, server)

static func _platform_create_and_start_game(
	server,
	mock_net,
	rm,
	room_code: String,
	cfg: Dictionary,
	host_peer_id: int,
	player_peer_id: int
) -> Result:
	var host_token_r: Result = _issue_token({
		"user_id": "u_host_%s" % room_code,
		"room_code": room_code,
		"role": "host",
		"display_name": "Host",
		"seat_index": 0,
		"config_json": JSON.stringify(cfg),
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not host_token_r.ok:
		return Result.failure("create_token(host) 失败: %s" % host_token_r.error)

	mock_net.multiplayer.remote_sender_id = host_peer_id
	server.handle_rpc_client_hello({
		"request_id": "r_host_%s" % room_code,
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "HostLocal", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
	})

	var player_token_r: Result = _issue_token({
		"user_id": "u_p2_%s" % room_code,
		"room_code": room_code,
		"role": "player",
		"display_name": "P2",
		"seat_index": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not player_token_r.ok:
		return Result.failure("create_token(player) 失败: %s" % player_token_r.error)

	mock_net.multiplayer.remote_sender_id = player_peer_id
	server.handle_rpc_client_hello({
		"request_id": "r_p2_%s" % room_code,
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2Local", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("room missing after platform join: %s" % room_code)
	var sr: Result = room.start_game()
	if not sr.ok:
		return Result.failure("StartGame 失败: %s" % sr.error)
	return Result.success()

static func _issue_token(payload: Dictionary, secret: String) -> Result:
	return ConnectTokenClass.create_token(payload, str(secret))

static func _finish(result: Result, mock_net, server) -> Result:
	if server != null and is_instance_valid(server) and server is RefCounted:
		# no-op
		pass
	_reset_net_context()
	return result

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

	func get_tree():
		var loop = Engine.get_main_loop()
		if loop is SceneTree:
			return loop
		return null

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
