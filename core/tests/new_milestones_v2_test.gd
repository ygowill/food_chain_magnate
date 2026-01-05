# 模块3：全新里程碑（New Milestones）
# 当前覆盖：FIRST MARKETEER USED
# - Marketing：每放置 1 个需求 +$5（仅由营销员放置的营销板件）
# - Dinnertime：distance -2，且允许为负
class_name NewMilestonesV2Test
extends RefCounted

const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "first_marketeer_used"

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
		"base_marketing",
		"new_milestones",
	]
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	state.phase = "Working"
	state.sub_phase = "Marketing"

	# 给玩家0 添加一张在岗营销员
	if int(state.employee_pool.get("marketer", 0)) <= 0:
		return Result.failure("employee_pool 中没有 marketer")
	state.employee_pool["marketer"] = int(state.employee_pool.get("marketer", 0)) - 1
	state.players[0]["employees"].append("marketer")

	var cmd := Command.create("initiate_marketing", 0, {
		"employee_type": "marketer",
		"board_number": 11,
		"product": "burger",
		"duration": 1,
		"position": [2, 1],
	})
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("initiate_marketing 执行失败: %s" % r.error)

	state = engine.get_state()
	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	# Marketing：结算应为放置的需求提供 $5
	var mk := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk.ok:
		return Result.failure("MarketingSettlement 失败: %s" % mk.error)
	if int(state.players[0].get("cash", -999)) != 5:
		return Result.failure("玩家0 cash 应为 5，实际: %s" % str(state.players[0].get("cash", null)))
	if int(state.bank.get("total", -999)) != 95:
		return Result.failure("bank.total 应为 95，实际: %s" % str(state.bank.get("total", null)))

	# Dinnertime：distance=0 时 -2 => -2，且不应因负数距离失败
	state.players[0]["inventory"]["burger"] = 1
	var ds := DinnertimeSettlementClass.apply(state, engine.phase_manager)
	if not ds.ok:
		return Result.failure("DinnertimeSettlement 失败（应允许负距离）：%s" % ds.error)

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
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# 贯通道路（y=2）
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_0", 1, house_cells)

	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"house_0": {
				"house_id": "house_0",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": house_cells,
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
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	# house 与 restaurant 同一个路口格（0,2）相邻 => shortest_path distance=0
	_set_house_demands(state, "house_0", [])

	state.players[0]["restaurants"] = ["rest_0"]
	MapRuntimeClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
