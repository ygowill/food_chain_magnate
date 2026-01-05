# Kimchi（模块5）规则测试（V2）
class_name KimchiV2Test
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_prefers_kimchi_restaurant_even_if_score_worse(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_cleanup_produces_and_forces_kimchi_storage(seed_val)
	if not r2.ok:
		return r2

	return Result.success({
		"cases": 2,
		"seed": seed_val,
	})

static func _test_prefers_kimchi_restaurant_even_if_score_worse(seed_val: int) -> Result:
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
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# house_left 需求 1 个 burger；两家餐厅都能满足 base，但只有玩家0 有 kimchi
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["kimchi"] = 1
	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["kimchi"] = 0

	# 让 base score 倾向玩家1（玩家0 单价更高）
	state.round_state["price_modifiers"] = {
		0: {"test": 1},
		1: {"test": 0},
	}

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	if int(state.players[0].get("cash", 0)) != 22:
		return Result.failure("Kimchi+base（2 件）收入应为 22，实际: %d" % int(state.players[0].get("cash", 0)))
	if int(state.players[1].get("cash", 0)) != 0:
		return Result.failure("玩家1 不应售出，现金应为 0，实际: %d" % int(state.players[1].get("cash", 0)))

	if int(state.players[0]["inventory"].get("burger", 0)) != 0:
		return Result.failure("burger 应被扣减，实际: %d" % int(state.players[0]["inventory"].get("burger", 0)))
	if int(state.players[0]["inventory"].get("kimchi", 0)) != 0:
		return Result.failure("kimchi 应被扣减，实际: %d" % int(state.players[0]["inventory"].get("kimchi", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "kimchi:kimchi_plus_base":
		return Result.failure("demand_variant_id 应为 kimchi:kimchi_plus_base，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_cleanup_produces_and_forces_kimchi_storage(seed_val: int) -> Result:
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
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()

	# 注入 kimchi_master（在岗），并给一些其他库存，验证 cleanup 后只保留 kimchi
	if int(state.employee_pool.get("kimchi_master", 0)) <= 0:
		return Result.failure("employee_pool 中没有 kimchi_master")
	state.employee_pool["kimchi_master"] = int(state.employee_pool.get("kimchi_master", 0)) - 1
	state.players[0]["employees"].append("kimchi_master")

	state.players[0]["inventory"]["burger"] = 3
	state.players[0]["inventory"]["pizza"] = 2

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	var inv: Dictionary = state.players[0]["inventory"]
	if int(inv.get("kimchi", 0)) != 1:
		return Result.failure("kimchi 应被生产并保留 1，实际: %d" % int(inv.get("kimchi", 0)))
	if int(inv.get("burger", 0)) != 0 or int(inv.get("pizza", 0)) != 0:
		return Result.failure("存储 kimchi 时其他产品应被丢弃，实际 inv=%s" % str(inv))

	var rs_kimchi: Dictionary = state.round_state.get("kimchi", {})
	var produced: Array = rs_kimchi.get("produced", [])
	if produced.is_empty():
		return Result.failure("round_state.kimchi.produced 应记录生产事件")

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
