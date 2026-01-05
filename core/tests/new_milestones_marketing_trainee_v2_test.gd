# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST MARKETING TRAINEE USED
# - 触发：使用 marketer 发起营销
# - 效果：获得 kitchen_trainee 与 errand_boy 各 1 张（进入 reserve_employees）
class_name NewMilestonesMarketingTraineeV2Test
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "first_marketing_trainee_used"

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

	# 给玩家0 添加 1 张在岗 marketer（从池取卡，保持守恒）
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

	var reserve: Array = state.players[0].get("reserve_employees", [])
	if not (reserve is Array):
		return Result.failure("reserve_employees 类型错误（期望 Array）")
	if not reserve.has("kitchen_trainee"):
		return Result.failure("reserve_employees 应包含 kitchen_trainee，实际: %s" % str(reserve))
	if not reserve.has("errand_boy"):
		return Result.failure("reserve_employees 应包含 errand_boy，实际: %s" % str(reserve))

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
		"tile_grid_size": Vector2i(1, 1),
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
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	MapRuntimeClass.invalidate_road_graph(state)

