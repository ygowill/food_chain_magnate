# 距离覆盖层组件
# 在地图上显示房屋到餐厅的距离路径
class_name DistanceOverlay
extends BaseTileOverlay

signal path_selected(house_id: String, restaurant_id: String)

const RoadGraphClass = preload("res://core/map/road_graph.gd")
const MapOverlayProviderRegistryClass = preload("res://core/rules/map_overlay_provider_registry.gd")
const DISTANCE_OVERRIDE_NONE := -999999999
var _road_graph = null  # RoadGraph 引用
var _map_data: Dictionary = {}

var _paths: Array[Dictionary] = []  # [{house_pos, restaurant_pos, distance, path_points}]
var _distance_label_panels: Array[PanelContainer] = []
var _distance_labels: Array[Label] = []

var _highlight_house: String = ""
var _highlight_restaurant: String = ""

const PATH_COLOR := Color(0.4, 0.7, 0.9, 0.3)
const PATH_HIGHLIGHT_COLOR := Color(0.5, 0.9, 0.5, 0.42)
const PATH_UNREACHABLE_COLOR := Color(0.9, 0.35, 0.35, 0.3)
const LABEL_UNREACHABLE_COLOR := Color(1, 0.55, 0.55, 1)
const PATH_CELL_INSET_PX := 2.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_layout_changed() -> void:
	_rebuild_paths()

func set_road_graph(graph) -> void:
	_road_graph = graph

func set_map_data(map_data: Dictionary) -> void:
	_map_data = map_data.duplicate(true)
	_road_graph = null

	if _map_data.is_empty():
		return

	var cells_val = _map_data.get("cells", null)
	var grid_size_val = _map_data.get("grid_size", null)
	var boundary_index_val = _map_data.get("boundary_index", null)
	if not (cells_val is Array) or not (grid_size_val is Vector2i) or not (boundary_index_val is Dictionary):
		return

	var cells: Array = cells_val
	var grid_size: Vector2i = grid_size_val
	var boundary_index: Dictionary = boundary_index_val

	var origin := Vector2i.ZERO
	var origin_val = _map_data.get("map_origin", Vector2i.ZERO)
	if origin_val is Vector2i:
		origin = origin_val

	var external_cells: Dictionary = {}
	var ext_val = _map_data.get("external_cells", null)
	if ext_val is Dictionary:
		external_cells = ext_val

	var options: Dictionary = {}
	var connect_parallel := false
	var cpl_val = _map_data.get("road_graph_connect_parallel_lanes", null)
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

	_road_graph = RoadGraphClass.build_from_cells_with_external(cells, grid_size, origin, external_cells, boundary_index, options)

