# 联机房间：InGame 权威快照落盘/恢复
class_name OnlineRoomPersistenceRecoveryTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const RoomPersistenceStoreClass = preload("res://server/room_persistence_store.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	var room_code := "PERS01"
	var store := RoomPersistenceStoreClass.new("user://online_room_persistence_recovery_test.json")
	var rm := RoomManagerClass.new()

	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var host_profile := {
		"name": "Host",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_host_persist",
	}
	var player_profile := {
		"name": "Player2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_persist",
	}

	var create_r: Result = rm.create_room_with_code(10, host_profile, room_code, cfg)
	if not create_r.ok:
		return Result.failure("create_room_with_code 失败: %s" % create_r.error)
	var join_r: Result = rm.join_room(11, player_profile, room_code, "")
	if not join_r.ok:
		return Result.failure("join_room 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("room missing after setup")
	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("start_game 失败: %s" % start_r.error)

	var original_hash := ""
	if room.game_engine != null and room.game_engine.get_state() != null:
		original_hash = str(room.game_engine.get_state().compute_hash())
	if original_hash.is_empty():
		return Result.failure("original_hash missing")

	var save_r: Result = store.save_room_manager(rm)
	if not save_r.ok:
		return Result.failure("save_room_manager 失败: %s" % save_r.error)

	var load_r: Result = store.load_snapshot()
	if not load_r.ok:
		return Result.failure("load_snapshot 失败: %s" % load_r.error)
	var snapshot: Dictionary = Dictionary(load_r.value)
	var rooms_val = snapshot.get("rooms", null)
	if not (rooms_val is Array):
		return Result.failure("snapshot.rooms 类型错误")
	if Array(rooms_val).size() != 1:
		return Result.failure("snapshot.rooms 数量错误: %d" % Array(rooms_val).size())

	var rm2 := RoomManagerClass.new()
	var restore_r: Result = rm2.restore_from_persistence(snapshot)
	if not restore_r.ok:
		return Result.failure("restore_from_persistence 失败: %s" % restore_r.error)

	var restored_room = rm2.rooms.get(room_code, null)
	if restored_room == null:
		return Result.failure("restored room missing")
	if str(restored_room.status) != "InGame":
		return Result.failure("restored status 错误: %s" % str(restored_room.status))
	if restored_room.get_player_count() != 2:
		return Result.failure("restored player_count 错误: %d" % restored_room.get_player_count())
	if restored_room.get_connected_player_count() != 0:
		return Result.failure("恢复后 connected_player_count 应为 0，实际: %d" % restored_room.get_connected_player_count())

	var restored_hash := ""
	if restored_room.game_engine != null and restored_room.game_engine.get_state() != null:
		restored_hash = str(restored_room.game_engine.get_state().compute_hash())
	if restored_hash != original_hash:
		return Result.failure("恢复后 hash 不一致: %s vs %s" % [original_hash, restored_hash])

	var bad_reconnect: Result = rm2.reconnect_player(31, {
		"name": "Player2Wrong",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "wrong_user",
	}, room_code, 1, "wrong_user")
	if bad_reconnect.ok:
		return Result.failure("错误 user_id 不应重连成功")

	var reconnect_r: Result = rm2.reconnect_player(31, {
		"name": "Player2Reconnect",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_persist",
	}, room_code, 1, "u_p2_persist")
	if not reconnect_r.ok:
		return Result.failure("reconnect_player 失败: %s" % reconnect_r.error)
	if str(rm2.peer_to_room.get(31, "")) != room_code:
		return Result.failure("重连后 peer_to_room 未恢复")
	if int(restored_room.player_id_by_peer_id.get(31, -1)) != 1:
		return Result.failure("重连后 player_id_by_peer_id 未恢复到 seat=1")

	return Result.success({
		"room_code": room_code,
		"hash": restored_hash.substr(0, 8),
	})
