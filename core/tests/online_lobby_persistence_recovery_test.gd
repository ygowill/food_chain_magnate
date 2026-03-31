# 联机房间：Lobby 快照恢复后按 seat/user_id reclaim
class_name OnlineLobbyPersistenceRecoveryTest
extends RefCounted

const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const RoomPersistenceStoreClass = preload("res://server/room_persistence_store.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var room_code := "LOBBY1"
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var rm := RoomManagerClass.new()
	var create_r: Result = rm.create_room_with_code(10, {
		"name": "Host",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_host_lobby_restore",
	}, room_code, cfg)
	if not create_r.ok:
		return Result.failure("create_room_with_code 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room_with_seat(11, {
		"name": "Player2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_lobby_restore",
	}, room_code, 1)
	if not join_r.ok:
		return Result.failure("join_room_with_seat 失败: %s" % join_r.error)

	var store := RoomPersistenceStoreClass.new("user://online_lobby_persistence_recovery_test.json")
	var save_r: Result = store.save_room_manager(rm)
	if not save_r.ok:
		return Result.failure("save_room_manager 失败: %s" % save_r.error)

	var load_r: Result = store.load_snapshot()
	if not load_r.ok:
		return Result.failure("load_snapshot 失败: %s" % load_r.error)

	var rm2 := RoomManagerClass.new()
	var restore_r: Result = rm2.restore_from_persistence(Dictionary(load_r.value))
	if not restore_r.ok:
		return Result.failure("restore_from_persistence 失败: %s" % restore_r.error)

	var restored_room = rm2.rooms.get(room_code, null)
	if restored_room == null:
		return Result.failure("restored room missing")
	if str(restored_room.status) != "Lobby":
		return Result.failure("restored room status 错误: %s" % str(restored_room.status))
	if restored_room.get_connected_player_count() != 0:
		return Result.failure("Lobby 恢复后 connected_player_count 应为 0，实际: %d" % restored_room.get_connected_player_count())
	if str(restored_room.owner_user_id) != "u_host_lobby_restore":
		return Result.failure("Lobby 恢复后 owner_user_id 错误: %s" % str(restored_room.owner_user_id))

	var mock_net := _MockNetClient.new(rm2)
	var server := ServerLogicClass.new()
	server.setup(mock_net)
	server.connect_token_secret_override = "test-secret"

	var host_token_r: Result = ConnectTokenClass.create_token({
		"user_id": "u_host_lobby_restore",
		"room_code": room_code,
		"role": "host",
		"display_name": "Host",
		"seat_index": 0,
		"config_json": JSON.stringify(cfg),
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not host_token_r.ok:
		return Result.failure("create_token(host) 失败: %s" % host_token_r.error)
	mock_net.multiplayer.remote_sender_id = 20
	server.handle_rpc_client_hello({
		"request_id": "r_host_resume",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Host", "color_index": 0, "restaurant_logo_id": -1},
		"connect_token": str(host_token_r.value),
	})

	var player_token_r: Result = ConnectTokenClass.create_token({
		"user_id": "u_p2_lobby_restore",
		"room_code": room_code,
		"role": "player",
		"display_name": "Player2",
		"seat_index": 1,
		"exp": int(Time.get_unix_time_from_system()) + 3600,
	}, server.connect_token_secret_override)
	if not player_token_r.ok:
		return Result.failure("create_token(player) 失败: %s" % player_token_r.error)
	mock_net.multiplayer.remote_sender_id = 21
	server.handle_rpc_client_hello({
		"request_id": "r_p2_resume",
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": "0.0.0",
		"schema_version": 0,
		"player_profile": {"name": "Player2", "color_index": 1, "restaurant_logo_id": -1},
		"connect_token": str(player_token_r.value),
	})

	if str(rm2.peer_to_room.get(20, "")) != room_code:
		return Result.failure("host reclaim 后 peer_to_room 未恢复")
	if str(rm2.peer_to_room.get(21, "")) != room_code:
		return Result.failure("player reclaim 后 peer_to_room 未恢复")
	if int(restored_room.host_peer_id) != 20:
		return Result.failure("host reclaim 后 host_peer_id 错误: %d" % int(restored_room.host_peer_id))
	var peers: Array[int] = restored_room.get_peer_ids()
	if peers.size() != 2 or not peers.has(20) or not peers.has(21):
		return Result.failure("Lobby reclaim 后 get_peer_ids 错误: %s" % str(peers))

	return Result.success()

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