func show_distances(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	clear_all()

	for to_pos in to_positions:
		var path_points: Array[Vector2i] = []
		var distance := -1

		if _road_graph != null and _road_graph.has_method("find_shortest_path"):
			var sp = _road_graph.find_shortest_path(from_position, to_pos)
			if sp.ok and (sp.value is Dictionary):
				var spv: Dictionary = sp.value
				distance = int(spv.get("distance", -1))
				var path_val = spv.get("path", null)
				if path_val is Array:
					for p in path_val:
						if p is Vector2i:
							path_points.append(p)

		if distance >= 0 and path_points.size() > 1:
			distance += _count_roadworks_penalty(path_points)

		show_distance(from_position, to_pos, path_points, "", "", distance)

	_update_path_styles()

func show_distance(
	house_pos: Vector2i,
	restaurant_pos: Vector2i,
	path_points: Array[Vector2i] = [],
	house_id: String = "",
	restaurant_id: String = "",
	distance_override: int = DISTANCE_OVERRIDE_NONE
) -> void:
	var distance := distance_override
	if distance_override == DISTANCE_OVERRIDE_NONE:
		distance = _calculate_distance(house_pos, restaurant_pos, path_points)

	var path_data: Dictionary = {
		"house_pos": house_pos,
		"restaurant_pos": restaurant_pos,
		"distance": distance,
		"path_points": path_points,
		"house_id": house_id,
		"restaurant_id": restaurant_id,
	}

	_paths.append(path_data)
	_add_path_visual(path_data)

func show_all_distances(house_restaurant_pairs: Array[Dictionary]) -> void:
	clear_all()

	for pair in house_restaurant_pairs:
		var house_id: String = str(pair.get("house_id", ""))
		var restaurant_id: String = str(pair.get("restaurant_id", ""))
		var house_pos: Vector2i = pair.get("house_pos", Vector2i.ZERO)
		var restaurant_pos: Vector2i = pair.get("restaurant_pos", Vector2i.ZERO)
		var path_points: Array[Vector2i] = []
		for p in Array(pair.get("path_points", [])):
			path_points.append(p as Vector2i)

		var distance_override := DISTANCE_OVERRIDE_NONE
		var dist_val = pair.get("distance", null)
		if dist_val is int or dist_val is float:
			distance_override = int(dist_val)

		show_distance(house_pos, restaurant_pos, path_points, house_id, restaurant_id, distance_override)

	_update_path_styles()

func highlight_path(house_id: String, restaurant_id: String) -> void:
	_highlight_house = house_id
	_highlight_restaurant = restaurant_id
	_update_path_styles()

func clear_highlight() -> void:
	_highlight_house = ""
	_highlight_restaurant = ""
	_update_path_styles()

func clear_all() -> void:
	_paths.clear()
	_free_nodes(_distance_label_panels)
	_free_nodes(_distance_labels)
	queue_redraw()

func _calculate_distance(house_pos: Vector2i, restaurant_pos: Vector2i, path_points: Array[Vector2i]) -> int:
	# 使用 RoadGraph 计算
	if _road_graph != null and _road_graph.has_method("get_distance"):
		var base := int(_road_graph.get_distance(house_pos, restaurant_pos))
		if base >= 0 and path_points.size() > 1:
			base += _count_roadworks_penalty(path_points)
		return base

	if path_points.size() > 1:
		return path_points.size() - 1

	# 距离工具：不做“曼哈顿兜底”，避免给出误导性结果；无法连接时返回 -1。
	return -1

func _count_roadworks_penalty(path_points: Array[Vector2i]) -> int:
	var marker_positions: Array[Vector2i] = MapOverlayProviderRegistryClass.get_roadworks_marker_world_positions(_map_data)
	if marker_positions.is_empty():
		return 0
	var marker_set := {}
	for p in marker_positions:
		if p is Vector2i:
			marker_set[p] = true
	var penalty := 0
	for i in range(1, path_points.size()):
		var p: Vector2i = path_points[i]
		if marker_set.has(p):
			penalty += 1
	return penalty

func _add_path_visual(path_data: Dictionary) -> void:
	var restaurant_pos: Vector2i = path_data.restaurant_pos
	var distance: int = path_data.distance

	# 创建距离标签（显示在终点上方，且增加背景以便阅读：issue_tracker #59）。
	var label_panel := PanelContainer.new()
	label_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.7)
	bg.border_color = Color(1, 1, 1, 0.2)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	label_panel.add_theme_stylebox_override("panel", bg)
	add_child(label_panel)
	_distance_label_panels.append(label_panel)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if distance < 0:
		label.text = "无法连接"
		label.add_theme_color_override("font_color", LABEL_UNREACHABLE_COLOR)
	else:
		label.text = str(distance)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_panel.add_child(label)

	var pad_x := 8
	var pad_y := 6
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = pad_x
	label.offset_top = pad_y
	label.offset_right = -pad_x
	label.offset_bottom = -pad_y

	var panel_size := label.get_minimum_size() + Vector2(float(pad_x * 2), float(pad_y * 2))
	label_panel.size = panel_size
	label_panel.custom_minimum_size = panel_size

	# 终点上方：以格子中心点为锚，向上偏移半格。
	var end_center := _grid_to_pixel_center(restaurant_pos)
	var target := end_center + Vector2(0, -_tile_size.y * 0.95)
	label_panel.position = target - (panel_size * 0.5)
	_distance_labels.append(label)

