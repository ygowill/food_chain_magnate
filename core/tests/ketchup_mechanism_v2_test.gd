# 模块8：番茄酱机制（The Ketchup Mechanism）
# - “他人卖出你营销产生的需求” -> 晚餐结束时获得里程碑
# - 里程碑效果：晚餐距离 -1（clamp 到 0）
class_name KetchupMechanismV2Test
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "ketchup_sold_your_demand"
const EFFECT_ID := "ketchup_mechanism:dinnertime:distance_delta:ketchup"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

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
		"ketchup_mechanism",
	]
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 玩家0 的“营销需求”被玩家1 售出：player0 应在晚餐结算结束后获得里程碑
	_set_house_demands(state, "house_left", [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}])
	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != "Payday":
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	# distance_delta handler：distance=0 时 clamp 到 0；distance=2 时变为 1
	var effect_registry = engine.phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("EffectRegistry 未设置")
	var ctx0 := {"distance": 0}
	var r0: Result = effect_registry.invoke(EFFECT_ID, [state, 0, ctx0])
	if not r0.ok:
		return r0
	if int(ctx0.get("distance", -1)) != 0:
		return Result.failure("distance=0 应 clamp 到 0，实际: %s" % str(ctx0.get("distance", null)))
	var ctx2 := {"distance": 2}
	var r2: Result = effect_registry.invoke(EFFECT_ID, [state, 0, ctx2])
	if not r2.ok:
		return r2
	if int(ctx2.get("distance", -1)) != 1:
		return Result.failure("distance=2 应变为 1，实际: %s" % str(ctx2.get("distance", null)))

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
