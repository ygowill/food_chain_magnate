# DistanceOverlay roadworks penalty regression test
# Ensures distance tool reflects lobbyists roadworks markers (+1 per marked road cell passed).
class_name DistanceOverlayRoadworksPenaltyTest
extends RefCounted

const DistanceOverlayClass = preload("res://ui/overlays/distance_overlay.gd")
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
	var marker_pos: Vector2i = path[1]

	# 注入一个 roadworks marker（不依赖模块逻辑，直接按 key 写入 map）
	s.map["lobbyists_roadworks_markers"] = {
		"%d,%d" % [marker_pos.x, marker_pos.y]: true,
	}

	var overlay := DistanceOverlayClass.new()
	overlay.set_map_data(s.map)
	if overlay._road_graph == null:
		return _finish(Result.failure("DistanceOverlay 未构建 RoadGraph（map_data 缺失关键字段）"), overlay, e)

	var base := int(overlay._road_graph.get_distance(from_pos, to_pos))
	if base < 0:
		return _finish(Result.failure("测试期望道路可达（get_distance 返回 -1）"), overlay, e)

	overlay.show_distances(from_pos, [to_pos])
	if overlay._paths.is_empty():
		return _finish(Result.failure("DistanceOverlay 未生成路径数据（_paths 为空）"), overlay, e)

	var d_val = overlay._paths[0].get("distance", null)
	if not (d_val is int):
		return _finish(Result.failure("DistanceOverlay 距离类型错误（期望 int）: %s" % str(d_val)), overlay, e)
	var d: int = int(d_val)
	if d != base + 1:
		return _finish(Result.failure("DistanceOverlay 应包含 roadworks 惩罚：base=%d expected=%d actual=%d" % [base, base + 1, d]), overlay, e)

	return _finish(Result.success({}), overlay, e)

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
