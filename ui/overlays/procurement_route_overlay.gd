# 采购路线覆盖层组件
# 在地图上显示饮料采购的自动规划路线（仅可视化，不改变规则）。
class_name ProcurementRouteOverlay
extends Control

const ROUTE_COLOR := Color(0.35, 0.8, 1.0, 0.8)
const ROUTE_WIDTH := 4.0

const START_COLOR := Color(0.35, 0.9, 0.55, 0.95)
const SOURCE_COLOR := Color(1.0, 0.75, 0.2, 0.95)
const MARKER_SIZE := 10.0

var _tile_size: Vector2 = Vector2(64, 64)
var _map_offset: Vector2 = Vector2.ZERO

var _entrance_pos: Vector2i = Vector2i(-1, -1)
var _route: Array[Vector2i] = []
var _picked_sources: Array[Vector2i] = []

var _route_line: Line2D = null
var _markers: Array[Control] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_line()

func set_tile_size(size: Vector2) -> void:
	_tile_size = size
	_rebuild_visuals()

func set_map_offset(offset: Vector2) -> void:
	_map_offset = offset
	_rebuild_visuals()

func show_plan(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = []) -> void:
	_entrance_pos = entrance_pos
	_route = route.duplicate()
	_picked_sources = picked_sources.duplicate()
	_rebuild_visuals()

func clear_all() -> void:
	_entrance_pos = Vector2i(-1, -1)
	_route.clear()
	_picked_sources.clear()
	_clear_markers()
	if _route_line != null and is_instance_valid(_route_line):
		_route_line.clear_points()

func _ensure_line() -> void:
	if _route_line != null and is_instance_valid(_route_line):
		return

	_route_line = Line2D.new()
	_route_line.width = ROUTE_WIDTH
	_route_line.default_color = ROUTE_COLOR
	_route_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_route_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_route_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_route_line.z_index = 10
	add_child(_route_line)

func _rebuild_visuals() -> void:
	_ensure_line()
	_clear_markers()

	if _route_line == null or not is_instance_valid(_route_line):
		return

	_route_line.clear_points()

	for pos in _route:
		_route_line.add_point(_grid_to_pixel(pos))

	var start := _entrance_pos
	if start == Vector2i(-1, -1) and _route.size() > 0:
		start = _route[0]
	if start != Vector2i(-1, -1):
		_add_marker(start, START_COLOR)

	for src_pos in _picked_sources:
		_add_marker(src_pos, SOURCE_COLOR, MARKER_SIZE * 0.8)

func _grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x, grid_pos.y) * _tile_size + _map_offset + _tile_size / 2.0

func _add_marker(grid_pos: Vector2i, color: Color, size: float = MARKER_SIZE) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.position = _grid_to_pixel(grid_pos) - Vector2(size, size) / 2.0
	rect.z_index = 11
	add_child(rect)
	_markers.append(rect)

func _clear_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()

