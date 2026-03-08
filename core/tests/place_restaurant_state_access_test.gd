# place_restaurant placement payload 状态访问回归测试
class_name PlaceRestaurantStateAccessTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlaceRestaurantActionClass = preload("res://gameplay/actions/place_restaurant_action.gd")

class FakePlacementValidator:
	extends RefCounted

	var _value

	func _init(value) -> void:
		_value = value

	func validate_restaurant_placement(_map_ctx: Dictionary, _world_anchor: Vector2i, _rotation: int, _piece_registry: Dictionary, _player_id: int, _is_initial: bool, _options: Dictionary) -> Result:
		return Result.success(_value)

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_fails_fast_on_invalid_placement_payload_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_fails_fast_on_invalid_placement_footprint_cells_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_fails_fast_on_invalid_placement_entrance_pos_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_fails_fast_on_invalid_player_restaurants_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_employee_type_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_when_no_new_restaurant_found()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_anchor_pos()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_opening_soon_missing_anchor_pos()
	if not r.ok:
		return r
	return Result.success({"cases": 8})

static func _build_place_restaurant_working_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	for pid in range(player_count):
		var grant := StateUpdaterClass.player_receive_from_bank(state, pid, 20)
		if not grant.ok:
			return Result.failure("发放测试现金失败: %s" % grant.error)
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working
	state = engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")
	var take := StateUpdaterClass.take_from_pool(state, "regional_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 regional_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "regional_manager", false)
	if not add.ok:
		return Result.failure("添加 regional_manager 失败: %s" % add.error)
	return Result.success(engine)

static func _test_apply_fails_fast_on_invalid_placement_payload_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_fails_fast_on_invalid_placement_response_without_partial_mutation(
		player_count,
		seed_val,
		"bad",
		"validate_restaurant_placement 返回值类型错误"
	)

static func _test_apply_fails_fast_on_invalid_placement_footprint_cells_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_fails_fast_on_invalid_placement_response_without_partial_mutation(
		player_count,
		seed_val,
		{"footprint_cells": [Vector2i.ZERO, "bad"], "entrance_pos": Vector2i.ZERO},
		"validate_restaurant_placement.footprint_cells[1] 类型错误"
	)

static func _test_apply_fails_fast_on_invalid_placement_entrance_pos_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	return _test_apply_fails_fast_on_invalid_placement_response_without_partial_mutation(
		player_count,
		seed_val,
		{"footprint_cells": [Vector2i.ZERO], "entrance_pos": "bad"},
		"validate_restaurant_placement 缺少 entrance_pos"
	)

static func _test_apply_fails_fast_on_invalid_placement_response_without_partial_mutation(player_count: int, seed_val: int, payload, expected_error: String) -> Result:
	var built := _build_place_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")
	var cmd := _find_first_valid_restaurant_placement(engine, actor, {"employee_type": "regional_manager"})
	if cmd == null:
		return Result.failure("找不到合法的餐厅放置点")
	var next_id_val = state.map.get("next_restaurant_id", null)
	if not (next_id_val is int):
		return Result.failure("map.next_restaurant_id 类型错误（期望 int）")
	var next_id_before: int = int(next_id_val)
	var predicted_rest_id := "rest_%d" % next_id_before
	var player_restaurants_before: Array = Array(state.players[actor].get("restaurants", []))
	var round_state_before := str(state.round_state)
	engine.action_registry.register_executor(PlaceRestaurantActionClass.new({}, FakePlacementValidator.new(payload)))
	var exec_result := engine.execute_command(cmd)
	if exec_result.ok:
		return Result.failure("placement payload 损坏时 place_restaurant apply 应失败")
	var err := str(exec_result.error)
	if err.find(expected_error) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error, err])
	state = engine.get_state()
	var next_id_after = state.map.get("next_restaurant_id", null)
	if not (next_id_after is int) or int(next_id_after) != next_id_before:
		return Result.failure("失败时不应提前递增 next_restaurant_id，实际: %s" % str(next_id_after))
	if state.map.get("restaurants", {}).has(predicted_rest_id):
		return Result.failure("失败时不应提前写入 map.restaurants: %s" % predicted_rest_id)
	var player_restaurants_after: Array = Array(state.players[actor].get("restaurants", []))
	if player_restaurants_after != player_restaurants_before:
		return Result.failure("失败时不应提前写入 player.restaurants")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	if _map_contains_restaurant_id(state, predicted_rest_id):
		return Result.failure("失败时不应提前写入餐厅格子结构: %s" % predicted_rest_id)
	return Result.success()

