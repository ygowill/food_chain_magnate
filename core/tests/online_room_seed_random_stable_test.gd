# 联机房间：seed_mode=random 时 seed 应保持稳定（用于大厅展示/可复现）
class_name OnlineRoomSeedRandomStableTest
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
		"seed_mode": "random",
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

	var seed_after := int(Dictionary(room.config).get("seed", 0))
	if seed_after != 12345:
		return Result.failure("seed_mode=random 时 seed 不应被重置: got=%d expected=%d" % [seed_after, 12345])

	return Result.success()

