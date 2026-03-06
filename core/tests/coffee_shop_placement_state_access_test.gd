# coffee shop placement 状态访问回归测试
class_name CoffeeShopPlacementStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/coffee/actions/place_or_move_coffee_shop_action.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_validate_coffee_shop_placement_succeeds_with_valid_map(seed_val)
	if not r.ok:
		return r
	r = _test_validate_coffee_shop_placement_fails_fast_on_missing_houses(seed_val)
	if not r.ok:
		return r
	r = _test_validate_coffee_shop_placement_fails_fast_on_missing_restaurants(seed_val)
	if not r.ok:
		return r
	r = _test_validate_coffee_shop_placement_fails_fast_on_missing_marketing_placements(seed_val)
	if not r.ok:
		return r
	r = _test_validate_coffee_shop_placement_fails_fast_on_invalid_marketing_placements_type(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_state(seed_val: int) -> Result:
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
		"coffee",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)
	_apply_train_test_map(state)
	_apply_coffee_map_fields(state)
	state.phase = PhaseDefsClass.PHASE_WORKING
	state.sub_phase = PhaseDefsClass.SUB_PHASE_TRAIN
	_mark_all_players_not_passed(state)
	state.round_state["train_events"] = [{
		"player_id": 0,
		"to_employee": "barista",
	}]
	return Result.success(state)

static func _make_command() -> Command:
	return Command.create("place_or_move_coffee_shop", 0, {
		"mode": "place",
		"position": [2, 1],
	})

static func _test_validate_coffee_shop_placement_succeeds_with_valid_map(seed_val: int) -> Result:
	var built := _make_state(seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var action = ActionClass.new()
	var result := action._validate_coffee_shop_placement(state, Vector2i(2, 1))
	if not result.ok:
		return Result.failure("_validate_coffee_shop_placement 不应失败: %s" % result.error)
	return Result.success()

static func _test_validate_coffee_shop_placement_fails_fast_on_missing_houses(seed_val: int) -> Result:
	var built := _make_state(seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.map.erase("houses")
	var action = ActionClass.new()
	var result := action._validate_coffee_shop_placement(state, Vector2i(2, 1))
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_validate_coffee_shop_placement_fails_fast_on_missing_restaurants(seed_val: int) -> Result:
	var built := _make_state(seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.map.erase("restaurants")
	var action = ActionClass.new()
	var result := action._validate_coffee_shop_placement(state, Vector2i(2, 1))
	if result.ok:
		return Result.failure("缺失 restaurants 时应失败")
	var err := str(result.error)
	if err.find("state.map.restaurants") < 0:
		return Result.failure("错误信息应包含 state.map.restaurants，实际: %s" % err)
	return Result.success()

static func _test_validate_coffee_shop_placement_fails_fast_on_missing_marketing_placements(seed_val: int) -> Result:
	var built := _make_state(seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.map.erase("marketing_placements")
	var action = ActionClass.new()
	var result := action._validate_coffee_shop_placement(state, Vector2i(2, 1))
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_validate_coffee_shop_placement_fails_fast_on_invalid_marketing_placements_type(seed_val: int) -> Result:
	var built := _make_state(seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.map["marketing_placements"] = []
	var action = ActionClass.new()
	var result := action._validate_coffee_shop_placement(state, Vector2i(2, 1))
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0

static func _mark_all_players_not_passed(state: GameState) -> void:
	state.round_state["sub_phase_passed"] = {0: false, 1: false}

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		cells.append(row)
	return cells

static func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true,
		}

static func _apply_coffee_map_fields(state: GameState) -> void:
	state.map["coffee_shops"] = {}
	state.map["next_coffee_shop_id"] = 1
	for pid in range(state.players.size()):
		state.players[pid]["coffee_shop_tokens_remaining"] = 3

static func _apply_train_test_map(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	}
	state.players[0]["restaurants"] = ["rest_0"]
	RoadGraphCacheClass.invalidate_road_graph(state)
