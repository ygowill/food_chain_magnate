# 联机 InGame：最后一个在线 peer 断开后，房间仍应保留以支持重连恢复
class_name OnlineInGameLastPeerDisconnectRecoveryTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 246810

	var rm = RoomManagerClass.new(rng)
	var room_code := "INGRSM"
	var config := {
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
		"user_id": "u_host_ingame_recover",
	}
	var create_r: Result = rm.create_room_with_code(10, host_profile, room_code, config)
	if not create_r.ok:
		return Result.failure("create_room_with_code 失败: %s" % create_r.error)

	var player_profile := {
		"name": "Player2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_ingame_recover",
	}
	var join_r: Result = rm.join_room_with_seat(11, player_profile, room_code, 1)
	if not join_r.ok:
		return Result.failure("join_room_with_seat 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("room missing after create/join")

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("StartGame 失败: %s" % start_r.error)
	if str(room.status) != "InGame":
		return Result.failure("StartGame 后状态错误: %s" % str(room.status))

	var disconnect_host_r: Result = rm.disconnect_peer(10)
	if not disconnect_host_r.ok:
		return Result.failure("disconnect_peer(host) 失败: %s" % disconnect_host_r.error)
	var disconnect_player_r: Result = rm.disconnect_peer(11)
	if not disconnect_player_r.ok:
		return Result.failure("disconnect_peer(player) 失败: %s" % disconnect_player_r.error)
	if bool(Dictionary(disconnect_player_r.value).get("removed", false)):
		return Result.failure("最后一个在线 peer 断开后不应立即删除 InGame 房间")

	var preserved_room = rm.rooms.get(room_code, null)
	if preserved_room == null:
		return Result.failure("InGame 所有人掉线后房间仍应保留")
	if preserved_room != room:
		return Result.failure("保留后的 room 实例发生替换")
	if int(room.get_connected_player_count()) != 0:
		return Result.failure("所有人掉线后 connected_player_count 应为 0: %d" % int(room.get_connected_player_count()))

	var room_state: Dictionary = room.to_room_state_dict()
	if not _has_disconnected_seat(room_state, 0) or not _has_disconnected_seat(room_state, 1):
		return Result.failure("所有玩家掉线后应保留 connected=false 的座位占位")

	var reconnect_host_r: Result = rm.reconnect_player(20, host_profile, room_code, 0, "u_host_ingame_recover", "host")
	if not reconnect_host_r.ok:
		return Result.failure("reconnect_player(host) 失败: %s" % reconnect_host_r.error)
	var reconnect_player_r: Result = rm.reconnect_player(21, player_profile, room_code, 1, "u_p2_ingame_recover")
	if not reconnect_player_r.ok:
		return Result.failure("reconnect_player(player) 失败: %s" % reconnect_player_r.error)

	if int(room.host_peer_id) != 20:
		return Result.failure("host 重连后 host_peer_id 错误: %d" % int(room.host_peer_id))
	if int(room.player_id_by_peer_id.get(20, -1)) != 0:
		return Result.failure("host 重连后 actor 映射错误: %s" % str(room.player_id_by_peer_id))
	if int(room.player_id_by_peer_id.get(21, -1)) != 1:
		return Result.failure("player 重连后 actor 映射错误: %s" % str(room.player_id_by_peer_id))
	if int(room.get_connected_player_count()) != 2:
		return Result.failure("双方重连后 connected_player_count 应恢复为 2: %d" % int(room.get_connected_player_count()))

	var peer_ids: Array[int] = room.get_peer_ids()
	if peer_ids.size() != 2 or not peer_ids.has(20) or not peer_ids.has(21):
		return Result.failure("重连后 get_peer_ids 错误: %s" % str(peer_ids))

	return Result.success()

static func _has_disconnected_seat(room_state: Dictionary, seat_index: int) -> bool:
	var players_val = room_state.get("players", null)
	if not (players_val is Array):
		return false
	for player_val in Array(players_val):
		if not (player_val is Dictionary):
			continue
		var player: Dictionary = Dictionary(player_val)
		if int(player.get("seat_index", -1)) != int(seat_index):
			continue
		return int(player.get("peer_id", 0)) == 0 and not bool(player.get("connected", true))
	return false
