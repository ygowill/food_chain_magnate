# 距离覆盖层组件
# 在地图上显示房屋到餐厅的距离路径
class_name DistanceOverlay
extends Control

signal path_selected(house_id: String, restaurant_id: String)

const RoadGraphClass = preload("res://core/map/road_graph.gd")

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO
var _road_graph = null  # RoadGraph 引用
var _map_data: Dictionary = {}

var _paths: Array[Dictionary] = []  # [{house_pos, restaurant_pos, distance, path_points}]
var _path_lines: Array[Line2D] = []
var _distance_labels: Array[Label] = []

var _highlight_house: String = ""
var _highlight_restaurant: String = ""

const PATH_COLOR := Color(0.4, 0.7, 0.9, 0.6)
const PATH_HIGHLIGHT_COLOR := Color(0.5, 0.9, 0.5, 0.8)
const PATH_WIDTH := 3.0
const PATH_HIGHLIGHT_WIDTH := 5.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_rebuild_paths()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
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

	_road_graph = RoadGraphClass.build_from_cells_with_external(cells, grid_size, origin, external_cells, boundary_index)

func show_distances(from_position: Vector2i, to_positions: Array[Vector2i]) -> void:
	clear_all()

	for to_pos in to_positions:
		var path_points: Array[Vector2i] = []
		var distance := _calculate_distance(from_position, to_pos, [])

		if _road_graph != null and _road_graph.has_method("find_shortest_path"):
			var sp = _road_graph.find_shortest_path(from_position, to_pos)
			if sp.ok and (sp.value is Dictionary):
				var spv: Dictionary = sp.value
				distance = int(spv.get("distance", distance))
				var path_val = spv.get("path", null)
				if path_val is Array:
					for p in path_val:
						if p is Vector2i:
							path_points.append(p)

		show_distance(from_position, to_pos, path_points)

	_update_path_styles()

func show_distance(house_pos: Vector2i, restaurant_pos: Vector2i, path_points: Array[Vector2i] = [], house_id: String = "", restaurant_id: String = "") -> void:
	var distance := _calculate_distance(house_pos, restaurant_pos, path_points)

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

		show_distance(house_pos, restaurant_pos, path_points, house_id, restaurant_id)

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

	for line in _path_lines:
		if is_instance_valid(line):
			line.queue_free()
	_path_lines.clear()

	for label in _distance_labels:
		if is_instance_valid(label):
			label.queue_free()
	_distance_labels.clear()

func _calculate_distance(house_pos: Vector2i, restaurant_pos: Vector2i, path_points: Array[Vector2i]) -> int:
	# 使用 RoadGraph 计算
	if _road_graph != null and _road_graph.has_method("get_distance"):
		var d: int = int(_road_graph.get_distance(house_pos, restaurant_pos))
		if d >= 0:
			return d

	if path_points.size() > 1:
		return path_points.size() - 1

	# 备用：曼哈顿距离
	return absi(house_pos.x - restaurant_pos.x) + absi(house_pos.y - restaurant_pos.y)

func _add_path_visual(path_data: Dictionary) -> void:
	var house_pos: Vector2i = path_data.house_pos
	var restaurant_pos: Vector2i = path_data.restaurant_pos
	var distance: int = path_data.distance
	var path_points: Array[Vector2i] = []
	for p in Array(path_data.get("path_points", [])):
		path_points.append(p as Vector2i)

	# 创建路径线
	var line := Line2D.new()
	line.width = PATH_WIDTH
	line.default_color = PATH_COLOR
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND

	if path_points.size() > 0:
		for point in path_points:
			var pixel_pos := _grid_to_pixel(point)
			line.add_point(pixel_pos)
	else:
		line.add_point(_grid_to_pixel(house_pos))
		line.add_point(_grid_to_pixel(restaurant_pos))

	add_child(line)
	_path_lines.append(line)

	# 创建距离标签
	var mid_point := (_grid_to_pixel(house_pos) + _grid_to_pixel(restaurant_pos)) / 2

	var label := Label.new()
	label.text = str(distance)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = mid_point - Vector2(10, 10)
	add_child(label)
	_distance_labels.append(label)

func _grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset + _tile_size / 2

func _rebuild_paths() -> void:
	var paths_copy := _paths.duplicate(true)
	clear_all()
	_paths = paths_copy

	for path_data in _paths:
		_add_path_visual(path_data)

func _update_path_styles() -> void:
	var highlight_house_pos := _get_house_pos_for_highlight()
	var highlight_restaurant_pos := _get_restaurant_pos_for_highlight()

	for i in range(_path_lines.size()):
		var line: Line2D = _path_lines[i]
		if not is_instance_valid(line):
			continue

		var is_highlighted := false
		if i < _paths.size():
			var path_data: Dictionary = _paths[i]
			var house_id: String = str(path_data.get("house_id", ""))
			var restaurant_id: String = str(path_data.get("restaurant_id", ""))
			var house_pos: Vector2i = path_data.get("house_pos", Vector2i(-1, -1))
			var restaurant_pos: Vector2i = path_data.get("restaurant_pos", Vector2i(-1, -1))

			if not _highlight_house.is_empty() and not _highlight_restaurant.is_empty():
				if not house_id.is_empty() or not restaurant_id.is_empty():
					is_highlighted = (house_id == _highlight_house and restaurant_id == _highlight_restaurant)
				elif highlight_house_pos != Vector2i(-1, -1) and highlight_restaurant_pos != Vector2i(-1, -1):
					is_highlighted = (house_pos == highlight_house_pos and restaurant_pos == highlight_restaurant_pos)
			elif not _highlight_house.is_empty():
				if not house_id.is_empty():
					is_highlighted = (house_id == _highlight_house)
				elif highlight_house_pos != Vector2i(-1, -1):
					is_highlighted = (house_pos == highlight_house_pos)
			elif not _highlight_restaurant.is_empty():
				if not restaurant_id.is_empty():
					is_highlighted = (restaurant_id == _highlight_restaurant)
				elif highlight_restaurant_pos != Vector2i(-1, -1):
					is_highlighted = (restaurant_pos == highlight_restaurant_pos)

		if is_highlighted:
			line.width = PATH_HIGHLIGHT_WIDTH
			line.default_color = PATH_HIGHLIGHT_COLOR
		else:
			line.width = PATH_WIDTH
			line.default_color = PATH_COLOR

		if i < _distance_labels.size():
			var label: Label = _distance_labels[i]
			if is_instance_valid(label):
				label.add_theme_font_size_override("font_size", 16 if is_highlighted else 14)
				label.add_theme_color_override("font_color", Color(0.6, 1, 0.6, 1) if is_highlighted else Color(1, 1, 1, 1))

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
