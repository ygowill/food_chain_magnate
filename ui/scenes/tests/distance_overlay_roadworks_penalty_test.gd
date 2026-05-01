# DistanceOverlay roadworks penalty regression test
# Ensures distance tool reflects lobbyists roadworks markers (+1 per marked road cell passed).
class_name DistanceOverlayRoadworksPenaltyTest
extends RefCounted

const DistanceOverlayClass = preload("res://ui/overlays/distance_overlay.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")

static func run(seed_val: int = 12345) -> Result:
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
		"lobbyists",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, e)
	var ui_metadata_apply := ModuleUiMetadataBootstrapClass.apply(e)
	if not ui_metadata_apply.ok:
		return _finish(Result.failure("UI metadata 装配失败: %s" % ui_metadata_apply.error), null, e)
	var s: GameState = e.get_state()

	var road_graph = RoadGraphCacheClass.get_road_graph(s)
	if road_graph == null:
		return _finish(Result.failure("道路图未初始化"), null, e)

	var pick := _pick_connected_road_path(s, road_graph)
	if not pick.ok:
		return _finish(pick, null, e)
	var path: Array[Vector2i] = pick.value
	if path.size() < 3:
		return _finish(Result.failure("测试需要 >=3 的道路 path（实际: %d）" % path.size()), null, e)

	var from_pos: Vector2i = path[0]
	var to_pos: Vector2i = path[path.size() - 1]
	var interior_marker_pos: Vector2i = path[1]
	var cases: Array[Dictionary] = [
		{
			"name": "interior marker forward",
			"marker": interior_marker_pos,
			"from": from_pos,
			"to": to_pos,
		},
		{
			"name": "start marker forward",
			"marker": from_pos,
			"from": from_pos,
			"to": to_pos,
		},
		{
			"name": "start marker reverse",
			"marker": from_pos,
			"from": to_pos,
			"to": from_pos,
		},
		{
			"name": "end marker forward",
			"marker": to_pos,
			"from": from_pos,
			"to": to_pos,
		},
		{
			"name": "end marker reverse",
			"marker": to_pos,
			"from": to_pos,
			"to": from_pos,
		},
	]

	for case_val in cases:
		var check := _assert_overlay_distance_case(s.map, case_val)
		if not check.ok:
			return _finish(check, null, e)

	return _finish(Result.success({}), null, e)

static func _assert_overlay_distance_case(map_data: Dictionary, case_data: Dictionary) -> Result:
	var marker_pos: Vector2i = Vector2i(case_data.get("marker", Vector2i.ZERO))
	map_data["lobbyists_roadworks_markers"] = {
		"%d,%d" % [marker_pos.x, marker_pos.y]: true,
	}

	var overlay := DistanceOverlayClass.new()
	overlay.set_map_data(map_data)
	if overlay._road_graph == null:
		return _finish_overlay_case(Result.failure("DistanceOverlay 未构建 RoadGraph（map_data 缺失关键字段）"), overlay)

	var from_pos: Vector2i = Vector2i(case_data.get("from", Vector2i.ZERO))
	var to_pos: Vector2i = Vector2i(case_data.get("to", Vector2i.ZERO))
	var base := int(overlay._road_graph.get_distance(from_pos, to_pos))
	if base < 0:
		return _finish_overlay_case(Result.failure("%s: 测试期望道路可达（get_distance 返回 -1）" % str(case_data.get("name", ""))), overlay)

	overlay.show_distances(from_pos, [to_pos])
	if overlay._paths.is_empty():
		return _finish_overlay_case(Result.failure("%s: DistanceOverlay 未生成路径数据（_paths 为空）" % str(case_data.get("name", ""))), overlay)

	var d_val = overlay._paths[0].get("distance", null)
	if not (d_val is int):
		return _finish_overlay_case(Result.failure("%s: DistanceOverlay 距离类型错误（期望 int）: %s" % [str(case_data.get("name", "")), str(d_val)]), overlay)
	var d: int = int(d_val)
	if d != base + 1:
		return _finish_overlay_case(Result.failure("%s: DistanceOverlay 应包含 roadworks 惩罚：base=%d expected=%d actual=%d" % [str(case_data.get("name", "")), base, base + 1, d]), overlay)

	return _finish_overlay_case(Result.success({}), overlay)

static func _finish_overlay_case(result: Result, overlay) -> Result:
	_safe_free(overlay)
	return result

static func _finish(result: Result, overlay, engine) -> Result:
	_safe_free(overlay)
	_safe_dispose_engine(engine)
	return result

static func _pick_connected_road_path(state: GameState, road_graph) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("state.map.cells 缺失或类型错误（期望 Array）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size 缺失或类型错误（期望 Vector2i）")

	var cells: Array = state.map["cells"]
	var grid: Vector2i = state.map["grid_size"]
	var road_cells: Array[Vector2i] = []
	for iy in range(grid.y):
		var row_val = cells[iy]
		if not (row_val is Array):
			continue
		var row: Array = row_val
		for ix in range(grid.x):
			var cell_val = row[ix]
			if not (cell_val is Dictionary):
				continue
			var cell: Dictionary = cell_val
			var segs = cell.get("road_segments", null)
			if segs is Array and not (segs as Array).is_empty():
				road_cells.append(CoordsClass.index_to_world(state, Vector2i(ix, iy)))

	for i in range(road_cells.size()):
		var from_pos: Vector2i = road_cells[i]
		for j in range(i + 1, road_cells.size()):
			var to_pos: Vector2i = road_cells[j]
			var path_r = road_graph.find_shortest_path(from_pos, to_pos)
			if not path_r.ok:
				continue
			if not (path_r.value is Dictionary):
				continue
			var info: Dictionary = path_r.value
			var path_val = info.get("path", null)
			if not (path_val is Array):
				continue
			var path_any: Array = path_val
			var path: Array[Vector2i] = []
			for k in range(path_any.size()):
				var p = path_any[k]
				if not (p is Vector2i):
					path = []
					break
				path.append(p)
			if path.size() >= 3:
				return Result.success(path)

	return Result.failure("未找到可用的道路路径（需要 >=3）")

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

static func _safe_dispose_engine(engine) -> void:
	if engine == null:
		return
	if engine.has_method("dispose"):
		engine.dispose()
