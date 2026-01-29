# 联机大厅：RoomList（公开房间列表）摘要与排序（M5）
class_name OnlineRoomListTest
extends RefCounted

const RoomManagerClass = preload("res://server/room_manager.gd")

static func run() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456

	var rm = RoomManagerClass.new(rng)

	var cr1: Result = rm.create_room(10, {"name": "Host1", "color_index": 0}, "", {"desired_player_count": 2})
	if not cr1.ok:
		return Result.failure("CreateRoom1 失败: %s" % cr1.error)
	var code1 := str(Dictionary(cr1.value).get("room_code", ""))

	var cr2: Result = rm.create_room(20, {"name": "Host2", "color_index": 1}, "pw", {"desired_player_count": 3})
	if not cr2.ok:
		return Result.failure("CreateRoom2 失败: %s" % cr2.error)
	var code2 := str(Dictionary(cr2.value).get("room_code", ""))

	var list: Array = rm.list_room_summaries()
	if list.size() != 2:
		return Result.failure("RoomList 长度错误: %d" % list.size())

	var seen := {}
	for i in range(list.size()):
		var s_val = list[i]
		if not (s_val is Dictionary):
			return Result.failure("RoomSummary 类型错误")
		var s: Dictionary = Dictionary(s_val)
		var code := str(s.get("room_code", ""))
		seen[code] = true

		if not s.has("status") or not s.has("desired_player_count") or not s.has("player_count"):
			return Result.failure("RoomSummary 缺少关键字段: %s" % str(s.keys()))
		if not s.has("password_required") or not s.has("allow_spectators") or not s.has("updated_at_ms"):
			return Result.failure("RoomSummary 缺少鉴权/观战/时间字段: %s" % str(s.keys()))
		if int(s.get("updated_at_ms", 0)) <= 0:
			return Result.failure("updated_at_ms 应为正数: %s" % str(s.get("updated_at_ms", 0)))

	# 必须包含两个 room_code
	if not seen.has(code1) or not seen.has(code2):
		return Result.failure("RoomList 未包含所有房间: have=%s need=[%s,%s]" % [str(seen.keys()), code1, code2])

	# password_required：无密码房间=false；有密码房间=true
	for s_val in list:
		var s: Dictionary = Dictionary(s_val)
		var code := str(s.get("room_code", ""))
		var required := bool(s.get("password_required", false))
		if code == code1 and required:
			return Result.failure("无密码房间 password_required 应为 false")
		if code == code2 and not required:
			return Result.failure("有密码房间 password_required 应为 true")

	# 排序：updated_at_ms 倒序；同时间按 room_code 倒序
	for i in range(list.size() - 1):
		var a: Dictionary = Dictionary(list[i])
		var b: Dictionary = Dictionary(list[i + 1])
		var ta := int(a.get("updated_at_ms", 0))
		var tb := int(b.get("updated_at_ms", 0))
		if ta < tb:
			return Result.failure("RoomList 未按 updated_at_ms 倒序排序: %d < %d" % [ta, tb])
		if ta == tb and str(a.get("room_code", "")) < str(b.get("room_code", "")):
			return Result.failure("RoomList 未按 room_code 倒序稳定排序")

	return Result.success()