func _rebuild_paths() -> void:
	var paths_copy := _paths.duplicate(true)
	clear_all()
	_paths = paths_copy

	for path_data in _paths:
		_add_path_visual(path_data)

	_update_path_styles()

func _draw() -> void:
	if _paths.is_empty():
		return

	var highlight_house_pos := _get_house_pos_for_highlight()
	var highlight_restaurant_pos := _get_restaurant_pos_for_highlight()

	# 先绘制未高亮路径，再绘制高亮路径，确保高亮视觉覆盖在上层。
	for path_data in _paths:
		if _is_path_highlighted(path_data, highlight_house_pos, highlight_restaurant_pos):
			continue
		_draw_path_cells(path_data, false)

	for path_data2 in _paths:
		if not _is_path_highlighted(path_data2, highlight_house_pos, highlight_restaurant_pos):
			continue
		_draw_path_cells(path_data2, true)

func _draw_path_cells(path_data: Dictionary, is_highlighted: bool) -> void:
	var d_val = path_data.get("distance", null)
	var is_unreachable := false
	if d_val is int:
		is_unreachable = int(d_val) < 0
	elif d_val is float:
		var f: float = float(d_val)
		if f == floor(f):
			is_unreachable = int(f) < 0

	var fill := PATH_HIGHLIGHT_COLOR if is_highlighted else (PATH_UNREACHABLE_COLOR if is_unreachable else PATH_COLOR)

	var cells := _get_path_cells_for_draw(path_data)
	_draw_cell_fills(cells, fill, PATH_CELL_INSET_PX)

