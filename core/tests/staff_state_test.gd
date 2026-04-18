# staff_state 基础兼容层回归测试
class_name StaffStateTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_add_employee_syncs_active_staff_ids(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_add_employee_syncs_reserve_staff_ids(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_add_staff_for_busy_zone_syncs_busy_staff_ids(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_roundtrip_preserves_staff_registry_and_round_state(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)
	return Result.success(engine)

static func _test_add_employee_syncs_active_staff_ids(player_count: int, seed_val: int) -> Result:
	var engine_read := _make_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()

	var take := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take.ok:
		return Result.failure("take_from_pool(trainer) 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add.ok:
		return Result.failure("add_employee(active) 失败: %s" % add.error)
	var new_staff_id := int(Dictionary(add.value).get("staff_id", -1))
	if new_staff_id <= 0:
		return Result.failure("add_employee(active) 应返回有效 staff_id，实际: %s" % str(add.value))

	var player: Dictionary = state.get_player(0)
	var employees: Array = Array(player.get("employees", []))
	var employees_staff_ids: Array = Array(player.get("employees_staff_ids", []))
	var staff_registry: Dictionary = Dictionary(player.get("staff_registry", {}))
	if employees.size() != 2:
		return Result.failure("active 员工数量应为 2，实际: %d" % employees.size())
	if employees_staff_ids.size() != employees.size():
		return Result.failure("employees_staff_ids 应与 employees 等长，实际: %d vs %d" % [employees_staff_ids.size(), employees.size()])
	if not staff_registry.has(new_staff_id):
		return Result.failure("staff_registry 应包含新 staff_id=%d" % new_staff_id)
	var record: Dictionary = Dictionary(staff_registry.get(new_staff_id, {}))
	if str(record.get("employee_type", "")) != "trainer":
		return Result.failure("新 staff 记录 employee_type 应为 trainer，实际: %s" % str(record))
	return Result.success()

static func _test_add_employee_syncs_reserve_staff_ids(player_count: int, seed_val: int) -> Result:
	var engine_read := _make_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()

	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("take_from_pool(marketing_trainee) 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add.ok:
		return Result.failure("add_employee(reserve) 失败: %s" % add.error)
	var new_staff_id := int(Dictionary(add.value).get("staff_id", -1))
	if new_staff_id <= 0:
		return Result.failure("add_employee(reserve) 应返回有效 staff_id，实际: %s" % str(add.value))

	var player: Dictionary = state.get_player(0)
	var reserve_employees: Array = Array(player.get("reserve_employees", []))
	var reserve_staff_ids: Array = Array(player.get("reserve_staff_ids", []))
	if reserve_employees.size() != 1:
		return Result.failure("reserve_employees 数量应为 1，实际: %d" % reserve_employees.size())
	if reserve_staff_ids.size() != reserve_employees.size():
		return Result.failure("reserve_staff_ids 应与 reserve_employees 等长，实际: %d vs %d" % [reserve_staff_ids.size(), reserve_employees.size()])
	var zone_read := StaffStateClass.get_staff_zone(state, 0, new_staff_id)
	if not zone_read.ok:
		return Result.failure("get_staff_zone(reserve) 失败: %s" % zone_read.error)
	if str(zone_read.value) != "reserve_employees":
		return Result.failure("reserve staff 所在区域应为 reserve_employees，实际: %s" % str(zone_read.value))
	return Result.success()

static func _test_add_staff_for_busy_zone_syncs_busy_staff_ids(player_count: int, seed_val: int) -> Result:
	var engine_read := _make_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()

	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("take_from_pool(marketing_trainee busy) 失败: %s" % take.error)
	var add := StateUpdaterClass.add_staff_for_employee(state, 0, "marketing_trainee", "busy_marketers")
	if not add.ok:
		return Result.failure("add_staff_for_employee(busy_marketers) 失败: %s" % add.error)
	var new_staff_id := int(Dictionary(add.value).get("staff_id", -1))
	if new_staff_id <= 0:
		return Result.failure("add_staff_for_employee(busy_marketers) 应返回有效 staff_id，实际: %s" % str(add.value))

	var player: Dictionary = state.get_player(0)
	var busy_marketers: Array = Array(player.get("busy_marketers", []))
	var busy_staff_ids: Array = Array(player.get("busy_staff_ids", []))
	if busy_marketers.size() != 1:
		return Result.failure("busy_marketers 数量应为 1，实际: %d" % busy_marketers.size())
	if busy_staff_ids.size() != busy_marketers.size():
		return Result.failure("busy_staff_ids 应与 busy_marketers 等长，实际: %d vs %d" % [busy_staff_ids.size(), busy_marketers.size()])
	var zone_read := StaffStateClass.get_staff_zone(state, 0, new_staff_id)
	if not zone_read.ok:
		return Result.failure("get_staff_zone(busy) 失败: %s" % zone_read.error)
	if str(zone_read.value) != "busy_marketers":
		return Result.failure("busy staff 所在区域应为 busy_marketers，实际: %s" % str(zone_read.value))
	return Result.success()

static func _test_roundtrip_preserves_staff_registry_and_round_state(player_count: int, seed_val: int) -> Result:
	var engine_read := _make_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()

	var take_active := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_active.ok:
		return Result.failure("roundtrip take trainer 失败: %s" % take_active.error)
	var add_active := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_active.ok:
		return Result.failure("roundtrip add trainer 失败: %s" % add_active.error)
	var active_staff_id := int(Dictionary(add_active.value).get("staff_id", -1))

	var take_reserve := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take_reserve.ok:
		return Result.failure("roundtrip take marketing_trainee 失败: %s" % take_reserve.error)
	var add_reserve := StateUpdaterClass.add_employee(state, 0, "marketing_trainee", true)
	if not add_reserve.ok:
		return Result.failure("roundtrip add reserve 员工失败: %s" % add_reserve.error)
	var reserve_staff_id := int(Dictionary(add_reserve.value).get("staff_id", -1))

	state.round_state["staff_usage"] = {
		active_staff_id: {"recruit": 1},
		reserve_staff_id: {"train": 2},
	}
	state.round_state["staff_train_event_counts"] = {
		reserve_staff_id: 1,
	}

	var json_text := JSON.stringify(state.to_dict())
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return Result.failure("JSON.parse_string(state.to_dict()) 类型错误（期望 Dictionary）")
	var restored_read := GameState.from_dict(parsed)
	if not restored_read.ok:
		return Result.failure("GameState.from_dict(roundtrip) 失败: %s" % restored_read.error)
	var restored: GameState = restored_read.value

	var staff_usage_val = restored.round_state.get("staff_usage", null)
	if not (staff_usage_val is Dictionary):
		return Result.failure("roundtrip 后 staff_usage 类型错误（期望 Dictionary）")
	var staff_usage: Dictionary = staff_usage_val
	if staff_usage.has(str(active_staff_id)) or staff_usage.has(str(reserve_staff_id)):
		return Result.failure("roundtrip 后 staff_usage 不应保留字符串 key")
	if not staff_usage.has(active_staff_id) or not staff_usage.has(reserve_staff_id):
		return Result.failure("roundtrip 后 staff_usage 缺少 staff_id key: %d / %d" % [active_staff_id, reserve_staff_id])

	var counts_val = restored.round_state.get("staff_train_event_counts", null)
	if not (counts_val is Dictionary):
		return Result.failure("roundtrip 后 staff_train_event_counts 类型错误（期望 Dictionary）")
	var counts: Dictionary = counts_val
	if counts.has(str(reserve_staff_id)):
		return Result.failure("roundtrip 后 staff_train_event_counts 不应保留字符串 key")
	if int(counts.get(reserve_staff_id, -1)) != 1:
		return Result.failure("roundtrip 后 staff_train_event_counts[%d] 应为 1，实际: %s" % [reserve_staff_id, str(counts)])

	var player: Dictionary = restored.get_player(0)
	var registry: Dictionary = Dictionary(player.get("staff_registry", {}))
	if not registry.has(active_staff_id) or not registry.has(reserve_staff_id):
		return Result.failure("roundtrip 后 staff_registry 缺少新增 staff 记录")
	if int(restored.next_staff_id) <= max(active_staff_id, reserve_staff_id):
		return Result.failure("roundtrip 后 next_staff_id 应大于现有最大 staff_id，实际: %d" % int(restored.next_staff_id))
	return Result.success()
