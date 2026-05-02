# 地图平衡分析模块回归测试
class_name MapBalanceAnalyzerTest
extends RefCounted

const AnalyzerClass = preload("res://core/map/map_balance/analyzer.gd")
const ThresholdsClass = preload("res://core/map/map_balance/thresholds.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_thresholds_expose_report_ranges()
	if not r.ok:
		return r
	r = _test_analyzer_counts_synthetic_map()
	if not r.ok:
		return r
	r = _test_analyzer_runs_on_generated_game_map()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _test_thresholds_expose_report_ranges() -> Result:
	var thresholds_read := ThresholdsClass.for_player_count(2)
	if not thresholds_read.ok:
		return thresholds_read
	var thresholds: Dictionary = thresholds_read.value
	var houses: Dictionary = thresholds.get("total_starting_houses", {})
	if int(houses.get("min", 0)) != 4 or int(houses.get("max", 0)) != 6:
		return Result.failure("2 人初始房屋阈值应为 4-6，实际: %s" % str(houses))
	var drinks: Dictionary = thresholds.get("total_drink_locations", {})
	if int(drinks.get("min", 0)) != 5 or int(drinks.get("max", 0)) != 7:
		return Result.failure("2 人饮料点阈值应为 5-7，实际: %s" % str(drinks))
	if int(thresholds.get("road_system_route_medium_min", 0)) != 3:
		return Result.failure("2 人 Medium+ 道路系统阈值应为 route_count>=3")
	return Result.success()

static func _test_analyzer_counts_synthetic_map() -> Result:
	var map_data := _build_synthetic_map_data()
	var analysis_read := AnalyzerClass.analyze_map_data(map_data, 2)
	if not analysis_read.ok:
		return analysis_read
	var analysis: Dictionary = analysis_read.value

	if int(analysis.get("total_starting_houses", -1)) != 1:
		return Result.failure("synthetic total_starting_houses 错误: %s" % str(analysis.get("total_starting_houses", null)))
	if int(analysis.get("total_drink_locations", -1)) != 1:
		return Result.failure("synthetic total_drink_locations 错误: %s" % str(analysis.get("total_drink_locations", null)))
	if int(analysis.get("neighborhood_count", -1)) != 2:
		return Result.failure("synthetic neighborhood_count 应为 2，实际: %s" % str(analysis.get("neighborhood_count", null)))
	if int(analysis.get("road_system_count", -1)) != 1:
		return Result.failure("synthetic road_system_count 应为 1，实际: %s" % str(analysis.get("road_system_count", null)))
	if int(analysis.get("max_starting_houses_in_neighborhood", -1)) != 1:
		return Result.failure("synthetic max_starting_houses_in_neighborhood 应为 1")
	if int(analysis.get("max_starting_houses_on_road_system", -1)) != 1:
		return Result.failure("synthetic max_starting_houses_on_road_system 应为 1")
	if int(analysis.get("max_drink_locations_on_road_system", -1)) != 1:
		return Result.failure("synthetic max_drink_locations_on_road_system 应为 1")
	if int(analysis.get("largest_road_system_route_count", -1)) != 5:
		return Result.failure("synthetic largest_road_system_route_count 应为 5")

	var eval_val = analysis.get("evaluation", null)
	if not (eval_val is Dictionary):
		return Result.failure("analyze_map_data(player_count>0) 应返回 evaluation")
	var evaluation: Dictionary = eval_val
	if not (evaluation.get("failed_checks", null) is Array):
		return Result.failure("evaluation.failed_checks 类型错误")
	return Result.success()

static func _test_analyzer_runs_on_generated_game_map() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var analysis_read := AnalyzerClass.analyze_state(engine.get_state(), 2)
	if not analysis_read.ok:
		return analysis_read
	var analysis: Dictionary = analysis_read.value

	if int(analysis.get("tile_count", 0)) != 9:
		return Result.failure("2 人生成地图 tile_count 应为 9，实际: %s" % str(analysis.get("tile_count", null)))
	if int(analysis.get("total_starting_houses", 0)) <= 0:
		return Result.failure("生成地图应至少有一个初始房屋")
	if int(analysis.get("road_system_count", 0)) <= 0:
		return Result.failure("生成地图应至少有一个道路系统")
	if not (analysis.get("drink_counts_by_type", null) is Dictionary):
		return Result.failure("生成地图分析应包含 drink_counts_by_type")
	if not (analysis.get("evaluation", null) is Dictionary):
		return Result.failure("生成地图分析应包含 evaluation")
	return Result.success({
		"score": Dictionary(analysis["evaluation"]).get("score", 0.0),
	})

static func _build_synthetic_map_data() -> Dictionary:
	var grid_size := Vector2i(5, 5)
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"road_segments": [],
				"blocked": false,
			})
		cells.append(row)

	for x in range(grid_size.x):
		var dirs: Array[String] = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		cells[2][x]["road_segments"].append({
			"dirs": dirs,
			"bridge": false,
		})

	var house_cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for pos in house_cells:
		cells[pos.y][pos.x]["structure"] = {
			"piece_id": "house",
			"owner": -1,
			"anchor_cell": pos == Vector2i(0, 0),
			"parent_anchor": Vector2i(0, 0),
			"house_id": "house_1",
			"house_number": 1,
			"dynamic": false,
		}

	cells[1][3]["drink_source"] = {"type": "beer"}

	return {
		"cells": cells,
		"grid_size": grid_size,
		"tile_placements": [
			{"tile_id": "synthetic", "board_pos": Vector2i.ZERO, "rotation": 0},
		],
		"houses": {
			"house_1": {
				"house_id": "house_1",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": house_cells,
				"printed": true,
				"demands": [],
			},
		},
		"restaurants": {},
		"drink_sources": [
			{"world_pos": Vector2i(3, 1), "type": "beer", "tile_id": "synthetic"},
		],
		"boundary_index": {},
		"map_origin": Vector2i.ZERO,
	}
