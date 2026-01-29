# 联机房间：RoomManager 逻辑测试（M1）
class_name OnlineRoomManagerTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456

	var rm = RoomManagerClass.new(rng)

	var host_peer_id := 10
	var host_profile := {"name": "Host", "color_index": 1}
	var config := {"desired_player_count": 2}

	var cr: Result = rm.create_room(host_peer_id, host_profile, "pw", config)
	if not cr.ok:
		return Result.failure("CreateRoom 失败: %s" % cr.error)

	var room_code := str(Dictionary(cr.value).get("room_code", ""))
	if room_code.length() != 6:
		return Result.failure("room_code 长度错误: %s" % room_code)
	if room_code != room_code.to_upper():
		return Result.failure("room_code 非全大写: %s" % room_code)

	var jr_bad: Result = rm.join_room(11, {"name": "P2", "color_index": 2}, room_code, "bad")
	if jr_bad.ok:
		return Result.failure("JoinRoom 预期密码错误失败，但实际 ok=true")

	var jr: Result = rm.join_room(11, {"name": "P2", "color_index": 2}, room_code, "pw")
	if not jr.ok:
		return Result.failure("JoinRoom 失败: %s" % jr.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		return Result.failure("JoinRoom 后 rooms 未包含 room_code=%s" % room_code)
	if room.get_player_count() != 2:
		return Result.failure("玩家数量错误: %d" % room.get_player_count())

	var jr_full: Result = rm.join_room(12, {"name": "P3", "color_index": 3}, room_code, "pw")
	if jr_full.ok:
		return Result.failure("JoinRoom 预期满员失败，但实际 ok=true")

	var lr_host: Result = rm.leave_room(host_peer_id)
	if not lr_host.ok:
		return Result.failure("LeaveRoom(host) 失败: %s" % lr_host.error)

	var room_after_host_leave = rm.rooms.get(room_code, null)
	if room_after_host_leave == null:
		return Result.failure("房主离开后房间不应被销毁")
	if room_after_host_leave.host_peer_id != 11:
		return Result.failure("房主迁移错误: host_peer_id=%d" % room_after_host_leave.host_peer_id)

	var lr_last: Result = rm.leave_room(11)
	if not lr_last.ok:
		return Result.failure("LeaveRoom(last) 失败: %s" % lr_last.error)
	if rm.rooms.has(room_code):
		return Result.failure("最后一人离开后房间应被销毁，但 rooms 仍包含 room_code=%s" % room_code)

	# 缺少参数：room_code
	var jr_missing: Result = rm.join_room(20, {"name": "X", "color_index": 0}, "", "pw")
	if jr_missing.ok or jr_missing.error_code != Result.ErrorCode.MISSING_PARAMS:
		return Result.failure("JoinRoom 缺少 room_code 预期返回 MISSING_PARAMS，但实际 ok=%s error_code=%d" % [str(jr_missing.ok), int(jr_missing.error_code)])

	# 无密码房间：room_password 为空时，JoinRoom 不应要求密码匹配
	var cr2: Result = rm.create_room(30, {"name": "Host2", "color_index": 0}, "", {"desired_player_count": 2})
	if not cr2.ok:
		return Result.failure("CreateRoom(无密码) 失败: %s" % cr2.error)
	var room_code2 := str(Dictionary(cr2.value).get("room_code", ""))
	var jr2: Result = rm.join_room(31, {"name": "P2", "color_index": 1}, room_code2, "any")
	if not jr2.ok:
		return Result.failure("JoinRoom(无密码) 失败: %s" % jr2.error)

	return Result.success()
