# place_restaurant opening-soon 状态访问回归测试
class_name PlaceRestaurantOpeningSoonStateAccessTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_opening_soon_key_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 1})

static func _test_apply_changes_fails_fast_on_invalid_opening_soon_key_without_partial_mutation(player_count: int, seed_val: int) -> Result:
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
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		return Result.failure("应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add.ok:
		return Result.failure("添加 local_manager 失败: %s" % add.error)

	var cmd := _find_first_valid_restaurant_placement(engine, actor, {"employee_type": "local_manager"})
	if cmd == null:
		return Result.failure("找不到合法的餐厅放置点")

	state = engine.get_state()
	var next_id_val = state.map.get("next_restaurant_id", null)
	if not (next_id_val is int):
		return Result.failure("map.next_restaurant_id 类型错误（期望 int）")
	var next_id_before: int = int(next_id_val)
	var predicted_rest_id := "rest_%d" % next_id_before
	var player_restaurants_before: Array = Array(state.players[actor].get("restaurants", []))
	state.round_state["opening_soon_restaurants"] = {}

	var exec_result := engine.execute_command(cmd)
	if exec_result.ok:
		return Result.failure("opening_soon_restaurants 类型错误时应失败")
	var err := str(exec_result.error)
	if err.find("state.round_state.opening_soon_restaurants") < 0:
		return Result.failure("错误信息应包含 state.round_state.opening_soon_restaurants，实际: %s" % err)

	state = engine.get_state()
	var next_id_after = state.map.get("next_restaurant_id", null)
	if not (next_id_after is int) or int(next_id_after) != next_id_before:
		return Result.failure("失败时不应提前递增 next_restaurant_id，实际: %s" % str(next_id_after))
	if state.map.get("restaurants", {}).has(predicted_rest_id):
		return Result.failure("失败时不应提前写入 map.restaurants: %s" % predicted_rest_id)
	var player_restaurants_after: Array = Array(state.players[actor].get("restaurants", []))
	if player_restaurants_after != player_restaurants_before:
		return Result.failure("失败时不应提前写入 player.restaurants")
	var pending_val = state.round_state.get("opening_soon_restaurants", null)
	if not (pending_val is Dictionary):
		return Result.failure("失败时不应改写非法 opening_soon_restaurants，实际: %s" % str(pending_val))
	if _map_contains_restaurant_id(state, predicted_rest_id):
		return Result.failure("失败时不应提前写入餐厅格子结构: %s" % predicted_rest_id)

	return Result.success(true)

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
