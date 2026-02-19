# 地图绘制画布（UI / M8）
# - Control._draw() 分层渲染（ground/road/drink/piece/marketing/selection）
# - 仅依赖 state.map（不读取 core 的 registry/Def），为后续“图片资源替换”预留接口
extends Control

signal cell_hovered(world_pos: Vector2i)
signal cell_selected(world_pos: Vector2i)

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const MapCanvasIndexerClass = preload("res://ui/scenes/game/map/indexer.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")
const MapCanvasTooltipClass = preload("res://ui/scenes/game/map/tooltip.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

const BASE_CELL_SIZE := 40
const UI_OUTSIDE_RING_MARGIN := 2

const EXT_PANEL_GAP_CELLS := 2
const EXT_PANEL_STACK_GAP_CELLS := 1
const EXT_PANEL_OUTER_PAD_CELLS := 1

var _zoom: float = 1.0

var _grid_size: Vector2i = Vector2i.ZERO
var _cells: Array = []
var _map_data: Dictionary = {}
var _state_seed: int = 0
var _player_restaurant_logo_ids: Dictionary = {} # player_id -> logo_id
var _drive_thru_active_by_owner: Dictionary = {} # player_id -> bool

var _base_grid_size: Vector2i = Vector2i.ZERO
var _world_origin: Vector2i = Vector2i.ZERO # view(0,0) 对应的 world_pos
var _external_cells_by_pos: Dictionary = {} # Vector2i -> cell dict

var _ui_outside_margin_override: int = 0 # 由 UI 模式请求的额外边距（例如飞机营销选点）
var _ui_outside_margin_required: int = 0 # 由当前地图内容决定的边距（例如已放置飞机营销）
var _ui_outside_margin_applied: int = 0

var _selected_pos: Vector2i = Vector2i(-1, -1) # world_pos
var _hover_pos: Vector2i = Vector2i(-1, -1) # world_pos

var _marketing_by_pos: Dictionary = {}  # Vector2i -> placement dict
var _structures_by_anchor: Dictionary = {} # Vector2i -> {piece_id, owner, rotation, min:Vector2i, max:Vector2i}

var _structure_preview_cells: Array[Vector2i] = []
var _structure_preview_valid: bool = true
var _structure_preview_info: Dictionary = {}

var _highlighted_cells: Dictionary = {} # Vector2i -> true

# 通用的 piece overlay（用于“覆盖范围/选中/hover”等统一高亮机制）。
# id -> {cells:Array[Vector2i], fill:Color, border:Color, border_width:float}
var _piece_overlays: Dictionary = {}

# 棋盘扩展面板（右侧附加区域）：用于在地图画布中渲染“非棋盘格/非 external_cells”的模块 UI。
# id -> {id, drawer, width_cells, height_cells, world_rect}
var _extension_panels_by_id: Dictionary = {}
var _extension_panel_order: Array[String] = []
var _content_bounds: Dictionary = {} # 不含扩展面板的 bounds（min/max/size）

# move_restaurant 模式：用于高亮“当前被移动的餐厅”（入口 anchor）。
var _move_restaurant_selected_anchor: Vector2i = Vector2i(-1, -1) # world_pos

var _procure_drinks_restaurant_index_by_anchor: Dictionary = {} # Vector2i(anchor) -> 1-based index
var _procure_drinks_selected_restaurant_anchor: Vector2i = Vector2i(-1, -1) # world_pos
var _procure_drinks_hovered_restaurant_anchor: Vector2i = Vector2i(-1, -1) # world_pos

var _skin = null
var _skin_modules_key: String = ""

func _ready() -> void:
	# 需要让 MapView（ScrollContainer）也能收到滚轮/拖拽等输入，用于缩放/平移。
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_game_state(state: GameState) -> void:
	if state == null:
		clear()
		return
	_state_seed = int(state.seed)
	_ensure_skin(Array(state.modules, TYPE_STRING, "", null))
	_player_restaurant_logo_ids.clear()
	_drive_thru_active_by_owner.clear()
	var logo_count := 0
	if _skin != null and _skin.has_method("get_restaurant_logo_piece_ids"):
		var ids_val = _skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			logo_count = (ids_val as Array).size()
	var fallback_logo_ids: Array[int] = _build_fallback_logo_ids(logo_count)
	var registry_loaded := EmployeeRegistryClass.is_loaded()
	for i in range(state.players.size()):
		var p_val = state.players[i]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var pid := int(p.get("id", i))
		if pid < 0:
			continue

		var logo_id := _read_logo_id(p.get("restaurant_logo_id", null), logo_count)
		if logo_id >= 0:
			_player_restaurant_logo_ids[pid] = logo_id
		else:
			_player_restaurant_logo_ids[pid] = _fallback_logo_id_for_player(pid, fallback_logo_ids)

		var drive_thru_active := false
		if registry_loaded:
			drive_thru_active = EmployeeRulesClass.count_active_by_tag(p, "drivethrough") > 0
		else:
			# 容错：EmployeeRegistry 未初始化时，仅针对基础员工做 best-effort 识别，避免 UI 崩溃。
			var employees_val = p.get("employees", null)
			if employees_val is Array:
				for e in (employees_val as Array):
					if e is String and (str(e) == "local_manager" or str(e) == "regional_manager"):
						drive_thru_active = true
						break
		_drive_thru_active_by_owner[pid] = drive_thru_active
	set_map_data(state.map)

func _read_logo_id(value, logo_count: int) -> int:
	if logo_count <= 0:
		return -1
	var logo_id := -1
	if value is int:
		logo_id = int(value)
	elif value is float:
		var f: float = float(value)
		if f == floor(f):
			logo_id = int(f)
	if logo_id < 0 or logo_id >= logo_count:
		return -1
	return logo_id

func _build_fallback_logo_ids(logo_count: int) -> Array[int]:
	if logo_count <= 0:
		return []
	var ids: Array[int] = []
	for i in range(logo_count):
		ids.append(i)

	var rng := RandomNumberGenerator.new()
	var logo_seed := int(_state_seed) ^ int(0x4C4F474F) # 'LOGO'
	rng.seed = int(logo_seed)
	rng.state = int(logo_seed)
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

	return ids

func _fallback_logo_id_for_player(player_id: int, fallback_logo_ids: Array[int]) -> int:
	if fallback_logo_ids.is_empty():
		return -1
	var pid := maxi(0, int(player_id))
	return int(fallback_logo_ids[pid % fallback_logo_ids.size()])

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
	_ui_outside_margin_required = _compute_required_ui_outside_margin(map_data)

	_apply_bounds_for_current_margin(true)
	queue_redraw()

func clear() -> void:
	_grid_size = Vector2i.ZERO
	_cells = []
	_map_data = {}
	_state_seed = 0
	_player_restaurant_logo_ids.clear()
	_drive_thru_active_by_owner.clear()
	_base_grid_size = Vector2i.ZERO
	_world_origin = Vector2i.ZERO
	_external_cells_by_pos.clear()
	_ui_outside_margin_override = 0
	_ui_outside_margin_required = 0
	_ui_outside_margin_applied = 0
	_marketing_by_pos.clear()
	_structures_by_anchor.clear()
	_selected_pos = Vector2i(-1, -1)
	_hover_pos = Vector2i(-1, -1)
	_structure_preview_cells.clear()
	_structure_preview_valid = true
	_structure_preview_info.clear()
	_highlighted_cells.clear()
	_piece_overlays.clear()
	_extension_panels_by_id.clear()
	_extension_panel_order.clear()
	_content_bounds.clear()
	_move_restaurant_selected_anchor = Vector2i(-1, -1)
	_procure_drinks_restaurant_index_by_anchor.clear()
	_procure_drinks_selected_restaurant_anchor = Vector2i(-1, -1)
	_procure_drinks_hovered_restaurant_anchor = Vector2i(-1, -1)
	custom_minimum_size = Vector2.ZERO
	queue_redraw()

func get_cell_size() -> int:
	return maxi(1, int(round(float(BASE_CELL_SIZE) * _zoom)))

func set_zoom(zoom: float) -> void:
	var z := clampf(float(zoom), 0.1, 10.0)
	if is_equal_approx(_zoom, z):
		return
	_zoom = z
	if _grid_size != Vector2i.ZERO:
		custom_minimum_size = Vector2(float(_grid_size.x * get_cell_size()), float(_grid_size.y * get_cell_size()))
	queue_redraw()

func set_ui_outside_margin_override(margin: int) -> bool:
	# 用于动态控制“地图外围 UI-only 空圈”的显示与交互区域（issue_tracker #64）。
	var m := maxi(0, int(margin))
	if _ui_outside_margin_override == m:
		return false
	_ui_outside_margin_override = m
	return _apply_bounds_for_current_margin()

func get_ui_outside_margin_applied() -> int:
	return _ui_outside_margin_applied

func get_world_origin() -> Vector2i:
	return _world_origin

func set_structure_preview(cells: Array[Vector2i], valid: bool, preview_info: Dictionary = {}) -> void:
	_structure_preview_cells = cells.duplicate()
	_structure_preview_valid = valid
	_structure_preview_info = preview_info.duplicate(true)
	queue_redraw()

func clear_structure_preview() -> void:
	if _structure_preview_cells.is_empty():
		return
	_structure_preview_cells.clear()
	_structure_preview_valid = true
	_structure_preview_info.clear()
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

func set_piece_overlay(id: String, cells: Array[Vector2i], style: Dictionary) -> void:
	var key := str(id).strip_edges()
	if key.is_empty():
		return

	var fill := Color(1, 1, 1, 0)
	var border := Color(1, 1, 1, 0)
	var border_width := 2.0

	var fill_val = style.get("fill", null)
	if fill_val is Color:
		fill = fill_val
	var border_val = style.get("border", null)
	if border_val is Color:
		border = border_val
	var bw_val = style.get("border_width", null)
	if bw_val is float:
		border_width = float(bw_val)
	elif bw_val is int:
		border_width = float(int(bw_val))
	if border_width < 0.0:
		border_width = 0.0

	var out_cells: Array[Vector2i] = []
	for v in cells:
		if v is Vector2i:
			out_cells.append(v)

	_piece_overlays[key] = {
		"cells": out_cells,
		"fill": fill,
		"border": border,
		"border_width": border_width,
	}
	queue_redraw()

func clear_piece_overlay(id: String) -> void:
	var key := str(id).strip_edges()
	if key.is_empty():
		return
	if _piece_overlays.erase(key):
		queue_redraw()

func set_move_restaurant_selected_restaurant(anchor_world_pos: Vector2i) -> void:
	_move_restaurant_selected_anchor = anchor_world_pos
	queue_redraw()

func clear_move_restaurant_selected_restaurant() -> void:
	if _move_restaurant_selected_anchor == Vector2i(-1, -1):
		return
	_move_restaurant_selected_anchor = Vector2i(-1, -1)
	queue_redraw()

func set_procure_drinks_restaurant_indices(index_by_anchor: Dictionary) -> void:
	_procure_drinks_restaurant_index_by_anchor.clear()
	for k in index_by_anchor.keys():
		if not (k is Vector2i):
			continue
		var v = index_by_anchor.get(k, 0)
		var idx := 0
		if v is int:
			idx = int(v)
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				idx = int(f)
		if idx <= 0:
			continue
		_procure_drinks_restaurant_index_by_anchor[Vector2i(k)] = idx
	queue_redraw()

func clear_procure_drinks_restaurant_indices() -> void:
	if _procure_drinks_restaurant_index_by_anchor.is_empty() and _procure_drinks_selected_restaurant_anchor == Vector2i(-1, -1) and _procure_drinks_hovered_restaurant_anchor == Vector2i(-1, -1):
		return
	_procure_drinks_restaurant_index_by_anchor.clear()
	_procure_drinks_selected_restaurant_anchor = Vector2i(-1, -1)
	_procure_drinks_hovered_restaurant_anchor = Vector2i(-1, -1)
	queue_redraw()

func set_procure_drinks_selected_restaurant_anchor(anchor_world_pos: Vector2i) -> void:
	if _procure_drinks_selected_restaurant_anchor == anchor_world_pos:
		return
	_procure_drinks_selected_restaurant_anchor = anchor_world_pos
	queue_redraw()

func clear_procure_drinks_selected_restaurant_anchor() -> void:
	if _procure_drinks_selected_restaurant_anchor == Vector2i(-1, -1):
		return
	_procure_drinks_selected_restaurant_anchor = Vector2i(-1, -1)
	queue_redraw()

func set_procure_drinks_hovered_restaurant_anchor(anchor_world_pos: Vector2i) -> void:
	if _procure_drinks_hovered_restaurant_anchor == anchor_world_pos:
		return
	_procure_drinks_hovered_restaurant_anchor = anchor_world_pos
	queue_redraw()

func clear_procure_drinks_hovered_restaurant_anchor() -> void:
	if _procure_drinks_hovered_restaurant_anchor == Vector2i(-1, -1):
		return
	_procure_drinks_hovered_restaurant_anchor = Vector2i(-1, -1)
	queue_redraw()

func register_map_extension_panel(panel_id: String, drawer, width_cells: int, height_cells: int) -> void:
	var id := str(panel_id).strip_edges()
	if id.is_empty():
		return
	var w := maxi(1, int(width_cells))
	var h := maxi(1, int(height_cells))

	var exists := _extension_panels_by_id.has(id)
	var panel: Dictionary = {}
	if exists and (_extension_panels_by_id.get(id, null) is Dictionary):
		panel = _extension_panels_by_id[id]

	var need_rebuild := (not exists)
	if panel.get("drawer", null) != drawer:
		need_rebuild = true
	if int(panel.get("width_cells", 0)) != w or int(panel.get("height_cells", 0)) != h:
		need_rebuild = true

	panel["id"] = id
	panel["drawer"] = drawer
	panel["width_cells"] = w
	panel["height_cells"] = h
	_extension_panels_by_id[id] = panel

	if not exists:
		_extension_panel_order.append(id)

	if need_rebuild:
		_apply_bounds_for_current_margin(true)
		queue_redraw()

func unregister_map_extension_panel(panel_id: String) -> void:
	var id := str(panel_id).strip_edges()
	if id.is_empty():
		return
	if not _extension_panels_by_id.erase(id):
		return
	_extension_panel_order.erase(id)
	_apply_bounds_for_current_margin(true)
	queue_redraw()

func is_world_pos_in_extension_panel(world_pos: Vector2i) -> bool:
	for id in _extension_panel_order:
		var panel_val = _extension_panels_by_id.get(id, null)
		if not (panel_val is Dictionary):
			continue
		var panel: Dictionary = panel_val
		var rect_val = panel.get("world_rect", null)
		if rect_val is Rect2i:
			if (rect_val as Rect2i).has_point(world_pos):
				return true
			continue

		var min_val = panel.get("world_min", null)
		var size_val = panel.get("world_size", null)
		if not (min_val is Vector2i) or not (size_val is Vector2i):
			continue
		var minp: Vector2i = min_val
		var sizep: Vector2i = size_val
		if world_pos.x >= minp.x and world_pos.x < (minp.x + sizep.x) and world_pos.y >= minp.y and world_pos.y < (minp.y + sizep.y):
			return true
	return false

func is_interactive_world_pos(world_pos: Vector2i) -> bool:
	return _is_interactive_world_pos(world_pos)

func is_cell_highlighted(world_pos: Vector2i) -> bool:
	return _highlighted_cells.has(world_pos)

func _ensure_skin(modules: Array[String]) -> void:
	var key: String = str(modules)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key

	# 复用 UI 全局 MapSkin 缓存，避免开局/首帧重复 build_for_modules 带来的卡顿（issue_tracker #72）。
	_skin = UiSkinCacheClass.get_skin_for_modules(Globals.modules_v2_base_dir, modules, BASE_CELL_SIZE)

func get_skin():
	# 供其它 UI（例如 TopBar 全屏面板）复用当前对局 MapSkin，避免重复构建/加载导致卡顿。
	return _skin

func _gui_input(event: InputEvent) -> void:
	if _grid_size == Vector2i.ZERO:
		return

	if event is InputEventMouseMotion:
		var e: InputEventMouseMotion = event
		var pos := _local_to_world_cell(e.position)
		if pos != _hover_pos:
			_hover_pos = pos
			if _is_interactive_world_pos(_hover_pos):
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
			if _is_interactive_world_pos(pos2):
				_selected_pos = pos2
				cell_selected.emit(_selected_pos)
				queue_redraw()
		return

func _update_tooltip_for_hover() -> void:
	var enabled := false
	if Globals != null:
		enabled = bool(Globals.show_cell_hover_tooltip)
	if not enabled:
		tooltip_text = ""
		return

	if not _is_interactive_world_pos(_hover_pos):
		tooltip_text = ""
		return
	var cell: Dictionary = _get_cell_world(_hover_pos)
	tooltip_text = MapCanvasTooltipClass.format_cell_tooltip(self, _hover_pos, cell)

func _local_to_world_cell(local_pos: Vector2) -> Vector2i:
	var cell_size := float(get_cell_size())
	var x := int(floor(local_pos.x / cell_size))
	var y := int(floor(local_pos.y / cell_size))
	return _world_origin + Vector2i(x, y)

func _is_valid_world_pos(world_pos: Vector2i) -> bool:
	var v := world_pos - _world_origin
	return v.x >= 0 and v.x < _grid_size.x and v.y >= 0 and v.y < _grid_size.y

func _is_interactive_world_pos(world_pos: Vector2i) -> bool:
	if not _is_valid_world_pos(world_pos):
		return false
	if is_world_pos_in_extension_panel(world_pos):
		return false
	return true

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
	_draw_extension_panels()

func _draw_extension_panels() -> void:
	if _extension_panels_by_id.is_empty():
		return
	var cell_size := int(get_cell_size())
	for id in _extension_panel_order:
		var panel_val = _extension_panels_by_id.get(id, null)
		if not (panel_val is Dictionary):
			continue
		var panel: Dictionary = panel_val
		var drawer = panel.get("drawer", null)
		if drawer == null or not is_instance_valid(drawer):
			continue
		if drawer.has_method("draw"):
			drawer.call("draw", self, cell_size, panel)

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
	return Vector2(float(_grid_size.x * BASE_CELL_SIZE), float(_grid_size.y * BASE_CELL_SIZE))

func get_grid_size() -> Vector2i:
	return _grid_size

func _get_effective_ui_outside_margin() -> int:
	return maxi(int(_ui_outside_margin_override), int(_ui_outside_margin_required))

func _compute_required_ui_outside_margin(map_data: Dictionary) -> int:
	# 目前只有飞机营销需要绘制到棋盘外侧；未来其它外围 piece 可在此扩展（issue_tracker #64）。
	if map_data.is_empty():
		return 0
	var placements_val = map_data.get("marketing_placements", null)
	if not (placements_val is Dictionary):
		return 0
	var placements: Dictionary = placements_val
	for k in placements.keys():
		var pv = placements.get(k, null)
		if not (pv is Dictionary):
			continue
		var p: Dictionary = pv
		var t := str(p.get("type", "")).strip_edges()
		if t == "airplane":
			return UI_OUTSIDE_RING_MARGIN
	return 0

func _apply_bounds_for_current_margin(force_rebuild: bool = false) -> bool:
	if _map_data.is_empty() or _base_grid_size == Vector2i.ZERO:
		return false

	var eff := _get_effective_ui_outside_margin()
	if not force_rebuild and eff == _ui_outside_margin_applied:
		return false

	var map_origin: Vector2i = _map_data.get("map_origin", Vector2i.ZERO)
	var content_bounds := MapCanvasIndexerClass.compute_bounds(_base_grid_size, map_origin, _external_cells_by_pos, eff)
	_content_bounds = content_bounds.duplicate()

	var ext := _layout_extension_panels(content_bounds)
	var extra_right := int(ext.get("extra_right", 0))
	var extra_bottom := int(ext.get("extra_bottom", 0))

	var minp: Vector2i = content_bounds.get("min", Vector2i.ZERO)
	var maxp: Vector2i = content_bounds.get("max", Vector2i.ZERO)
	var max2 := Vector2i(maxp.x + extra_right, maxp.y + extra_bottom)
	var size2 := max2 - minp + Vector2i.ONE

	_world_origin = minp
	_grid_size = size2
	_ui_outside_margin_applied = eff

	custom_minimum_size = Vector2(float(_grid_size.x * get_cell_size()), float(_grid_size.y * get_cell_size()))
	MapCanvasIndexerClass.rebuild_overlay_indexes(self)
	queue_redraw()
	return true

func _layout_extension_panels(content_bounds: Dictionary) -> Dictionary:
	# Returns {extra_right:int, extra_bottom:int}. Also updates each panel's world_rect.
	for id in _extension_panel_order:
		var pval = _extension_panels_by_id.get(id, null)
		if not (pval is Dictionary):
			continue
		var p: Dictionary = pval
		p.erase("world_rect")
		p.erase("world_min")
		p.erase("world_size")
		_extension_panels_by_id[id] = p

	if _extension_panel_order.is_empty():
		return {"extra_right": 0, "extra_bottom": 0}

	var panels: Array[Dictionary] = []
	var max_w := 0
	var total_h := 0
	for id in _extension_panel_order:
		var pval2 = _extension_panels_by_id.get(id, null)
		if not (pval2 is Dictionary):
			continue
		var p2: Dictionary = pval2
		var w := maxi(1, int(p2.get("width_cells", 1)))
		var h := maxi(1, int(p2.get("height_cells", 1)))
		p2["width_cells"] = w
		p2["height_cells"] = h
		panels.append(p2)
		max_w = max(max_w, w)
		total_h += h
	if panels.is_empty():
		return {"extra_right": 0, "extra_bottom": 0}
	if panels.size() >= 2:
		total_h += (panels.size() - 1) * EXT_PANEL_STACK_GAP_CELLS

	var minp: Vector2i = content_bounds.get("min", Vector2i.ZERO)
	var maxp: Vector2i = content_bounds.get("max", Vector2i.ZERO)
	var sizep: Vector2i = content_bounds.get("size", Vector2i.ZERO)
	var content_h := maxi(1, int(sizep.y))

	var stack_top := minp.y
	var pad_top := maxi(0, int(floor(float(content_h - total_h) * 0.5)))
	stack_top = minp.y + pad_top

	var start_x := maxp.x + 1 + EXT_PANEL_GAP_CELLS
	var y := stack_top
	for p3 in panels:
		var w3 := int(p3.get("width_cells", 1))
		var h3 := int(p3.get("height_cells", 1))
		var off_x := maxi(0, int(floor(float(max_w - w3) * 0.5)))
		var world_min := Vector2i(start_x + off_x, y)
		var world_size := Vector2i(w3, h3)
		p3["world_min"] = world_min
		p3["world_size"] = world_size
		p3["world_rect"] = Rect2i(world_min, world_size)
		_extension_panels_by_id[str(p3.get("id", ""))] = p3
		y += h3 + EXT_PANEL_STACK_GAP_CELLS

	var extra_right := EXT_PANEL_GAP_CELLS + max_w + EXT_PANEL_OUTER_PAD_CELLS
	var bottom_y := stack_top + total_h - 1
	var extra_bottom := maxi(0, int((bottom_y + EXT_PANEL_OUTER_PAD_CELLS) - maxp.y))
	return {"extra_right": extra_right, "extra_bottom": extra_bottom}
