# 地图绘制画布（UI / M8）
# - Control._draw() 分层渲染（ground/road/drink/piece/marketing/selection）
# - 仅依赖 state.map（不读取 core 的 registry/Def），为后续“图片资源替换”预留接口
extends Control

signal cell_hovered(world_pos: Vector2i)
signal cell_selected(world_pos: Vector2i)

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapSkinClass = preload("res://ui/visual/map_skin.gd")
const MapCanvasIndexerClass = preload("res://ui/scenes/game/map_canvas_indexer.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const MapCanvasTooltipClass = preload("res://ui/scenes/game/map_canvas_tooltip.gd")

const CELL_SIZE := 40

var _grid_size: Vector2i = Vector2i.ZERO
var _cells: Array = []
var _map_data: Dictionary = {}

var _base_grid_size: Vector2i = Vector2i.ZERO
var _world_origin: Vector2i = Vector2i.ZERO # view(0,0) 对应的 world_pos
var _external_cells_by_pos: Dictionary = {} # Vector2i -> cell dict

var _selected_pos: Vector2i = Vector2i(-1, -1) # world_pos
var _hover_pos: Vector2i = Vector2i(-1, -1) # world_pos

var _marketing_by_pos: Dictionary = {}  # Vector2i -> placement dict
var _structures_by_anchor: Dictionary = {} # Vector2i -> {piece_id, owner, rotation, min:Vector2i, max:Vector2i}

var _structure_preview_cells: Array[Vector2i] = []
var _structure_preview_valid: bool = true

var _highlighted_cells: Dictionary = {} # Vector2i -> true

var _skin = null
var _skin_modules_key: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_game_state(state: GameState) -> void:
	if state == null:
		clear()
		return
	_ensure_skin(Array(state.modules, TYPE_STRING, "", null))
	set_map_data(state.map)

func set_map_data(map_data: Dictionary) -> void:
	if map_data.is_empty():
		clear()
		return

	_map_data = map_data
	var grid_size: Vector2i = map_data.get("grid_size", Vector2i.ZERO)
	var cells: Array = map_data.get("cells", [])
	if grid_size == Vector2i.ZERO or cells.is_empty():
		clear()
		return

	_base_grid_size = grid_size
	_cells = cells
	_external_cells_by_pos = MapCanvasIndexerClass.parse_external_cells(map_data)

	var map_origin: Vector2i = map_data.get("map_origin", Vector2i.ZERO)
	var bounds := MapCanvasIndexerClass.compute_bounds(_base_grid_size, map_origin, _external_cells_by_pos)
	_world_origin = bounds.get("min", Vector2i.ZERO)
	_grid_size = bounds.get("size", _base_grid_size)

	custom_minimum_size = Vector2(float(_grid_size.x * CELL_SIZE), float(_grid_size.y * CELL_SIZE))

	MapCanvasIndexerClass.rebuild_overlay_indexes(self)
	queue_redraw()

func clear() -> void:
	_grid_size = Vector2i.ZERO
	_cells = []
	_map_data = {}
	_base_grid_size = Vector2i.ZERO
	_world_origin = Vector2i.ZERO
	_external_cells_by_pos.clear()
	_marketing_by_pos.clear()
	_structures_by_anchor.clear()
	_selected_pos = Vector2i(-1, -1)
	_hover_pos = Vector2i(-1, -1)
	_structure_preview_cells.clear()
	_structure_preview_valid = true
	_highlighted_cells.clear()
	custom_minimum_size = Vector2.ZERO
	queue_redraw()

func get_cell_size() -> int:
	return CELL_SIZE

func get_world_origin() -> Vector2i:
	return _world_origin

func set_structure_preview(cells: Array[Vector2i], valid: bool) -> void:
	_structure_preview_cells = cells.duplicate()
	_structure_preview_valid = valid
	queue_redraw()

func clear_structure_preview() -> void:
	if _structure_preview_cells.is_empty():
		return
	_structure_preview_cells.clear()
	_structure_preview_valid = true
	queue_redraw()

func set_cell_highlights(cells: Array[Vector2i]) -> void:
	_highlighted_cells.clear()
	for v in cells:
		if v is Vector2i:
			_highlighted_cells[v] = true
	queue_redraw()

func clear_cell_highlights() -> void:
	if _highlighted_cells.is_empty():
		return
	_highlighted_cells.clear()
	queue_redraw()

func is_cell_highlighted(world_pos: Vector2i) -> bool:
	return _highlighted_cells.has(world_pos)

func _ensure_skin(modules: Array[String]) -> void:
	var key: String = str(modules)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key

	var read := MapSkinBuilderClass.build_for_modules(Globals.modules_v2_base_dir, modules, CELL_SIZE)
	if read.ok and read.value != null:
		_skin = read.value
		return

	push_error("MapCanvas: MapSkin 构建失败，将使用占位皮肤: %s" % str(read.error))
	var fallback = MapSkinClass.new()
	fallback.cell_size_px = CELL_SIZE
	fallback._init_placeholders()
	_skin = fallback

func _gui_input(event: InputEvent) -> void:
	if _grid_size == Vector2i.ZERO:
		return

	if event is InputEventMouseMotion:
		var e: InputEventMouseMotion = event
		var pos := _local_to_world_cell(e.position)
		if pos != _hover_pos:
			_hover_pos = pos
			if _is_valid_world_pos(_hover_pos):
				cell_hovered.emit(_hover_pos)
			else:
				cell_hovered.emit(Vector2i(-1, -1))
			_update_tooltip_for_hover()
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var e2: InputEventMouseButton = event
		if e2.button_index == MOUSE_BUTTON_LEFT and e2.pressed:
			var pos2 := _local_to_world_cell(e2.position)
			if _is_valid_world_pos(pos2):
				_selected_pos = pos2
				cell_selected.emit(_selected_pos)
				queue_redraw()
		return

func _update_tooltip_for_hover() -> void:
	if not _is_valid_world_pos(_hover_pos):
		tooltip_text = ""
		return
	var cell: Dictionary = _get_cell_world(_hover_pos)
	tooltip_text = MapCanvasTooltipClass.format_cell_tooltip(self, _hover_pos, cell)

func _local_to_world_cell(local_pos: Vector2) -> Vector2i:
	var x := int(floor(local_pos.x / float(CELL_SIZE)))
	var y := int(floor(local_pos.y / float(CELL_SIZE)))
	return _world_origin + Vector2i(x, y)

func _is_valid_world_pos(world_pos: Vector2i) -> bool:
	var v := world_pos - _world_origin
	return v.x >= 0 and v.x < _grid_size.x and v.y >= 0 and v.y < _grid_size.y

func _get_cell_world(world_pos: Vector2i) -> Dictionary:
	var map_origin: Vector2i = _map_data.get("map_origin", Vector2i.ZERO)
	var idx := world_pos + map_origin
	if _base_grid_size != Vector2i.ZERO and MapUtils.is_valid_pos(idx, _base_grid_size):
		var row_val = _cells[idx.y]
		if not (row_val is Array):
			return {}
		var row: Array = row_val
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			return {}
		return cell_val
	if _external_cells_by_pos.has(world_pos):
		var cell_val = _external_cells_by_pos[world_pos]
		return cell_val if cell_val is Dictionary else {}
	return {}

func _world_to_view(world_pos: Vector2i) -> Vector2i:
	return world_pos - _world_origin

func _draw() -> void:
	MapCanvasDrawerClass.draw(self)

func _get_house_info(house_id: String) -> Dictionary:
	if house_id.is_empty():
		return {}
	if _map_data.is_empty():
		return {}
	if not _map_data.has("houses") or not (_map_data["houses"] is Dictionary):
		return {}
	var houses: Dictionary = _map_data["houses"]
	var val = houses.get(house_id, null)
	if not (val is Dictionary):
		return {}
	return val

# === 缩放辅助方法 ===

func get_base_size() -> Vector2:
	return Vector2(float(_grid_size.x * CELL_SIZE), float(_grid_size.y * CELL_SIZE))

func get_grid_size() -> Vector2i:
	return _grid_size

