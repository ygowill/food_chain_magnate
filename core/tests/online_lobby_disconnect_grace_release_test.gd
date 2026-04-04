class_name OnlineLobbyDisconnectGraceReleaseTest
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

	var room_code_a := "LGRACE1"
	var setup_a: Result = await _platform_create_lobby(server, mock_net, rm, room_code_a, cfg, 10, 11)
	if not setup_a.ok:
		return _finish(setup_a)
	var room_a = rm.rooms.get(room_code_a, null)
	if room_a == null:
		return _finish(Result.failure("room_a missing"))

	server.on_peer_disconnected(11)
	if room_a.get_player_count() != 2 or room_a.get_connected_player_count() != 1:
		return _finish(Result.failure("Lobby 掉线后应先保留断线 seat"))

	await tree.create_timer(0.12).timeout
	var room_a_after = rm.rooms.get(room_code_a, null)
	if room_a_after == null:
		return _finish(Result.failure("host 仍在线时，Lobby grace 后不应直接删房"))
	if room_a_after.get_player_count() != 1:
		return _finish(Result.failure("Lobby grace 后应释放断线 seat: %d" % room_a_after.get_player_count()))
	if room_a_after.get_connected_player_count() != 1:
		return _finish(Result.failure("Lobby grace 后 connected_player_count 错误: %d" % room_a_after.get_connected_player_count()))
	if room_a_after.is_full():
		return _finish(Result.failure("Lobby grace 后应允许新玩家加入，不应仍视为满员"))
	var summary_a := _find_summary(rm.list_room_summaries(), room_code_a)
	if summary_a.is_empty():
		return _finish(Result.failure("Lobby grace 后房间摘要丢失"))
	if int(summary_a.get("player_count", -1)) != 1 or int(summary_a.get("connected_player_count", -1)) != 1:
		return _finish(Result.failure("Lobby grace 后房间摘要人数错误: %s" % str(summary_a)))

	var room_code_b := "LGRACE2"
	var setup_b: Result = await _platform_create_lobby(server, mock_net, rm, room_code_b, cfg, 20, 21)
	if not setup_b.ok:
		return _finish(setup_b)
	var room_b = rm.rooms.get(room_code_b, null)
	if room_b == null:
		return _finish(Result.failure("room_b missing"))

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
		return _finish(Result.failure("create_token(reconnect) 失败: %s" % reconnect_token_r.error))

	mock_net.multiplayer.remote_sender_id = 22
	server.handle_rpc_client_hello({
		"request_id": "r_lobby_reconnect",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "P2BLocal", "color_index": 2, "restaurant_logo_id": -1},
		"connect_token": str(reconnect_token_r.value),
	})

	if str(rm.peer_to_room.get(22, "")) != room_code_b:
		return _finish(Result.failure("Lobby grace 内 reclaim 失败：peer_to_room 未恢复"))
	await tree.create_timer(0.12).timeout
	var room_b_after = rm.rooms.get(room_code_b, null)
	if room_b_after == null:
		return _finish(Result.failure("Lobby grace 内 reclaim 后房间不应消失"))
	if room_b_after.get_player_count() != 2 or room_b_after.get_connected_player_count() != 2:
		return _finish(Result.failure("Lobby grace 内 reclaim 后人数状态错误"))
	if not room_b_after.is_full():
		return _finish(Result.failure("Lobby grace 内 reclaim 后房间应恢复为满员"))

	server.on_peer_disconnected(10)
	await tree.create_timer(0.12).timeout
	if rm.rooms.has(room_code_a):
		return _finish(Result.failure("Lobby 最后一名玩家 grace 超时后应清理空房"))

	return _finish(Result.success())

static func _platform_create_lobby(
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
		return Result.failure("room missing after lobby setup: %s" % room_code)
	if room.get_player_count() != 2 or room.get_connected_player_count() != 2:
		return Result.failure("lobby setup 人数错误")
	return Result.success()

static func _issue_token(payload: Dictionary, secret: String) -> Result:
	return ConnectTokenClass.create_token(payload, str(secret))

static func _find_summary(list: Array, room_code: String) -> Dictionary:
	var target := str(room_code).strip_edges().to_upper()
	for item in list:
		if not (item is Dictionary):
			continue
		var summary: Dictionary = Dictionary(item)
		if str(summary.get("room_code", "")).strip_edges().to_upper() == target:
			return summary
	return {}

static func _finish(result: Result) -> Result:
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
