# GameMapInteractionController：距离工具（道路↔道路 / 房屋+餐厅）
extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const RoadGraphClass = preload("res://core/map/road_graph.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

const _POINTS_OVERLAY_ID := "distance_tool_points"

var _owner_ref: WeakRef
var _map_canvas = null
var _overlay_controller = null
var _from_pick: Dictionary = {} # {kind: road|house|restaurant, id: String, pos: Vector2i, cells: Array[Vector2i]}

func _init(owner, map_canvas, overlay_controller) -> void:
	_owner_ref = weakref(owner)
	_map_canvas = map_canvas
	_overlay_controller = overlay_controller

func dispose() -> void:
	on_mode_cleared()
	_owner_ref = null
	_map_canvas = null
	_overlay_controller = null

func _get_owner():
	if _owner_ref == null:
		return null
	return _owner_ref.get_ref()

func toggle_distance_tool() -> void:
	var owner = _get_owner()
	if owner == null:
		return

	if str(owner._mode) == "distance_tool":
		if owner.has_method("resume_suspended_mode_from_distance_tool"):
			var resumed_val = owner.call("resume_suspended_mode_from_distance_tool")
			if resumed_val is bool and bool(resumed_val):
				GameLog.info("Game", "距离工具已关闭，已返回放置模式")
				return
		owner.clear_selection()
		GameLog.info("Game", "距离工具已关闭")
		return

	if str(owner._mode) == "restaurant_placement":
		if owner.has_method("suspend_current_mode_for_distance_tool"):
			var suspended_val = owner.call("suspend_current_mode_for_distance_tool")
			if suspended_val is bool and bool(suspended_val):
				_from_pick.clear()
				if _overlay_controller != null and _overlay_controller.has_method("hide_distance_overlay"):
					_overlay_controller.hide_distance_overlay()
				GameLog.info("Game", "距离工具已启用：支持道路到道路，或房屋到餐厅")
				return

	if not str(owner._mode).is_empty():
		GameLog.warn("Game", "当前正在 %s 选点模式，无法启用距离工具" % str(owner._mode))
		return

	owner.begin_selection("distance_tool")
	_from_pick.clear()
	if _overlay_controller != null and _overlay_controller.has_method("hide_distance_overlay"):
		_overlay_controller.hide_distance_overlay()
	GameLog.info("Game", "距离工具已启用：支持道路到道路，或房屋到餐厅")

func on_mode_cleared() -> void:
	_from_pick.clear()
	if _overlay_controller != null and _overlay_controller.has_method("hide_distance_overlay"):
		_overlay_controller.hide_distance_overlay()
	_clear_points_highlight()

func clear_points_overlay() -> void:
	_clear_points_highlight()

func on_cell_selected(world_pos: Vector2i) -> void:
	if _overlay_controller == null:
		return

	var owner = _get_owner()
	if owner == null:
		return
	if owner._scene == null or owner._scene.game_engine == null:
		return
	var state: GameState = owner._scene.game_engine.get_state()
	if state == null:
		return

	var pick := _resolve_pick(state, world_pos)
	if pick.is_empty():
		return

	if _from_pick.is_empty():
		_from_pick = pick.duplicate(true)
		if _overlay_controller.has_method("hide_distance_overlay"):
			_overlay_controller.hide_distance_overlay()
		_show_points_highlight(_pick_to_cells(pick))
		GameLog.info("Game", "距离工具：起点=%s，请选择终点" % _get_pick_label(pick))
		return

	if _is_same_pick(_from_pick, pick):
		_from_pick.clear()
		if _overlay_controller.has_method("hide_distance_overlay"):
			_overlay_controller.hide_distance_overlay()
		_clear_points_highlight()
		GameLog.info("Game", "距离工具：已清除起点，请重新选择起点")
		return

	var measure_read := _measure_distance_between_picks(state, _from_pick, pick)
	if not measure_read.ok:
		# 非法组合时，将当前点击目标作为新的起点。
		_from_pick = pick.duplicate(true)
		if _overlay_controller.has_method("hide_distance_overlay"):
			_overlay_controller.hide_distance_overlay()
		_show_points_highlight(_pick_to_cells(pick))
		GameLog.info("Game", "%s；已切换起点=%s" % [measure_read.error, _get_pick_label(pick)])
		return

	var measured: Dictionary = measure_read.value
	var measured_kind := str(measured.get("kind", "")).strip_edges()
	if measured_kind == "road_pair":
		var from_pos_val = measured.get("from_position", null)
		var to_pos_val = measured.get("to_position", null)
		if from_pos_val is Vector2i and to_pos_val is Vector2i and _overlay_controller.has_method("show_distance_overlay"):
			var to_positions: Array[Vector2i] = [Vector2i(to_pos_val)]
			_overlay_controller.show_distance_overlay(Vector2i(from_pos_val), to_positions)
	elif measured_kind == "house_restaurant_pair":
		if _overlay_controller.has_method("show_distance_overlay_pair"):
			var house_pos_val = measured.get("house_position", null)
			var restaurant_pos_val = measured.get("restaurant_position", null)
			var path_val = measured.get("path_points", null)
			var distance_val = measured.get("distance", -1)
			if house_pos_val is Vector2i and restaurant_pos_val is Vector2i and path_val is Array:
				var path_points: Array[Vector2i] = []
				for p in Array(path_val):
					if p is Vector2i:
						path_points.append(Vector2i(p))
				_overlay_controller.show_distance_overlay_pair(
					Vector2i(house_pos_val),
					Vector2i(restaurant_pos_val),
					path_points,
					int(distance_val)
				)

	var hl_val = measured.get("highlight_cells", null)
	if hl_val is Array:
		var hl: Array[Vector2i] = []
		for c in Array(hl_val):
			if c is Vector2i:
				hl.append(Vector2i(c))
		_show_points_highlight(hl)
	_from_pick.clear()

func _show_points_highlight(cells_in: Array[Vector2i]) -> void:
	if not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("set_piece_overlay"):
		return
	# NOTE: set_piece_overlay expects Array[Vector2i]; passing an untyped Array via call() will error.
	var cells: Array[Vector2i] = []
	for v in cells_in:
		cells.append(v)
	if cells.is_empty():
		return
	_map_canvas.call("set_piece_overlay", _POINTS_OVERLAY_ID, cells, {
		"fill": Color(1, 0.9, 0.15, 0.2),
		"border": Color(1, 0.9, 0.15, 0.95),
		"border_width": 3.0,
	})

func _clear_points_highlight() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", _POINTS_OVERLAY_ID)

func _resolve_pick(state: GameState, world_pos: Vector2i) -> Dictionary:
	var house_pick := _find_house_at(state, world_pos)
	if not house_pick.is_empty():
		return house_pick

	var restaurant_pick := _find_restaurant_at(state, world_pos)
	if not restaurant_pick.is_empty():
		return restaurant_pick

	if CellsClass.has_road_at_any(state, world_pos):
		var road_cells: Array[Vector2i] = [world_pos]
		return {
			"kind": "road",
			"id": "",
			"pos": world_pos,
			"cells": road_cells,
		}
	return {}

func _is_same_pick(a: Dictionary, b: Dictionary) -> bool:
	var ka := str(a.get("kind", "")).strip_edges()
	var kb := str(b.get("kind", "")).strip_edges()
	if ka != kb:
		return false

	if ka == "road":
		var pa = a.get("pos", null)
		var pb = b.get("pos", null)
		return (pa is Vector2i) and (pb is Vector2i) and Vector2i(pa) == Vector2i(pb)

	var ida := str(a.get("id", "")).strip_edges()
	var idb := str(b.get("id", "")).strip_edges()
	if not ida.is_empty() and not idb.is_empty():
		return ida == idb
	return false

func _pick_to_cells(pick: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells_val = pick.get("cells", null)
	if cells_val is Array:
		for c in Array(cells_val):
			if c is Vector2i:
				var p := Vector2i(c)
				if not out.has(p):
					out.append(p)
	if out.is_empty():
		var pos_val = pick.get("pos", null)
		if pos_val is Vector2i:
			out.append(Vector2i(pos_val))
	return out

func _get_pick_label(pick: Dictionary) -> String:
	var kind := str(pick.get("kind", "")).strip_edges()
	var id := str(pick.get("id", "")).strip_edges()
	var pos_val = pick.get("pos", null)
	var pos := Vector2i(pos_val) if pos_val is Vector2i else Vector2i(-1, -1)
	match kind:
		"road":
			return "道路%s" % str(pos)
		"house":
			var display_number := str(pick.get("display_number", "")).strip_edges()
			if display_number.is_empty():
				display_number = HouseNumberManagerClass.format_display_label(null, id, "")
			return "房屋%s" % (" #%s" % display_number if not display_number.is_empty() else "")
		"restaurant":
			return "餐厅%s" % (" %s" % id if not id.is_empty() else "")
		_:
			return str(pos)

func _find_house_at(state: GameState, world_pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var houses_val = state.map.get("houses", null)
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	for hid_val in houses.keys():
		if not (hid_val is String):
			continue
		var hid := str(hid_val).strip_edges()
		if hid.is_empty():
			continue
		var house_val = houses.get(hid_val, null)
		if not (house_val is Dictionary):
			continue
		var house: Dictionary = house_val
		var cells := _extract_cells_from_structure(house)
		if not cells.has(world_pos):
			continue
		return {
			"kind": "house",
			"id": hid,
			"display_number": HouseNumberManagerClass.format_display_label(house.get("house_number", null), hid, ""),
			"pos": world_pos,
			"cells": cells,
			"structure": house.duplicate(true),
		}
	return {}

func _find_restaurant_at(state: GameState, world_pos: Vector2i) -> Dictionary:
	if state == null or not (state.map is Dictionary):
		return {}
	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return {}
	var restaurants: Dictionary = restaurants_val
	for rid_val in restaurants.keys():
		if not (rid_val is String):
			continue
		var rid := str(rid_val).strip_edges()
		if rid.is_empty():
			continue
		var rest_val = restaurants.get(rid_val, null)
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var cells := _extract_cells_from_structure(rest)
		if not cells.has(world_pos):
			continue
		return {
			"kind": "restaurant",
			"id": rid,
			"pos": world_pos,
			"cells": cells,
			"structure": rest.duplicate(true),
		}
	return {}

func _extract_cells_from_structure(structure: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells_val = structure.get("cells", null)
	if cells_val is Array:
		for p in Array(cells_val):
			if p is Vector2i:
				var pv := Vector2i(p)
				if not out.has(pv):
					out.append(pv)
			elif p is Array:
				var a: Array = p
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					var pv2 := Vector2i(int(a[0]), int(a[1]))
					if not out.has(pv2):
						out.append(pv2)
	if out.is_empty():
		var anchor_val = structure.get("anchor_pos", null)
		if anchor_val is Vector2i:
			out.append(Vector2i(anchor_val))
	return out

func _measure_distance_between_picks(state: GameState, from_pick: Dictionary, to_pick: Dictionary) -> Result:
	var from_kind := str(from_pick.get("kind", "")).strip_edges()
	var to_kind := str(to_pick.get("kind", "")).strip_edges()

	if from_kind == "road" and to_kind == "road":
		var from_pos_val = from_pick.get("pos", null)
		var to_pos_val = to_pick.get("pos", null)
		if not (from_pos_val is Vector2i) or not (to_pos_val is Vector2i):
			return Result.failure("距离工具：道路坐标无效")
		var highlight_cells: Array[Vector2i] = [Vector2i(from_pos_val), Vector2i(to_pos_val)]
		return Result.success({
			"kind": "road_pair",
			"from_position": Vector2i(from_pos_val),
			"to_position": Vector2i(to_pos_val),
			"highlight_cells": highlight_cells,
		})

	var house_pick: Dictionary = {}
	var restaurant_pick: Dictionary = {}
	if from_kind == "house" and to_kind == "restaurant":
		house_pick = from_pick
		restaurant_pick = to_pick
	elif from_kind == "restaurant" and to_kind == "house":
		house_pick = to_pick
		restaurant_pick = from_pick
	else:
		return Result.failure("距离工具：请选择两条道路格，或一间房屋+一间餐厅")

	var house_id := str(house_pick.get("id", "")).strip_edges()
	var restaurant_id := str(restaurant_pick.get("id", "")).strip_edges()
	if house_id.is_empty() or restaurant_id.is_empty():
		return Result.failure("距离工具：房屋或餐厅信息无效")

	var house_val = house_pick.get("structure", null)
	var rest_val = restaurant_pick.get("structure", null)
	if not (house_val is Dictionary) or not (rest_val is Dictionary):
		return Result.failure("距离工具：房屋或餐厅数据缺失")
	var house: Dictionary = house_val
	var rest: Dictionary = rest_val

	var hr_read := _measure_house_to_restaurant_distance(state, house_id, house, restaurant_id, rest)
	if not hr_read.ok:
		return hr_read
	var hr: Dictionary = hr_read.value

	var highlight_cells := _pick_to_cells(house_pick)
	for c in _pick_to_cells(restaurant_pick):
		if not highlight_cells.has(c):
			highlight_cells.append(c)

	var house_pos_val = house_pick.get("pos", null)
	var restaurant_pos_val = restaurant_pick.get("pos", null)
	if not (house_pos_val is Vector2i):
		house_pos_val = Vector2i.ZERO
	if not (restaurant_pos_val is Vector2i):
		restaurant_pos_val = Vector2i.ZERO

	return Result.success({
		"kind": "house_restaurant_pair",
		"house_position": Vector2i(house_pos_val),
		"restaurant_position": Vector2i(restaurant_pos_val),
		"path_points": Array(hr.get("path_points", [])),
		"distance": int(hr.get("distance", -1)),
		"highlight_cells": highlight_cells,
	})

func _measure_house_to_restaurant_distance(
	state: GameState,
	house_id: String,
	house: Dictionary,
	restaurant_id: String,
	rest: Dictionary
) -> Result:
	var road_graph = _build_road_graph_from_state(state)
	if road_graph == null or not is_instance_valid(road_graph):
		return Result.failure("距离工具：无法构建道路图")

	var house_cells := _extract_cells_from_structure(house)
	if house_cells.is_empty():
		return Result.failure("距离工具：房屋缺少有效占地")
	var house_roads := _get_structure_adjacent_roads(state, house_cells)
	if house_roads.is_empty():
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	var entrance_read := StructuresClass.get_restaurant_entrance_points(state, restaurant_id, rest)
	if not entrance_read.ok:
		return Result.failure("距离工具：%s" % entrance_read.error)
	var entrance_points: Array[Vector2i] = []
	for p in Array(entrance_read.value):
		if p is Vector2i:
			entrance_points.append(Vector2i(p))
	if entrance_points.is_empty():
		return Result.failure("距离工具：餐厅入口无效: %s" % restaurant_id)
	var rest_roads := _get_structure_adjacent_roads(state, entrance_points)
	if rest_roads.is_empty():
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	var rest_entry_cost_by_road := _build_structure_to_road_boundary_cost(entrance_points, rest_roads)
	var house_entry_cost_by_road := _build_structure_to_road_boundary_cost(house_cells, house_roads)

	var best_distance := 2147483647
	var best_steps := 2147483647
	var best_path: Array[Vector2i] = []

	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok or not (sp.value is Dictionary):
				continue
			var sp_val: Dictionary = sp.value
			var base_distance := int(sp_val.get("distance", -1))
			if base_distance < 0:
				continue
			var steps := int(sp_val.get("steps", 2147483647))
			var path_points: Array[Vector2i] = []
			var path_val = sp_val.get("path", null)
			if path_val is Array:
				for p2 in Array(path_val):
					if p2 is Vector2i:
						path_points.append(Vector2i(p2))
			if path_points.is_empty():
				path_points.append(Vector2i(s))
				if Vector2i(t) != Vector2i(s):
					path_points.append(Vector2i(t))

			var d := base_distance
			d += int(rest_entry_cost_by_road.get(s, 0))
			d += int(house_entry_cost_by_road.get(t, 0))
			if d < best_distance or (d == best_distance and steps < best_steps):
				best_distance = d
				best_steps = steps
				best_path = path_points

	if best_distance == 2147483647:
		return Result.success({
			"distance": -1,
			"path_points": [],
		})

	best_distance += _count_roadworks_penalty(state.map, best_path)
	return Result.success({
		"distance": best_distance,
		"path_points": best_path,
	})

func _build_road_graph_from_state(state: GameState):
	if state == null or not (state.map is Dictionary):
		return null
	var map_data: Dictionary = state.map
	var cells_val = map_data.get("cells", null)
	var grid_size_val = map_data.get("grid_size", null)
	var boundary_index_val = map_data.get("boundary_index", null)
	if not (cells_val is Array) or not (grid_size_val is Vector2i) or not (boundary_index_val is Dictionary):
		return null

	var origin := Vector2i.ZERO
	var origin_val = map_data.get("map_origin", Vector2i.ZERO)
	if origin_val is Vector2i:
		origin = origin_val

	var external_cells: Dictionary = {}
	var ext_val = map_data.get("external_cells", null)
	if ext_val is Dictionary:
		external_cells = ext_val

	var options: Dictionary = {}
	var connect_parallel := false
	var cpl_val = map_data.get("road_graph_connect_parallel_lanes", null)
	if cpl_val is bool:
		connect_parallel = bool(cpl_val)
	elif cpl_val is int:
		connect_parallel = int(cpl_val) != 0
	elif cpl_val is float:
		var f: float = float(cpl_val)
		if f == floor(f):
			connect_parallel = int(f) != 0
	if connect_parallel:
		options["connect_parallel_lanes"] = true

	return RoadGraphClass.build_from_cells_with_external(
		cells_val,
		Vector2i(grid_size_val),
		origin,
		external_cells,
		boundary_index_val,
		options
	)

func _get_structure_adjacent_roads(state: GameState, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		if CellsClass.has_cell_any(state, cell) and CellsClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtilsClass.DIRECTIONS:
			var n := MapUtilsClass.get_neighbor_pos(cell, dir)
			if not CellsClass.has_cell_any(state, n):
				continue
			if CellsClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(Vector2i(k))
	return result

func _build_structure_to_road_boundary_cost(
	structure_cells: Array[Vector2i],
	road_cells: Array[Vector2i]
) -> Dictionary:
	var out := {}
	for r in road_cells:
		var best := 2147483647
		for c in structure_cells:
			if c == r:
				best = 0
				break
			if not MapUtilsClass.are_adjacent(c, r):
				continue
			best = min(best, 1 if MapUtilsClass.crosses_tile_boundary(c, r) else 0)
		if best == 2147483647:
			best = 0
		out[r] = int(best)
	return out

func _count_roadworks_penalty(map_data: Dictionary, path_points: Array[Vector2i]) -> int:
	if map_data == null or map_data.is_empty() or path_points.is_empty():
		return 0
	var marker_positions: Array[Vector2i] = MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions(map_data)
	if marker_positions.is_empty():
		return 0
	var marker_set := {}
	for p in marker_positions:
		if p is Vector2i:
			marker_set[p] = true
	var penalty := 0
	for i in range(1, path_points.size()):
		var p2: Vector2i = path_points[i]
		if marker_set.has(p2):
			penalty += 1
	return penalty
