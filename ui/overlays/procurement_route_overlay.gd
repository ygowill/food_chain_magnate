# 采购路线覆盖层组件
# 在地图上显示饮料采购的自动规划路线（仅可视化，不改变规则）。
class_name ProcurementRouteOverlay
extends BaseTileOverlay

const ROUTE_CELL_FILL_COLOR := Color(0.35, 0.8, 1.0, 0.22)
const ROUTE_CELL_OUTLINE_COLOR := Color(0.35, 0.8, 1.0, 0.55)

const PREVIEW_ROUTE_CELL_FILL_COLOR := Color(1.0, 0.75, 0.25, 0.18)
const PREVIEW_ROUTE_CELL_OUTLINE_COLOR := Color(1.0, 0.75, 0.25, 0.55)

const ROUTE_CELL_INSET_PX := 2.0
const ROUTE_CELL_OUTLINE_WIDTH := 1.0

const START_COLOR := Color(0.35, 0.9, 0.55, 0.95)
const PREVIEW_START_COLOR := Color(1.0, 0.78, 0.35, 0.95)
const MARKER_SIZE := 10.0
const LEGAL_TILE_OUTLINE_COLOR := Color(0.45, 0.82, 1.0, 0.7)
const SELECTED_TILE_OUTLINE_COLOR := Color(0.12, 0.35, 0.85, 0.95)
const SOURCE_OUTLINE_COLOR := Color(0.12, 0.35, 0.85, 0.95)
const TILE_OUTLINE_WIDTH := 3.0
const SOURCE_OUTLINE_WIDTH := 2.0

var _entrance_pos: Vector2i = Vector2i(-1, -1)
var _route: Array[Vector2i] = []
var _picked_sources: Array[Vector2i] = []

var _markers: Array[Control] = []
var _tile_mode: bool = false
var _show_route: bool = true
var _preview: bool = false
var _tile_size_cells: int = 1
var _legal_tiles: Array[Vector2i] = []
var _selected_tiles: Array[Vector2i] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_layout_changed() -> void:
	_rebuild_visuals()

func show_plan(entrance_pos: Vector2i, route: Array[Vector2i], picked_sources: Array[Vector2i] = [], options: Dictionary = {}) -> void:
	_entrance_pos = entrance_pos
	_route = route.duplicate()
	_picked_sources = picked_sources.duplicate()
	var opts := options if options is Dictionary else {}
	_preview = bool(opts.get("preview", false))
	_tile_mode = bool(opts.get("tile_mode", false)) or str(opts.get("mode", "")) == "air"
	_show_route = bool(opts.get("show_route", opts.get("show_route_line", true)))
	_tile_size_cells = maxi(1, int(opts.get("tile_size_cells", 1)))
	_legal_tiles = _read_vec2i_list(opts.get("legal_tiles", []))
	_selected_tiles = _read_vec2i_list(opts.get("selected_tiles", []))
	_rebuild_visuals()

func clear_all() -> void:
	_entrance_pos = Vector2i(-1, -1)
	_route.clear()
	_picked_sources.clear()
	_tile_mode = false
	_show_route = true
	_preview = false
	_tile_size_cells = 1
	_legal_tiles.clear()
	_selected_tiles.clear()
	_free_nodes(_markers)
	queue_redraw()

func _rebuild_visuals() -> void:
	_free_nodes(_markers)

	if (not _tile_mode) and _show_route:
		var start := _entrance_pos
		if start == Vector2i(-1, -1) and _route.size() > 0:
			start = _route[0]
		if start != Vector2i(-1, -1):
			_add_marker(start, PREVIEW_START_COLOR if _preview else START_COLOR)

	queue_redraw()

func _add_marker(grid_pos: Vector2i, color: Color, size: float = MARKER_SIZE) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.custom_minimum_size = Vector2(size, size)
	rect.size = Vector2(size, size)
	rect.position = _grid_to_pixel_center(grid_pos) - Vector2(size, size) / 2.0
	rect.z_index = 11
	add_child(rect)
	_markers.append(rect)

func _draw() -> void:
	if (not _tile_mode) and _show_route and not _route.is_empty():
		var fill := PREVIEW_ROUTE_CELL_FILL_COLOR if _preview else ROUTE_CELL_FILL_COLOR
		var outline := PREVIEW_ROUTE_CELL_OUTLINE_COLOR if _preview else ROUTE_CELL_OUTLINE_COLOR
		_draw_cell_fills(_route, fill, ROUTE_CELL_INSET_PX, outline, ROUTE_CELL_OUTLINE_WIDTH)
	if _tile_mode:
		_draw_tile_outlines()
	_draw_source_outlines()

func _draw_tile_outlines() -> void:
	if _tile_size_cells <= 0:
		return
	var tile_scale := float(_tile_size_cells)
	var tile_pixel_size := _tile_size * tile_scale

	for tile_pos in _legal_tiles:
		var base := Vector2(tile_pos.x, tile_pos.y) * tile_scale
		var pixel_pos := base * _tile_size + _map_offset
		draw_rect(Rect2(pixel_pos, tile_pixel_size), LEGAL_TILE_OUTLINE_COLOR, false, TILE_OUTLINE_WIDTH)

	for tile_pos in _selected_tiles:
		var base2 := Vector2(tile_pos.x, tile_pos.y) * tile_scale
		var pixel_pos2 := base2 * _tile_size + _map_offset
		draw_rect(Rect2(pixel_pos2, tile_pixel_size), SELECTED_TILE_OUTLINE_COLOR, false, TILE_OUTLINE_WIDTH)

func _draw_source_outlines() -> void:
	if _picked_sources.is_empty():
		return
	for src_pos in _picked_sources:
		var pixel_pos := Vector2(src_pos.x, src_pos.y) * _tile_size + _map_offset
		draw_rect(Rect2(pixel_pos, _tile_size), SOURCE_OUTLINE_COLOR, false, SOURCE_OUTLINE_WIDTH)

func _read_vec2i_list(val) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if val is Array:
		for v in val:
			if v is Vector2i:
				out.append(v)
	return out
