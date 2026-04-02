# 联机 Lobby：断线保留座位，可 reclaim 恢复，且断线期间不能开局
class_name OnlineLobbyDisconnectReclaimTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const LobbyViewModelClass = preload("res://ui/scenes/online/online_lobby_view_model.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 789012

	var rm = RoomManagerClass.new(rng)
	var room_code := "LBRECL"
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
		"user_id": "u_host_lobby_disconnect",
	}
	var create_r: Result = rm.create_room_with_code(10, host_profile, room_code, config)
	if not create_r.ok:
		return Result.failure("create_room_with_code 失败: %s" % create_r.error)

	var player_profile := {
		"name": "Player2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_lobby_disconnect",
	}
	var join_r: Result = rm.join_room_with_seat(11, player_profile, room_code, 1)
	if not join_r.ok:
		return Result.failure("join_room_with_seat 失败: %s" % join_r.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("room missing after create/join")

	var room_state_ready: Dictionary = room.to_room_state_dict()
	if not LobbyViewModelClass.can_start_game(room_state_ready, 10):
		return Result.failure("两名玩家都在线时应可开始游戏")

	var disconnect_player_r: Result = rm.disconnect_peer(11)
	if not disconnect_player_r.ok:
		return Result.failure("disconnect_peer(player) 失败: %s" % disconnect_player_r.error)
	if room.get_player_count() != 2:
		return Result.failure("Lobby 断线后应保留玩家座位: %d" % room.get_player_count())
	if room.get_connected_player_count() != 1:
		return Result.failure("Lobby 断线后 connected_player_count 错误: %d" % room.get_connected_player_count())
	if not room.is_full():
		return Result.failure("Lobby 断线保留座位后房间应视为满员，避免被他人顶替")
	var disconnected_state: Dictionary = room.to_room_state_dict()
	if LobbyViewModelClass.can_start_game(disconnected_state, 10):
		return Result.failure("存在掉线座位时不应允许开始游戏")
	if not _has_disconnected_seat(disconnected_state, 1):
		return Result.failure("掉线玩家座位未保留为 connected=false")

	var disconnect_host_r: Result = rm.disconnect_peer(10)
	if not disconnect_host_r.ok:
		return Result.failure("disconnect_peer(host) 失败: %s" % disconnect_host_r.error)
	if rm.rooms.get(room_code, null) == null:
		return Result.failure("Lobby 所有人暂时掉线时不应立即删除房间")
	if room.get_connected_player_count() != 0:
		return Result.failure("host 掉线后 connected_player_count 应为 0: %d" % room.get_connected_player_count())
	var host_disconnected_state: Dictionary = room.to_room_state_dict()
	if int(host_disconnected_state.get("host_peer_id", -1)) != 0:
		return Result.failure("host 掉线后 host_peer_id 应清空: %s" % str(host_disconnected_state.get("host_peer_id", null)))
	if int(host_disconnected_state.get("host_seat_index", -1)) != 0:
		return Result.failure("host 掉线后 host_seat_index 应保留为 0: %s" % str(host_disconnected_state.get("host_seat_index", null)))

	var reclaim_host_r: Result = rm.reclaim_room_seat(20, host_profile, room_code, 0, "u_host_lobby_disconnect", "host")
	if not reclaim_host_r.ok:
		return Result.failure("reclaim_room_seat(host) 失败: %s" % reclaim_host_r.error)
	if int(room.host_peer_id) != 20:
		return Result.failure("host reclaim 后 host_peer_id 错误: %d" % int(room.host_peer_id))

	var reclaim_player_r: Result = rm.reclaim_room_seat(21, player_profile, room_code, 1, "u_p2_lobby_disconnect")
	if not reclaim_player_r.ok:
		return Result.failure("reclaim_room_seat(player) 失败: %s" % reclaim_player_r.error)
	if room.get_connected_player_count() != 2:
		return Result.failure("双方 reclaim 后 connected_player_count 应恢复为 2: %d" % room.get_connected_player_count())

	var resumed_state: Dictionary = room.to_room_state_dict()
	if not LobbyViewModelClass.can_start_game(resumed_state, 20):
		return Result.failure("双方 reclaim 后房主应可再次开始游戏")

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("reclaim 后 StartGame 失败: %s" % start_r.error)

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
