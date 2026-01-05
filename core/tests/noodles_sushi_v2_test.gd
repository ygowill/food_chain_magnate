# Noodles / Sushi（模块6/7）晚餐替代规则测试（V2）
class_name NoodlesSushiV2Test
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_sushi_replaces_all_for_garden_house(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_noodles_only_when_base_unavailable(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_extra_luxury_manager_patch(seed_val)
	if not r3.ok:
		return r3

	return Result.success({
		"cases": 3,
		"seed": seed_val,
	})

static func _test_sushi_replaces_all_for_garden_house(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_garden(state, "house_left", true)

	# 花园房屋需求 2 个：若 sushi 足够，应优先用 sushi 完全替代
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	# 两边都能满足 base demand，但只有玩家0 有 sushi
	state.players[0]["inventory"]["burger"] = 2
	state.players[0]["inventory"]["soda"] = 2
	state.players[0]["inventory"]["sushi"] = 2

	state.players[1]["inventory"]["burger"] = 2
	state.players[1]["inventory"]["soda"] = 2
	state.players[1]["inventory"]["sushi"] = 0

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var cash0: int = int(state.players[0].get("cash", 0))
	# 花园翻倍“单价部分”：unit_price=10，quantity=2 => price_part=40
	if cash0 != 40:
		return Result.failure("寿司替代应使玩家0 获得 40，实际: %d" % cash0)
	if int(state.players[0]["inventory"].get("sushi", 0)) != 0:
		return Result.failure("寿司库存应被扣减至 0，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))
	if int(state.players[0]["inventory"].get("burger", 0)) != 2:
		return Result.failure("寿司替代不应消耗 burger，实际: %d" % int(state.players[0]["inventory"].get("burger", 0)))
	if int(state.players[0]["inventory"].get("soda", 0)) != 2:
		return Result.failure("寿司替代不应消耗 soda，实际: %d" % int(state.players[0]["inventory"].get("soda", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "sushi:replace_all":
		return Result.failure("demand_variant_id 应为 sushi:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_noodles_only_when_base_unavailable(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 非花园房屋：base demand 无人满足时，才用 noodles 完全替代
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 0
	state.players[0]["inventory"]["soda"] = 0
	state.players[0]["inventory"]["noodles"] = 0

	state.players[1]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["soda"] = 0
	state.players[1]["inventory"]["noodles"] = 2

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var cash1: int = int(state.players[1].get("cash", 0))
	if cash1 != 20:
		return Result.failure("面条替代应使玩家1 获得 20，实际: %d" % cash1)
	if int(state.players[1]["inventory"].get("noodles", 0)) != 0:
		return Result.failure("面条库存应被扣减至 0，实际: %d" % int(state.players[1]["inventory"].get("noodles", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "noodles:replace_all":
		return Result.failure("demand_variant_id 应为 noodles:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_extra_luxury_manager_patch(seed_val: int) -> Result:
	# 基线（2 人局 one_x=1）：base_rules 的 luxury_manager 应为 1
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var s0 := e0.get_state()
	var lm0: int = int(s0.employee_pool.get("luxury_manager", -1))
	if lm0 != 1:
		return Result.failure("基线 luxury_manager 应为 1，实际: %d" % lm0)

	# 启用 noodles：+1
	var e1 := GameEngine.new()
	var init1 := e1.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
	])
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var s1 := e1.get_state()
	var lm1: int = int(s1.employee_pool.get("luxury_manager", -1))
	if lm1 != 2:
		return Result.failure("启用 noodles 后 luxury_manager 应为 2，实际: %d" % lm1)

	# 启用 sushi + noodles：仍只加一次（去重）
	var e2 := GameEngine.new()
	var init2 := e2.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
		"sushi",
	])
	if not init2.ok:
		return Result.failure("初始化失败: %s" % init2.error)
	var s2 := e2.get_state()
	var lm2: int = int(s2.employee_pool.get("luxury_manager", -1))
	if lm2 != 2:
		return Result.failure("启用 noodles+sushi 后 luxury_manager 应为 2（只加一次），实际: %d" % lm2)

	return Result.success()

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

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i], has_garden: bool) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": has_garden,
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
	var right_house_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells, false)
	_set_house(cells, "house_right", 2, right_house_cells, false)

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
			"house_right": {
				"house_id": "house_right",
				"house_number": 2,
				"anchor_pos": Vector2i(8, 0),
				"cells": right_house_cells,
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
		"next_house_number": 3,
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

static func _set_house_garden(state: GameState, house_id: String, has_garden: bool) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["has_garden"] = has_garden
	houses[house_id] = house
	state.map["houses"] = houses
