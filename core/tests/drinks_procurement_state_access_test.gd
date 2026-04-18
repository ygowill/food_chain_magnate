# 饮料采购状态访问回归测试
class_name DrinksProcurementStateAccessTest
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const PlanResolverClass = preload("res://core/rules/drinks_procurement/plan_resolver.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const ActionClass = preload("res://gameplay/actions/procure_drinks_action.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_resolve_procurement_plan_fails_fast_on_missing_drink_sources()
	if not r.ok:
		return r
	r = _test_resolve_procurement_plan_fails_fast_on_invalid_drink_sources_type()
	if not r.ok:
		return r
	r = _test_get_tile_size_fails_fast_on_missing_grid_size()
	if not r.ok:
		return r
	r = _test_get_tile_bounds_fails_fast_on_missing_tile_grid_size()
	if not r.ok:
		return r
	r = _test_get_tile_positions_set_result_fails_fast_on_invalid_external_tile_placements_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_missing_employee_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_employee_type_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_includes_staff_id_for_errand_boy()
	if not r.ok:
		return r
	return Result.success({"cases": 8})

static func _make_procurement_state() -> GameState:
	var state := GameState.new()
	state.next_staff_id = 1
	state.phase = "working"
	state.sub_phase = "get_drinks"
	state.current_player_index = 0
	state.turn_order = [0]
	state.round_number = 1
	state.players = [{
		"employees": ["errand_boy"],
		"reserve_employees": [],
		"busy_marketers": [],
		"staff_registry": {
			1: {
				"staff_id": 1,
				"employee_type": "errand_boy",
				"created_round": 1,
			}
		},
		"employees_staff_ids": [1],
		"reserve_staff_ids": [],
		"busy_staff_ids": [],
		"inventory": {},
		"milestones": [],
	}]
	state.round_state = {}
	state.map = {
		"restaurants": {
			"rest_0": {
				"owner": 0,
				"entrance_pos": Vector2i(0, 0),
			}
		},
		"drink_sources": [{
			"world_pos": Vector2i(1, 1),
			"type": "soda",
			"tile_id": "A",
		}],
	}
	return state

static func _make_tile_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(10, 10),
		"tile_grid_size": Vector2i(2, 2),
		"tile_placements": [{
			"board_pos": Vector2i(0, 0),
		}],
		"external_tile_placements": [],
	}
	return state

static func _make_employee_def() -> EmployeeDef:
	var emp_def := EmployeeDefClass.new()
	emp_def.id = "truck_driver"
	emp_def.range_type = "road"
	emp_def.range_value = 3
	return emp_def

static func _make_command() -> Command:
	return Command.create("procure_drinks", 0, {})

static func _make_restaurant_ids() -> Array[String]:
	return ["rest_0"]

static func _test_resolve_procurement_plan_fails_fast_on_missing_drink_sources() -> Result:
	var state := _make_procurement_state()
	state.map.erase("drink_sources")
	var result := PlanResolverClass.resolve_procurement_plan(
		state,
		_make_command(),
		_make_restaurant_ids(),
		_make_employee_def()
	)
	if result.ok:
		return Result.failure("缺失 drink_sources 时应失败")
	var err := str(result.error)
	if err.find("state.map.drink_sources") < 0:
		return Result.failure("错误信息应包含 state.map.drink_sources，实际: %s" % err)
	return Result.success()

static func _test_resolve_procurement_plan_fails_fast_on_invalid_drink_sources_type() -> Result:
	var state := _make_procurement_state()
	state.map["drink_sources"] = {}
	var result := PlanResolverClass.resolve_procurement_plan(
		state,
		_make_command(),
		_make_restaurant_ids(),
		_make_employee_def()
	)
	if result.ok:
		return Result.failure("drink_sources 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.drink_sources") < 0:
		return Result.failure("错误信息应包含 state.map.drink_sources，实际: %s" % err)
	return Result.success()

