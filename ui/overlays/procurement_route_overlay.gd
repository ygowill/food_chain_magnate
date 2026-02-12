# 采购路线覆盖层组件
# 在地图上显示饮料采购的自动规划路线（仅可视化，不改变规则）。
class_name ProcurementRouteOverlay
extends BaseTileOverlay

const ROUTE_BASE_COLOR := Color("#B200FF")
const ROUTE_ALPHA := 0.34
const ROUTE_PREVIEW_ALPHA := 0.22
const START_RESTAURANT_ALPHA := 0.44
const PICKED_SOURCE_ALPHA := 0.44

const ROUTE_CELL_INSET_PX := 0.0
const LEGAL_TILE_OUTLINE_COLOR := Color(0.45, 0.82, 1.0, 0.7)
const SELECTED_TILE_OUTLINE_COLOR := Color(0.12, 0.35, 0.85, 0.95)
const TILE_OUTLINE_WIDTH := 3.0

var _entrance_pos: Vector2i = Vector2i(-1, -1)
var _start_restaurant_cells: Array[Vector2i] = []
var _route: Array[Vector2i] = []
var _picked_sources: Array[Vector2i] = []

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
	_start_restaurant_cells = _read_vec2i_list(opts.get("start_restaurant_cells", opts.get("start_cells", opts.get("restaurant_cells", []))))
	_rebuild_visuals()

func clear_all() -> void:
	_entrance_pos = Vector2i(-1, -1)
	_start_restaurant_cells.clear()
	_route.clear()
	_picked_sources.clear()
	_tile_mode = false
	_show_route = true
	_preview = false
	_tile_size_cells = 1
	_legal_tiles.clear()
	_selected_tiles.clear()
	queue_redraw()

func _rebuild_visuals() -> void:
	queue_redraw()

func _draw() -> void:
	if (not _tile_mode) and _show_route and not _route.is_empty():
		var fill := ROUTE_BASE_COLOR
		fill.a = ROUTE_PREVIEW_ALPHA if _preview else ROUTE_ALPHA
		_draw_cell_fills(_route, fill, ROUTE_CELL_INSET_PX)

	var start_cells := _start_restaurant_cells
	if start_cells.is_empty() and _entrance_pos != Vector2i(-1, -1):
		start_cells = [_entrance_pos]
	if not start_cells.is_empty():
		var start_fill := ROUTE_BASE_COLOR
		start_fill.a = START_RESTAURANT_ALPHA
		_draw_cell_fills(start_cells, start_fill, 0.0)

	if not _picked_sources.is_empty():
		var src_fill := ROUTE_BASE_COLOR
		src_fill.a = PICKED_SOURCE_ALPHA
		_draw_cell_fills(_picked_sources, src_fill, 0.0)

	if _tile_mode:
		_draw_tile_outlines()

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

func _read_vec2i_list(val) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if val is Array:
		for v in val:
			if v is Vector2i:
				out.append(v)
			elif v is Array:
				var a: Array = v
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					out.append(Vector2i(int(a[0]), int(a[1])))
	return out
