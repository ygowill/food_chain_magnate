# 模块9：薯条厨师（Fry Chefs）
# - 培训：从汉堡/披萨/寿司/面条厨师培训而来（通过 employee patch 注入 train_to）
# - 晚餐：每成功售卖一个“非饮品 food”的房屋，每个在岗 fry_chef +$10（按房屋算）
class_name FryChefsV2Test
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_train_to_patched(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_house_bonus_for_food(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_house_bonus_not_for_drink(seed_val)
	if not r3.ok:
		return r3

	return Result.success()

static func _test_train_to_patched(seed_val: int) -> Result:
	# 对照组：未启用 fry_chefs -> burger_cook.train_to 不应包含 fry_chef
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var b0 = EmployeeRegistryClass.get_def("burger_cook")
	if b0 == null:
		return Result.failure("缺少 burger_cook 定义")
	if (b0.train_to as Array).has("fry_chef"):
		return Result.failure("未启用 fry_chefs 时 burger_cook.train_to 不应包含 fry_chef")

	# 实验组：启用 fry_chefs -> 自动包含 noodles/sushi；并注入 train_to
	var e1 := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"fry_chefs",
	]
	var init1 := e1.initialize(2, seed_val, enabled_modules)
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)

	var plan: Array = e1.get_module_plan_v2()
	if not plan.has("noodles") or not plan.has("sushi"):
		return Result.failure("启用 fry_chefs 时应自动包含 noodles/sushi 依赖，实际 plan=%s" % str(plan))

	var b1 = EmployeeRegistryClass.get_def("burger_cook")
	if b1 == null:
		return Result.failure("缺少 burger_cook 定义（启用 fry_chefs 后）")
	if not (b1.train_to as Array).has("fry_chef"):
		return Result.failure("启用 fry_chefs 后 burger_cook.train_to 应包含 fry_chef，实际: %s" % str(b1.train_to))
	if EmployeeRegistryClass.get_def("fry_chef") == null:
		return Result.failure("启用 fry_chefs 后应存在 fry_chef 定义")

	return Result.success()

static func _test_house_bonus_for_food(seed_val: int) -> Result:
	var engine := _build_engine_with_fry_chefs(seed_val)
	if engine == null:
		return Result.failure("内部错误：engine 为空")

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "burger"}])
	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 0

	_take_to_active(state, 0, "fry_chef")

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.failure("round_state.dinnertime 缺失或类型错误（期望 Dictionary）")
	var ds: Dictionary = ds_val
	var bonus_val = ds.get("income_sale_house_bonus", null)
	if not (bonus_val is Array):
		return Result.failure("income_sale_house_bonus 缺失或类型错误（期望 Array[int]）")
	var bonus: Array = bonus_val
	if int(bonus[0]) != 10:
		return Result.failure("food 房屋售卖应触发 +10，实际: %s" % str(bonus))

	return Result.success()

static func _test_house_bonus_not_for_drink(seed_val: int) -> Result:
	var engine := _build_engine_with_fry_chefs(seed_val)
	if engine == null:
		return Result.failure("内部错误：engine 为空")

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "soda"}])
	state.players[0]["inventory"]["soda"] = 1
	state.players[1]["inventory"]["soda"] = 0

	_take_to_active(state, 0, "fry_chef")

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	var ds_val = state.round_state.get("dinnertime", null)
	if not (ds_val is Dictionary):
		return Result.failure("round_state.dinnertime 缺失或类型错误（期望 Dictionary）")
	var ds: Dictionary = ds_val
	var bonus_val = ds.get("income_sale_house_bonus", null)
	if not (bonus_val is Array):
		return Result.failure("income_sale_house_bonus 缺失或类型错误（期望 Array[int]）")
	var bonus: Array = bonus_val
	if int(bonus[0]) != 0:
		return Result.failure("drink 房屋售卖不应触发薯条厨师奖励，实际: %s" % str(bonus))

	return Result.success()

static func _build_engine_with_fry_chefs(seed_val: int) -> GameEngine:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"fry_chefs",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return null
	return engine

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = "Working"
	state.sub_phase = "PlaceRestaurants"
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

	var adv := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("推进到 Dinnertime 失败: %s" % adv.error)
	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)
	return cells

static func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var left_house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": left_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	MapRuntimeClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses

static func _take_to_active(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	state.players[player_id]["employees"].append(employee_id)

