# 联机房间：旁观者（spectator）与断线保留座位（M4）
# - InGame 断线：保留玩家座位占位（connected=false, peer_id=0）
# - InGame JoinRoom：允许以 spectator 加入（不占用玩家席位）
class_name OnlineRoomSpectatorTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456

	var rm = RoomManagerClass.new(rng)

	var host_peer_id := 10
	var host_profile := {"name": "Host", "color_index": 1}
	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var cr: Result = rm.create_room(host_peer_id, host_profile, "pw", config)
	if not cr.ok:
		return Result.failure("CreateRoom 失败: %s" % cr.error)
	var room_code := str(Dictionary(cr.value).get("room_code", ""))
	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		return Result.failure("CreateRoom 未返回 room")

	var jr: Result = rm.join_room(11, {"name": "P2", "color_index": 2}, room_code, "pw")
	if not jr.ok:
		return Result.failure("JoinRoom 失败: %s" % jr.error)

	var sr: Result = room.start_game()
	if not sr.ok:
		return Result.failure("StartGame 失败: %s" % sr.error)
	if str(room.status) != "InGame":
		return Result.failure("StartGame 后状态错误: %s" % str(room.status))

	# 断线：保留 seat（并迁移 host）
	var dr: Result = rm.disconnect_peer(host_peer_id)
	if not dr.ok:
		return Result.failure("disconnect_peer(host) 失败: %s" % dr.error)
	if int(room.host_peer_id) != 11:
		return Result.failure("host 未迁移: %d" % int(room.host_peer_id))

	if int(room.get_player_count()) != 2:
		return Result.failure("player_count 应保持不变: %d" % int(room.get_player_count()))
	if int(room.get_connected_player_count()) != 1:
		return Result.failure("connected_player_count 错误: %d" % int(room.get_connected_player_count()))
	var peer_ids: Array[int] = room.get_peer_ids()
	if peer_ids.size() != 1 or int(peer_ids[0]) != 11:
		return Result.failure("get_peer_ids 未剔除断线玩家: %s" % str(peer_ids))

	var room_state: Dictionary = room.to_room_state_dict()
	var players: Array = Array(room_state.get("players", []))
	if players.size() != 2:
		return Result.failure("room_state.players 长度错误: %d" % players.size())
	var disconnected_found := false
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = Dictionary(p_val)
		if int(p.get("peer_id", 0)) == 0 and not bool(p.get("connected", true)):
			disconnected_found = true
	if not disconnected_found:
		return Result.failure("room_state.players 未包含 connected=false 的断线占位")

	# InGame JoinRoom：旁观者加入（不占 seat / 不进入 player_id_by_peer_id）
	var jr2: Result = rm.join_room(20, {"name": "Spec", "color_index": 0}, room_code, "pw")
	if not jr2.ok:
		return Result.failure("JoinRoom(spectator) 失败: %s" % jr2.error)
	if str(Dictionary(jr2.value).get("role", "")) != "spectator":
		return Result.failure("JoinRoom(spectator) role 错误: %s" % str(Dictionary(jr2.value).get("role", "")))

	if int(room.get_player_count()) != 2:
		return Result.failure("spectator 加入不应改变 player_count: %d" % int(room.get_player_count()))
	var peer_ids2: Array[int] = room.get_peer_ids()
	if peer_ids2.size() != 2 or not peer_ids2.has(11) or not peer_ids2.has(20):
		return Result.failure("spectator 未进入 get_peer_ids: %s" % str(peer_ids2))
	if room.player_id_by_peer_id.has(20) or room.player_id_by_peer_id.has("20"):
		return Result.failure("spectator 不应进入 player_id_by_peer_id")

	var room_state2: Dictionary = room.to_room_state_dict()
	var spectators: Array = Array(room_state2.get("spectators", []))
	if spectators.size() != 1:
		return Result.failure("room_state.spectators 长度错误: %d" % spectators.size())

	# spectator 断线：应被移除
	var dr2: Result = rm.disconnect_peer(20)
	if not dr2.ok:
		return Result.failure("disconnect_peer(spectator) 失败: %s" % dr2.error)
	var room_state3: Dictionary = room.to_room_state_dict()
	if not Array(room_state3.get("spectators", [])).is_empty():
		return Result.failure("spectator 断线后未移除: %s" % str(room_state3.get("spectators", [])))

	return Result.success()