static func _test_get_tile_size_fails_fast_on_missing_grid_size() -> Result:
	var state := _make_tile_state()
	state.map.erase("grid_size")
	var result := TileRouteUtilsClass.get_tile_size(state, "DrinksProcurementStateAccessTest")
	if result.ok:
		return Result.failure("缺失 grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.grid_size，实际: %s" % err)
	return Result.success()

static func _test_get_tile_bounds_fails_fast_on_missing_tile_grid_size() -> Result:
	var state := _make_tile_state()
	state.map.erase("tile_grid_size")
	var result := TileRouteUtilsClass.get_tile_bounds(state, "DrinksProcurementStateAccessTest")
	if result.ok:
		return Result.failure("缺失 tile_grid_size 时应失败")
	var err := str(result.error)
	if err.find("state.map.tile_grid_size") < 0:
		return Result.failure("错误信息应包含 state.map.tile_grid_size，实际: %s" % err)
	return Result.success()

static func _test_get_tile_positions_set_result_fails_fast_on_invalid_external_tile_placements_type() -> Result:
	var state := _make_tile_state()
	state.map["external_tile_placements"] = {}
	var result := TileRouteUtilsClass.get_tile_positions_set_result(state, "DrinksProcurementStateAccessTest")
	if result.ok:
		return Result.failure("external_tile_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.external_tile_placements") < 0:
		return Result.failure("错误信息应包含 state.map.external_tile_placements，实际: %s" % err)
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_missing_employee_type() -> Result:
	var action = ActionClass.new()
	var state := _make_procurement_state()
	var events := action._generate_specific_events(state, state, Command.create("procure_drinks", 0, {}))
	if not events.is_empty():
		return Result.failure("缺失 employee_type 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_employee_type_type() -> Result:
	var action = ActionClass.new()
	var state := _make_procurement_state()
	var events := action._generate_specific_events(state, state, Command.create("procure_drinks", 0, {"employee_type": 1}))
	if not events.is_empty():
		return Result.failure("employee_type 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_includes_staff_id_for_errand_boy() -> Result:
	var action = ActionClass.new()
	var state := _make_procurement_state()
	var used_before := StaffStateClass.get_staff_track_used(state, 1, "procure_drinks")
	if not used_before.ok:
		return Result.failure("读取 errand_boy 初始 staff usage 失败: %s" % used_before.error)
	if int(used_before.value) != 0:
		return Result.failure("errand_boy 初始 procure_drinks usage 应为 0，实际: %s" % str(used_before.value))
	var events := action._generate_specific_events(state, state, Command.create("procure_drinks", 0, {
		"employee_type": "errand_boy",
		"staff_id": 1,
		"drink_type": "beer",
	}))
	if events.size() != 1:
		return Result.failure("errand_boy 应生成 1 条采购事件，实际: %d" % events.size())
	var event_val = events[0]
	if not (event_val is Dictionary):
		return Result.failure("errand_boy 采购事件类型错误（期望 Dictionary）")
	var event: Dictionary = event_val
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return Result.failure("errand_boy 采购事件缺少 data")
	var data: Dictionary = data_val
	if int(data.get("staff_id", -1)) != 1:
		return Result.failure("errand_boy 采购事件应包含 staff_id=1，实际: %s" % str(data))
	var drinks_procured_val = data.get("drinks_procured", null)
	if not (drinks_procured_val is Dictionary):
		return Result.failure("errand_boy 采购事件缺少 drinks_procured")
	var drinks_procured: Dictionary = drinks_procured_val
	if int(drinks_procured.get("beer", 0)) != 1:
		return Result.failure("errand_boy 采购事件的 drinks_procured[beer] 应为 1，实际: %s" % str(drinks_procured))
	var used_after := StaffStateClass.get_staff_track_used(state, 1, "procure_drinks")
	if not used_after.ok:
		return Result.failure("读取 errand_boy 事件后 staff usage 失败: %s" % used_after.error)
	if int(used_after.value) != 0:
		return Result.failure("生成事件不应改写 staff usage，实际: %s" % str(used_after.value))
	return Result.success()