func _get_path_cells_for_draw(path_data: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	var points_val = path_data.get("path_points", null)
	if points_val is Array:
		for p in (points_val as Array):
			if p is Vector2i:
				out.append(p)
	if not out.is_empty():
		return out

	var house_val = path_data.get("house_pos", null)
	if house_val is Vector2i:
		out.append(Vector2i(house_val))

	var rest_val = path_data.get("restaurant_pos", null)
	if rest_val is Vector2i:
		var rp := Vector2i(rest_val)
		if out.is_empty() or out[out.size() - 1] != rp:
			out.append(rp)

	return out

func _update_path_styles() -> void:
	var highlight_house_pos := _get_house_pos_for_highlight()
	var highlight_restaurant_pos := _get_restaurant_pos_for_highlight()

	for i in range(_paths.size()):
		var is_unreachable := false
		var is_highlighted := false
		var path_data: Dictionary = _paths[i]
		var d_val = path_data.get("distance", null)
		if d_val is int:
			is_unreachable = int(d_val) < 0
		elif d_val is float:
			var f: float = float(d_val)
			if f == floor(f):
				is_unreachable = int(f) < 0
		is_highlighted = _is_path_highlighted(path_data, highlight_house_pos, highlight_restaurant_pos)

		if i < _distance_labels.size():
			var label: Label = _distance_labels[i]
			if is_instance_valid(label):
				label.add_theme_font_size_override("font_size", 22 if is_highlighted else 18)
				if is_highlighted:
					label.add_theme_color_override("font_color", Color(0.6, 1, 0.6, 1))
				else:
					label.add_theme_color_override("font_color", LABEL_UNREACHABLE_COLOR if is_unreachable else Color(1, 1, 1, 1))

				# 重新计算面板尺寸/位置，避免高亮时字号变化导致裁剪。
				if i < _distance_label_panels.size():
					var panel: PanelContainer = _distance_label_panels[i]
					if is_instance_valid(panel):
						var pad_x := 8
						var pad_y := 6
						var panel_size := label.get_minimum_size() + Vector2(float(pad_x * 2), float(pad_y * 2))
						panel.size = panel_size
						panel.custom_minimum_size = panel_size

						var rp_val = _paths[i].get("restaurant_pos", null) if i < _paths.size() else null
						if rp_val is Vector2i:
							var end_center := _grid_to_pixel_center(Vector2i(rp_val))
							var target := end_center + Vector2(0, -_tile_size.y * 0.95)
							panel.position = target - (panel_size * 0.5)

	queue_redraw()

func _is_path_highlighted(path_data: Dictionary, highlight_house_pos: Vector2i, highlight_restaurant_pos: Vector2i) -> bool:
	var house_id: String = str(path_data.get("house_id", ""))
	var restaurant_id: String = str(path_data.get("restaurant_id", ""))
	var house_pos: Vector2i = path_data.get("house_pos", Vector2i(-1, -1))
	var restaurant_pos: Vector2i = path_data.get("restaurant_pos", Vector2i(-1, -1))

	# 兼容：若 path_data 没有 house_id/restaurant_id，则回落到坐标匹配（仅在两个 id 都为空时）
	if not _highlight_house.is_empty() and not _highlight_restaurant.is_empty():
		if not house_id.is_empty() or not restaurant_id.is_empty():
			return house_id == _highlight_house and restaurant_id == _highlight_restaurant
		return (
			highlight_house_pos != Vector2i(-1, -1)
			and highlight_restaurant_pos != Vector2i(-1, -1)
			and house_pos == highlight_house_pos
			and restaurant_pos == highlight_restaurant_pos
		)

	if not _highlight_house.is_empty():
		if not house_id.is_empty():
			return house_id == _highlight_house
		return highlight_house_pos != Vector2i(-1, -1) and house_pos == highlight_house_pos

	if not _highlight_restaurant.is_empty():
		if not restaurant_id.is_empty():
			return restaurant_id == _highlight_restaurant
		return highlight_restaurant_pos != Vector2i(-1, -1) and restaurant_pos == highlight_restaurant_pos

	return false

func _get_house_pos_for_highlight() -> Vector2i:
	if _highlight_house.is_empty():
		return Vector2i(-1, -1)
	if _map_data.is_empty():
		return Vector2i(-1, -1)
	var houses_val = _map_data.get("houses", null)
	if not (houses_val is Dictionary):
		return Vector2i(-1, -1)
	var house_val = (houses_val as Dictionary).get(_highlight_house, null)
	if not (house_val is Dictionary):
		return Vector2i(-1, -1)
	var anchor_val = (house_val as Dictionary).get("anchor_pos", null)
	if anchor_val is Vector2i:
		return anchor_val
	var cells_val = (house_val as Dictionary).get("cells", null)
	if cells_val is Array and not (cells_val as Array).is_empty():
		var first = (cells_val as Array)[0]
		if first is Vector2i:
			return first
	return Vector2i(-1, -1)

func _get_restaurant_pos_for_highlight() -> Vector2i:
	if _highlight_restaurant.is_empty():
		return Vector2i(-1, -1)
	if _map_data.is_empty():
		return Vector2i(-1, -1)
	var restaurants_val = _map_data.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Vector2i(-1, -1)
	var rest_val = (restaurants_val as Dictionary).get(_highlight_restaurant, null)
	if not (rest_val is Dictionary):
		return Vector2i(-1, -1)
	var entrance_val = (rest_val as Dictionary).get("entrance_pos", null)
	if entrance_val is Vector2i:
		return entrance_val
	var anchor_val = (rest_val as Dictionary).get("anchor_pos", null)
	if anchor_val is Vector2i:
		return anchor_val
	var cells_val = (rest_val as Dictionary).get("cells", null)
	if cells_val is Array and not (cells_val as Array).is_empty():
		var first = (cells_val as Array)[0]
		if first is Vector2i:
			return first
	return Vector2i(-1, -1)
