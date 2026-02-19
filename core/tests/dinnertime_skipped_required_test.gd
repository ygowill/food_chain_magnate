# skipped 订单：应包含 required 明细（用于 UI 显示需求图标）
class_name DinnertimeSkippedRequiredTest
extends RefCounted

const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % pid)
		var p: Dictionary = p_val
		var inv_val = p.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("players[%d].inventory 类型错误（期望 Dictionary）" % pid)
		var inv: Dictionary = inv_val
		inv["burger"] = 0
		p["inventory"] = inv
		state.players[pid] = p

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	var dt_val = state.round_state.get("dinnertime", null)
	if not (dt_val is Dictionary):
		return Result.failure("round_state.dinnertime 缺失或类型错误（期望 Dictionary）")
	var dt: Dictionary = dt_val
	var skipped_val = dt.get("skipped", null)
	if not (skipped_val is Array):
		return Result.failure("round_state.dinnertime.skipped 缺失或类型错误（期望 Array）")
	var skipped: Array = skipped_val
	if skipped.is_empty():
		return Result.failure("应存在 skipped 订单，但 skipped 为空")

	var entry: Dictionary = {}
	for e_val in skipped:
		if e_val is Dictionary and str((e_val as Dictionary).get("house_id", "")) == "house_left":
			entry = e_val
			break
	if entry.is_empty():
		return Result.failure("skipped 中缺少 house_left")

	var req_val = entry.get("required", null)
	if not (req_val is Dictionary):
		return Result.failure("skipped[house_left].required 缺失或类型错误（期望 Dictionary）")
	var req: Dictionary = req_val
	if int(req.get("burger", 0)) != 1:
		return Result.failure("skipped[house_left].required.burger 应为 1，实际: %s" % str(req.get("burger", null)))

	return Result.success()

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))
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

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i], entrance_pos: Vector2i) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)  # 2×1 板块（TILE_SIZE=5），用于测试跨板块距离
	var cells := _build_empty_cells(grid_size)

	# 水平道路 y=2，连接左右两块板
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
	_set_restaurant(cells, "rest_0", 0, rest0_cells, Vector2i(0, 3))
	_set_restaurant(cells, "rest_1", 1, rest1_cells, Vector2i(9, 3))

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
	RoadGraphCacheClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
