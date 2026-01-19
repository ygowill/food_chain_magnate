# 回归：距离从餐厅入口起算时，入口格 -> 邻接道路格若跨越板块边界，应计入一次距离。
class_name DinnertimeDistanceEntryBoundaryTest
extends RefCounted

const DinnertimeDistanceClass = preload("res://core/rules/phase/dinnertime/dinnertime_distance.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_apply_test_map(state)

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("RoadGraph 未初始化")

	var house_id := "house"
	var rest_id := "rest_0"

	var houses: Dictionary = state.map.get("houses", {})
	var restaurants: Dictionary = state.map.get("restaurants", {})
	var house_val = houses.get(house_id, null)
	var rest_val = restaurants.get(rest_id, null)
	if not (house_val is Dictionary):
		return Result.failure("测试房屋不存在: %s" % house_id)
	if not (rest_val is Dictionary):
		return Result.failure("测试餐厅不存在: %s" % rest_id)
	var house: Dictionary = house_val
	var rest: Dictionary = rest_val

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var dist_r := DinnertimeDistanceClass.get_restaurant_to_house_distance(
		road_graph,
		state,
		grid_size,
		rest_id,
		rest,
		house_id,
		house
	)
	if not dist_r.ok:
		return Result.failure("距离计算失败: %s" % dist_r.error)
	if not (dist_r.value is Dictionary):
		return Result.failure("距离计算返回值类型错误（期望 Dictionary）")
	var info: Dictionary = dist_r.value
	if int(info.get("distance", -999)) != 1:
		return Result.failure("入口跨板块应导致距离=1，实际: %s" % str(info))

	return Result.success()

static func _apply_test_map(state: GameState) -> void:
	# 2×1 板块（TILE_SIZE=5），边界位于 x=5：
	# - 餐厅入口位于 (4,2)（左板块）
	# - 相邻道路位于 (5,2)（右板块）
	# - 房屋与该道路同板块，保证 RoadGraph 路径 distance=0，只靠“入口跨板块”贡献 +1
	var grid_size := Vector2i(10, 5)
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

	# 仅放置一个道路格（无需连通到其他道路，start=end 仍可求最短路）
	cells[2][5]["road_segments"] = [{"dirs": ["N"]}]

	var house_cells: Array[Vector2i] = [
		Vector2i(6, 1), Vector2i(7, 1),
		Vector2i(6, 2), Vector2i(7, 2),
	]
	for p in house_cells:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": "house",
			"dynamic": true
		}

	var rest_cells: Array[Vector2i] = [
		Vector2i(4, 2), Vector2i(4, 3),
		Vector2i(3, 2), Vector2i(3, 3),
	]
	for p in rest_cells:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": 0,
			"restaurant_id": "rest_0",
			"dynamic": true
		}

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house": {
				"house_id": "house",
				"house_number": 1,
				"anchor_pos": Vector2i(6, 1),
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
				"anchor_pos": Vector2i(4, 2),
				"entrance_pos": Vector2i(4, 2),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = []
	RoadGraphCacheClass.invalidate_road_graph(state)
