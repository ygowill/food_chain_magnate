# place_house 状态访问回归测试
class_name PlaceHouseStateAccessTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlaceHouseActionClass = preload("res://gameplay/actions/place_house_action.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

class FakePlacementValidator:
	extends RefCounted

	var _value

	func _init(value) -> void:
		_value = value

	func validate_placement(_map_ctx: Dictionary, _piece_id: String, _world_anchor: Vector2i, _rotation: int, _piece_registry: Dictionary, _options: Dictionary) -> Result:
		return Result.success(_value)

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_house_placement_counts_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_placement_payload_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_footprint_cells_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_employee_type_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_when_no_new_house_found()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_anchor_pos()
	if not r.ok:
		return r
	r = _test_generate_specific_events_includes_staff_id_when_resolvable(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 7})

static func _test_apply_changes_fails_fast_on_invalid_house_placement_counts_without_partial_mutation(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("应处于 Working/PlaceHouses，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var take := StateUpdaterClass.take_from_pool(state, "new_business_developer", 1)
	if not take.ok:
		return Result.failure("从员工池取出 new_business_developer 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "new_business_developer", false)
	if not add.ok:
		return Result.failure("添加 new_business_developer 失败: %s" % add.error)

	var house_number := _pick_house_number(state)
	if house_number <= 0:
		return Result.failure("无法获取可用房屋编号")
	var cmd := _find_first_valid_house_placement(engine, actor, house_number)
	if cmd == null:
		return Result.failure("找不到合法的房屋放置点")

	var executor = engine.action_registry.get_executor("place_house")
	if executor == null:
		return Result.failure("缺少 place_house 执行器")

	state = engine.get_state()
	var predicted_house_id := str(house_number)
	var supply_before: String = str(state.map.get("house_number_supply_remaining", []))
	var houses_before: String = str(state.map.get("houses", {}))
	state.round_state["house_placement_counts"] = []

	var result := executor._apply_changes(state, cmd)
	if result.ok:
		return Result.failure("house_placement_counts 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.house_placement_counts") < 0:
		return Result.failure("错误信息应包含 round_state.house_placement_counts，实际: %s" % err)
	if str(state.map.get("house_number_supply_remaining", [])) != supply_before:
		return Result.failure("失败时不应提前消耗房屋编号供给")
	if str(state.map.get("houses", {})) != houses_before:
		return Result.failure("失败时不应提前改写 map.houses")
	if state.map.get("houses", {}).has(predicted_house_id):
		return Result.failure("失败时不应提前注册新房屋: %s" % predicted_house_id)
	if _map_contains_house_id(state, predicted_house_id):
		return Result.failure("失败时不应提前写入房屋格子结构: %s" % predicted_house_id)

	return Result.success(true)

static func _test_apply_changes_fails_fast_on_invalid_placement_payload_without_partial_mutation(seed_val: int) -> Result:
	return _test_apply_changes_fails_fast_on_invalid_placement_response_without_partial_mutation(
		seed_val,
		"bad",
		"validate_placement 返回值类型错误"
	)

static func _test_apply_changes_fails_fast_on_invalid_footprint_cells_without_partial_mutation(seed_val: int) -> Result:
	return _test_apply_changes_fails_fast_on_invalid_placement_response_without_partial_mutation(
		seed_val,
		{"footprint_cells": [Vector2i.ZERO, "bad"]},
		"validate_placement.footprint_cells[1] 类型错误"
	)

static func _test_apply_changes_fails_fast_on_invalid_placement_response_without_partial_mutation(seed_val: int, payload, expected_error: String) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_HOUSES:
		return Result.failure("应处于 Working/PlaceHouses，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var take := StateUpdaterClass.take_from_pool(state, "new_business_developer", 1)
	if not take.ok:
		return Result.failure("从员工池取出 new_business_developer 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "new_business_developer", false)
	if not add.ok:
		return Result.failure("添加 new_business_developer 失败: %s" % add.error)

	var house_number := _pick_house_number(state)
	if house_number <= 0:
		return Result.failure("无法获取可用房屋编号")
	var cmd := _find_first_valid_house_placement(engine, actor, house_number)
	if cmd == null:
		return Result.failure("找不到合法的房屋放置点")

	var predicted_house_id := str(house_number)
	var supply_before := str(state.map.get("house_number_supply_remaining", []))
	var houses_before := str(state.map.get("houses", {}))
	var round_state_before := str(state.round_state)
	var original_executor = engine.action_registry.get_executor("place_house")
	if original_executor == null:
		return Result.failure("缺少 place_house 执行器")
	engine.action_registry.register_executor(PlaceHouseActionClass.new(original_executor._piece_registry, FakePlacementValidator.new(payload)))
	var result := engine.execute_command(cmd)
	if result.ok:
		return Result.failure("placement payload 损坏时 place_house apply 应失败")
	var err := str(result.error)
	if err.find(expected_error) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error, err])
	state = engine.get_state()
	if str(state.map.get("house_number_supply_remaining", [])) != supply_before:
		return Result.failure("失败时不应提前消耗房屋编号供给")
	if str(state.map.get("houses", {})) != houses_before:
		return Result.failure("失败时不应提前改写 map.houses")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	if state.map.get("houses", {}).has(predicted_house_id):
		return Result.failure("失败时不应提前注册新房屋: %s" % predicted_house_id)
	if _map_contains_house_id(state, predicted_house_id):
		return Result.failure("失败时不应提前写入房屋格子结构: %s" % predicted_house_id)
	return Result.success(true)

static func _find_first_valid_house_placement(engine: GameEngine, actor: int, house_number: int) -> Command:
	var state := engine.get_state()
	var executor = engine.action_registry.get_executor("place_house")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var cmd := Command.create("place_house", actor, {"position": [x, y], "rotation": r, "house_number": int(house_number)})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd
	return null

static func _pick_house_number(state: GameState) -> int:
	if state == null or not (state.map is Dictionary):
		return -1
	var supply_val = state.map.get("house_number_supply_remaining", null)
	if supply_val is Array:
		var nums: Array[int] = []
		for v in Array(supply_val):
			if v is int:
				nums.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					nums.append(int(f))
		nums.sort()
		return int(nums[0]) if not nums.is_empty() else -1
	return 1

static func _map_contains_house_id(state: GameState, house_id: String) -> bool:
	if state == null or house_id.is_empty() or not (state.map is Dictionary):
		return false
	var cells_val = state.map.get("cells", null)
	if not (cells_val is Array):
		return false
	var cells: Array = cells_val
	for y in range(cells.size()):
		var row_val = cells[y]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for x in range(row.size()):
			var cell_val = row[x]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var structure_val = cell.get("structure", null)
			if structure_val is Dictionary and str((structure_val as Dictionary).get("house_id", "")) == house_id:
				return true
	return false

static func _make_event_state(houses: Dictionary) -> GameState:
	var state := GameState.new()
	state.map = {"houses": houses}
	return state

static func _test_generate_specific_events_returns_empty_on_invalid_employee_type_type() -> Result:
	var action = PlaceHouseActionClass.new()
	var old_state := _make_event_state({})
	var new_state := _make_event_state({})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_house", 0, {"employee_type": 1}))
	if not events.is_empty():
		return Result.failure("employee_type 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_when_no_new_house_found() -> Result:
	var action = PlaceHouseActionClass.new()
	var old_state := _make_event_state({"h1": {"house_number": 1, "anchor_pos": Vector2i.ZERO}})
	var new_state := _make_event_state({"h1": {"house_number": 1, "anchor_pos": Vector2i.ZERO}})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_house", 0, {"employee_type": "new_business_developer"}))
	if not events.is_empty():
		return Result.failure("未找到新房屋时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_anchor_pos() -> Result:
	var action = PlaceHouseActionClass.new()
	var old_state := _make_event_state({})
	var new_state := _make_event_state({"h1": {"house_number": 1}})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_house", 0, {"employee_type": "new_business_developer"}))
	if not events.is_empty():
		return Result.failure("anchor_pos 损坏时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_includes_staff_id_when_resolvable(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val + 701)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working
	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_HOUSES
	var actor := state.get_current_player_id()
	var take := StateUpdaterClass.take_from_pool(state, "new_business_developer", 1)
	if not take.ok:
		return Result.failure("取出 new_business_developer 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "new_business_developer", false)
	if not add.ok:
		return Result.failure("添加 new_business_developer 失败: %s" % add.error)
	var staff_id := int(Dictionary(add.value).get("staff_id", -1))
	if staff_id <= 0:
		return Result.failure("new_business_developer staff_id 无效: %s" % str(add.value))
	var house_number := _pick_house_number(state)
	var cmd := _find_first_valid_house_placement(engine, actor, house_number)
	if cmd == null:
		return Result.failure("找不到合法房屋放置点")
	cmd.params["staff_id"] = staff_id
	cmd.params["employee_type"] = "new_business_developer"
	var action = PlaceHouseActionClass.new()
	var old_state := engine.get_state().duplicate_state()
	var result := engine.execute_command(cmd)
	if not result.ok:
		return Result.failure("place_house 执行失败: %s" % result.error)
	var new_state := engine.get_state()
	var events := action._generate_specific_events(old_state, new_state, cmd)
	if events.size() != 1:
		return Result.failure("应生成 1 条 HOUSE_PLACED 事件，实际: %d" % events.size())
	var data_val = Dictionary(events[0]).get("data", null)
	if not (data_val is Dictionary):
		return Result.failure("HOUSE_PLACED 事件缺少 data")
	var data: Dictionary = data_val
	if int(data.get("staff_id", -1)) != staff_id:
		return Result.failure("HOUSE_PLACED 事件应包含 staff_id=%d，实际: %s" % [staff_id, str(data)])
	var used_read := StaffStateClass.get_staff_track_used(new_state, staff_id, "place_house_or_garden")
	if not used_read.ok or int(used_read.value) != 1:
		return Result.failure("place_house 应写入 staff_usage[%d].place_house_or_garden=1，实际: %s" % [staff_id, str(used_read)])
	return Result.success()