static func _test_apply_fails_fast_on_invalid_player_restaurants_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_place_restaurant_working_engine(player_count, seed_val)
	if not built.ok:
		return built
	var engine: GameEngine = built.value
	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")
	var cmd := _find_first_valid_restaurant_placement(engine, actor, {"employee_type": "regional_manager"})
	if cmd == null:
		return Result.failure("找不到合法的餐厅放置点")
	var next_id_val = state.map.get("next_restaurant_id", null)
	if not (next_id_val is int):
		return Result.failure("map.next_restaurant_id 类型错误（期望 int）")
	var next_id_before: int = int(next_id_val)
	var predicted_rest_id := "rest_%d" % next_id_before
	state.players[actor]["restaurants"] = "bad"
	var player_before := str(state.players[actor])
	var round_state_before := str(state.round_state)
	var exec_result := engine.execute_command(cmd)
	if exec_result.ok:
		return Result.failure("player.restaurants 类型错误时 place_restaurant apply 应失败")
	var err := str(exec_result.error)
	if err.find("player[%d].restaurants" % actor) < 0:
		return Result.failure("错误信息应包含 player[%d].restaurants，实际: %s" % [actor, err])
	state = engine.get_state()
	var next_id_after = state.map.get("next_restaurant_id", null)
	if not (next_id_after is int) or int(next_id_after) != next_id_before:
		return Result.failure("失败时不应提前递增 next_restaurant_id，实际: %s" % str(next_id_after))
	if state.map.get("restaurants", {}).has(predicted_rest_id):
		return Result.failure("失败时不应提前写入 map.restaurants: %s" % predicted_rest_id)
	if str(state.players[actor]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	if str(state.round_state) != round_state_before:
		return Result.failure("失败时不应提前改写 round_state")
	if _map_contains_restaurant_id(state, predicted_rest_id):
		return Result.failure("失败时不应提前写入餐厅格子结构: %s" % predicted_rest_id)
	return Result.success()

static func _make_event_state(restaurants: Dictionary, round_state_val = {}, phase_val: String = "") -> GameState:
	var state := GameState.new()
	state.map = {"restaurants": restaurants}
	state.round_state = round_state_val
	state.phase = phase_val
	return state

static func _test_generate_specific_events_returns_empty_on_invalid_employee_type_type() -> Result:
	var action = PlaceRestaurantActionClass.new()
	var old_state := _make_event_state({})
	var new_state := _make_event_state({"rest_1": {"anchor_pos": Vector2i.ZERO}})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_restaurant", 0, {"employee_type": 1}))
	if not events.is_empty():
		return Result.failure("employee_type 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_when_no_new_restaurant_found() -> Result:
	var action = PlaceRestaurantActionClass.new()
	var old_state := _make_event_state({"rest_1": {"anchor_pos": Vector2i.ZERO}})
	var new_state := _make_event_state({"rest_1": {"anchor_pos": Vector2i.ZERO}})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_restaurant", 0, {"employee_type": "regional_manager"}))
	if not events.is_empty():
		return Result.failure("未找到新餐厅时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_anchor_pos() -> Result:
	var action = PlaceRestaurantActionClass.new()
	var old_state := _make_event_state({})
	var new_state := _make_event_state({"rest_1": {}})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_restaurant", 0, {"employee_type": "regional_manager"}))
	if not events.is_empty():
		return Result.failure("anchor_pos 损坏时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_opening_soon_missing_anchor_pos() -> Result:
	var action = PlaceRestaurantActionClass.new()
	var old_state := _make_event_state({}, {"opening_soon_restaurants": []})
	var new_state := _make_event_state({}, {"opening_soon_restaurants": [{"restaurant_id": "rest_1"}]})
	var events := action._generate_specific_events(old_state, new_state, Command.create("place_restaurant", 0, {"employee_type": "regional_manager"}))
	if not events.is_empty():
		return Result.failure("opening_soon 缺少 anchor_pos 时应返回空事件列表")
	return Result.success()

static func _find_first_valid_restaurant_placement(engine: GameEngine, actor: int, extra_params: Dictionary = {}) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null
	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var params := {"position": [x, y], "rotation": r}
				if extra_params != null and not extra_params.is_empty():
					for k in extra_params.keys():
						params[k] = extra_params[k]
				var cmd := Command.create("place_restaurant", actor, params)
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd
	return null

static func _map_contains_restaurant_id(state: GameState, restaurant_id: String) -> bool:
	if state == null or restaurant_id.is_empty() or not (state.map is Dictionary):
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
			if structure_val is Dictionary and str((structure_val as Dictionary).get("restaurant_id", "")) == restaurant_id:
				return true
	return false
