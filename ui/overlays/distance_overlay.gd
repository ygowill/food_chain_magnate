# 距离覆盖层组件
# 在地图上显示房屋到餐厅的距离路径
class_name DistanceOverlay
extends Control

signal path_selected(house_id: String, restaurant_id: String)

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO
var _road_graph = null  # RoadGraph 引用

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

func show_distance(house_pos: Vector2i, restaurant_pos: Vector2i, path_points: Array[Vector2i] = []) -> void:
	var distance := _calculate_distance(house_pos, restaurant_pos, path_points)

	var path_data: Dictionary = {
		"house_pos": house_pos,
		"restaurant_pos": restaurant_pos,
		"distance": distance,
		"path_points": path_points,
	}

	_paths.append(path_data)
	_add_path_visual(path_data)

func show_all_distances(house_restaurant_pairs: Array[Dictionary]) -> void:
	clear_all()

	for pair in house_restaurant_pairs:
		var house_pos: Vector2i = pair.get("house_pos", Vector2i.ZERO)
		var restaurant_pos: Vector2i = pair.get("restaurant_pos", Vector2i.ZERO)
		var path_points: Array[Vector2i] = []
		for p in Array(pair.get("path_points", [])):
			path_points.append(p as Vector2i)

		show_distance(house_pos, restaurant_pos, path_points)

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
	if path_points.size() > 1:
		return path_points.size() - 1

	# 使用 RoadGraph 计算
	if _road_graph != null and _road_graph.has_method("get_distance"):
		return _road_graph.get_distance(house_pos, restaurant_pos)

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
	for i in range(_path_lines.size()):
		var line: Line2D = _path_lines[i]
		if not is_instance_valid(line):
			continue

		# TODO: 根据 house_id 和 restaurant_id 判断是否高亮
		# 目前简化处理，使用索引
		var is_highlighted := false

		if is_highlighted:
			line.width = PATH_HIGHLIGHT_WIDTH
			line.default_color = PATH_HIGHLIGHT_COLOR
		else:
			line.width = PATH_WIDTH
			line.default_color = PATH_COLOR
