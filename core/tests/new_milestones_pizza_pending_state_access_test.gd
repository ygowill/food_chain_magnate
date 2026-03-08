# new_milestones pizza pending 状态访问回归测试
class_name NewMilestonesPizzaPendingStateAccessTest
extends RefCounted

const EntryClass = preload("res://modules/new_milestones/rules/settlement_and_hooks.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")

const PIZZA_PENDING_KEY := "new_milestones_pizza_radios_pending"
const MILESTONE_ID_PIZZA_SOLD := "first_pizza_sold"

static func run(player_count: int = 2, seed_val: int = 880011) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)
	var r := _test_after_dinnertime_primary_builds_pizza_pending(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_is_fail_soft_without_marketing_placements(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_is_fail_soft_on_invalid_marketing_placements_type(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_skips_pending_when_all_radio_boards_are_used(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_fails_fast_on_missing_houses(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_fails_fast_on_invalid_anchor_pos(seed_val)
	if not r.ok:
		return r
	r = _test_after_dinnertime_primary_fails_fast_without_partial_mutation_on_invalid_pending_phase_actions(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 7})

static func _make_engine_state(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"new_milestones",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_apply_test_map(state)
	state.round_state = {
		"dinnertime": {
			"sales": [{
				"winner_owner": 0,
				"required": {"pizza": 1},
				"house_id": "h1",
				"house_number": 1,
			}]
		},
		"milestones_auto_awarded": [{"milestone_id": MILESTONE_ID_PIZZA_SOLD}],
	}
	return Result.success({"engine": engine, "state": state})

static func _test_after_dinnertime_primary_builds_pizza_pending(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if not result.ok:
		return Result.failure("_after_dinnertime_primary 失败: %s" % result.error)
	var pending_val = state.round_state.get(PIZZA_PENDING_KEY, null)
	if not (pending_val is Array):
		return Result.failure("应生成 pizza pending（Array），实际: %s" % str(pending_val))
	var pending: Array = pending_val
	if pending.size() != 1:
		return Result.failure("pizza pending 应为 1，实际: %d" % pending.size())
	return Result.success()

static func _test_after_dinnertime_primary_is_fail_soft_without_marketing_placements(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.map.erase("marketing_placements")
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if not result.ok:
		return Result.failure("缺失 marketing_placements 时应保持 fail-soft，实际: %s" % result.error)
	if state.round_state.has(PIZZA_PENDING_KEY):
		return Result.failure("缺失 marketing_placements 时不应写入 pizza pending，实际: %s" % str(state.round_state.get(PIZZA_PENDING_KEY, null)))
	if state.round_state.has("pending_phase_actions"):
		return Result.failure("缺失 marketing_placements 时不应写入 pending_phase_actions，实际: %s" % str(state.round_state.get("pending_phase_actions", null)))
	return Result.success()

static func _test_after_dinnertime_primary_is_fail_soft_on_invalid_marketing_placements_type(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.map["marketing_placements"] = []
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if not result.ok:
		return Result.failure("marketing_placements 类型错误时应保持 fail-soft，实际: %s" % result.error)
	if state.round_state.has(PIZZA_PENDING_KEY):
		return Result.failure("marketing_placements 类型错误时不应写入 pizza pending，实际: %s" % str(state.round_state.get(PIZZA_PENDING_KEY, null)))
	if state.round_state.has("pending_phase_actions"):
		return Result.failure("marketing_placements 类型错误时不应写入 pending_phase_actions，实际: %s" % str(state.round_state.get("pending_phase_actions", null)))
	return Result.success()

static func _test_after_dinnertime_primary_skips_pending_when_all_radio_boards_are_used(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.marketing_instances = [
		{"board_number": 1},
		{"board_number": 2},
		{"board_number": 3},
	]
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if not result.ok:
		return Result.failure("radio 板件已占满时应保持成功，实际: %s" % result.error)
	if state.round_state.has(PIZZA_PENDING_KEY):
		return Result.failure("radio 板件已占满时不应写入 pizza pending，实际: %s" % str(state.round_state.get(PIZZA_PENDING_KEY, null)))
	if state.round_state.has("pending_phase_actions"):
		return Result.failure("radio 板件已占满时不应写入 pending_phase_actions，实际: %s" % str(state.round_state.get("pending_phase_actions", null)))
	return Result.success()

static func _test_after_dinnertime_primary_fails_fast_on_missing_houses(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.map.erase("houses")
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_after_dinnertime_primary_fails_fast_on_invalid_anchor_pos(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.map["houses"]["h1"]["anchor_pos"] = [2, 1]
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if result.ok:
		return Result.failure("anchor_pos 类型错误时应失败")
	var err := str(result.error)
	if err.find("houses[h1].anchor_pos") < 0:
		return Result.failure("错误信息应包含 houses[h1].anchor_pos，实际: %s" % err)
	return Result.success()

static func _test_after_dinnertime_primary_fails_fast_without_partial_mutation_on_invalid_pending_phase_actions(seed_val: int) -> Result:
	var built := _make_engine_state(seed_val)
	if not built.ok:
		return built
	var payload: Dictionary = built.value
	var engine: GameEngine = payload["engine"]
	var state: GameState = payload["state"]
	state.round_state["pending_phase_actions"] = []
	var entry = EntryClass.new()
	var result := entry._after_dinnertime_primary(state, engine.phase_manager)
	if result.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 round_state.pending_phase_actions，实际: %s" % err)
	if state.round_state.has(PIZZA_PENDING_KEY):
		return Result.failure("失败时不应提前写入 pizza pending，实际: %s" % str(state.round_state.get(PIZZA_PENDING_KEY, null)))
	return Result.success()

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

static func _set_road(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road(cells, Vector2i(x, 2), dirs)
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	_set_house_1x1(cells, "h1", 1, Vector2i(2, 1))
	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h1": {"house_id": "h1", "house_number": 1, "anchor_pos": Vector2i(2, 1), "cells": [Vector2i(2, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 3), "entrance_pos": Vector2i(1, 2), "cells": rest_cells},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	}
	state.players[0]["restaurants"] = ["rest_0"]
	RoadGraphCacheClass.invalidate_road_graph(state)
