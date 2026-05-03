class_name MapSnapshotCpuCanvas
extends RefCounted

const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const MapCanvasIndexerClass = preload("res://ui/scenes/game/map/indexer.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const ModuleUiMetadataBootstrapClass = preload("res://gameplay/module_ui_metadata_bootstrap.gd")

const PROJECT_FALLBACK_FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"
const BASE_CELL_SIZE := 40
const UI_OUTSIDE_RING_MARGIN := 2

var _zoom: float = 1.0
var _grid_size: Vector2i = Vector2i.ZERO
var _cells: Array = []
var _map_data: Dictionary = {}
var _state_seed: int = 0
var _player_restaurant_logo_ids: Dictionary = {}
var _drive_thru_active_by_owner: Dictionary = {}
var _base_grid_size: Vector2i = Vector2i.ZERO
var _world_origin: Vector2i = Vector2i.ZERO
var _external_cells_by_pos: Dictionary = {}
var _ui_outside_margin_override: int = 0
var _ui_outside_margin_required: int = 0
var _ui_outside_margin_applied: int = 0
var _selected_pos: Vector2i = Vector2i(-1, -1)
var _hover_pos: Vector2i = Vector2i(-1, -1)
var _marketing_by_pos: Dictionary = {}
var _structures_by_anchor: Dictionary = {}
var _hidden_demand_counts_by_house: Dictionary = {}
var _structure_preview_cells: Array[Vector2i] = []
var _structure_preview_valid: bool = true
var _structure_preview_info: Dictionary = {}
var _highlighted_cells: Dictionary = {}
var _piece_overlays: Dictionary = {}
var _move_restaurant_selected_anchor: Vector2i = Vector2i(-1, -1)
var _procure_drinks_restaurant_index_by_anchor: Dictionary = {}
var _procure_drinks_selected_restaurant_anchor: Vector2i = Vector2i(-1, -1)
var _procure_drinks_hovered_restaurant_anchor: Vector2i = Vector2i(-1, -1)
var _skin = null
var _skin_modules_key: String = ""
var _interaction_enabled: bool = false
var _intro_reveal_enabled: bool = false
var _intro_reveal_count: int = 0
var _intro_reveal_total: int = 0
var _intro_reveal_tile_order: Array[Vector2i] = []
var _intro_reveal_tile_index_by_origin: Dictionary = {}
var _image: Image = null
var _transform_origin: Vector2 = Vector2.ZERO
var _transform_rotation: float = 0.0
var _transform_scale: Vector2 = Vector2.ONE
var _project_fallback_font: Font = null

const _INTRO_VOID_CELL := {"tile_origin": Vector2i(-1, -1), "blocked": false}

func render_state_png(state, options: Dictionary = {}) -> Result:
	if state == null or not (state.map is Dictionary):
		return Result.failure("map snapshot: state.map 缺失")
	var metadata_r := _ensure_module_ui_metadata_for_state(state)
	if not metadata_r.ok:
		return metadata_r
	_install_project_fallback_font()
	set_game_state(state)
	if _grid_size == Vector2i.ZERO:
		return Result.failure("map snapshot: grid size 非法")
	if _skin == null:
		return Result.failure("map snapshot: MapSkin 不可用")

	var desired_cell_px := maxi(1, int(options.get("cell_px", BASE_CELL_SIZE)))
	var min_cell_px := maxi(1, int(options.get("min_cell_px", 8)))
	var max_image_dimension := maxi(64, int(options.get("max_image_dimension", 1600)))
	var max_cells := maxi(_grid_size.x, _grid_size.y)
	var cell_px := desired_cell_px
	if max_cells * cell_px > max_image_dimension:
		cell_px = maxi(min_cell_px, int(floor(float(max_image_dimension) / float(max_cells))))
	set_zoom(float(cell_px) / float(BASE_CELL_SIZE))

	var width := maxi(1, _grid_size.x * get_cell_size())
	var height := maxi(1, _grid_size.y * get_cell_size())
	_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	MapCanvasDrawerClass.draw(self)

	var png_bytes := _image.save_png_to_buffer()
	if png_bytes.is_empty():
		return Result.failure("map snapshot: png 编码失败")
	return Result.success({
		"renderer": "map_canvas_cpu",
		"png_bytes": png_bytes,
		"width": width,
		"height": height,
		"cell_px": get_cell_size(),
	})

func set_game_state(state) -> void:
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
			var employees_val = p.get("employees", null)
			if employees_val is Array:
				for e in (employees_val as Array):
					if e is String and (str(e) == "local_manager" or str(e) == "regional_manager"):
						drive_thru_active = true
						break
		_drive_thru_active_by_owner[pid] = drive_thru_active
	set_map_data(state.map)

func set_map_data(map_data: Dictionary) -> void:
	if map_data.is_empty():
		clear()
		return

	_map_data = map_data
	_base_grid_size = _read_vector2i(map_data.get("grid_size", null), Vector2i.ZERO)
	_cells = map_data.get("cells", [])
	if _base_grid_size == Vector2i.ZERO or _cells.is_empty():
		clear()
		return

	_external_cells_by_pos = MapCanvasIndexerClass.parse_external_cells(map_data)
	_ui_outside_margin_required = _compute_required_ui_outside_margin(map_data)
	_refresh_intro_reveal_totals()
	_apply_bounds_for_current_margin(true)

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
	_hidden_demand_counts_by_house.clear()
	_selected_pos = Vector2i(-1, -1)
	_hover_pos = Vector2i(-1, -1)
	_structure_preview_cells.clear()
	_structure_preview_valid = true
	_structure_preview_info.clear()
	_highlighted_cells.clear()
	_piece_overlays.clear()
	_move_restaurant_selected_anchor = Vector2i(-1, -1)
	_procure_drinks_restaurant_index_by_anchor.clear()
	_procure_drinks_selected_restaurant_anchor = Vector2i(-1, -1)
	_procure_drinks_hovered_restaurant_anchor = Vector2i(-1, -1)
	_interaction_enabled = false
	_intro_reveal_enabled = false
	_intro_reveal_count = 0
	_intro_reveal_total = 0
	_intro_reveal_tile_order.clear()
	_intro_reveal_tile_index_by_origin.clear()

func get_cell_size() -> int:
	return maxi(1, int(round(float(BASE_CELL_SIZE) * _zoom)))

func set_zoom(zoom: float) -> void:
	_zoom = clampf(float(zoom), 0.1, 10.0)

func is_intro_reveal_active() -> bool:
	return _intro_reveal_enabled

func is_intro_tile_revealed(board_pos: Vector2i) -> bool:
	if not _intro_reveal_enabled:
		return true
	var idx_val = _intro_reveal_tile_index_by_origin.get(board_pos, null)
	if idx_val is int:
		return int(idx_val) < _intro_reveal_count
	if idx_val is float:
		var f: float = float(idx_val)
		if f == floor(f):
			return int(f) < _intro_reveal_count
	return _intro_reveal_total > 0 and _intro_reveal_count >= _intro_reveal_total

func is_intro_world_pos_revealed(world_pos: Vector2i) -> bool:
	if not _intro_reveal_enabled:
		return true
	if _base_grid_size == Vector2i.ZERO or _map_data.is_empty():
		return true
	var map_origin: Vector2i = _read_vector2i(_map_data.get("map_origin", null), Vector2i.ZERO)
	var idx := world_pos + map_origin
	if not MapUtils.is_valid_pos(idx, _base_grid_size):
		if _external_cells_by_pos.has(world_pos):
			var ext_val = _external_cells_by_pos[world_pos]
			if ext_val is Dictionary:
				var ext_cell: Dictionary = ext_val
				var tile_origin_val2 = ext_cell.get("tile_origin", null)
				if tile_origin_val2 is Vector2i:
					var tile_origin2: Vector2i = tile_origin_val2
					if tile_origin2 == Vector2i(-1, -1):
						return false
					return is_intro_tile_revealed(tile_origin2)
		return true

	if idx.y < 0 or idx.y >= _cells.size():
		return true
	var row_val = _cells[idx.y]
	if not (row_val is Array):
		return true
	var row: Array = row_val
	if idx.x < 0 or idx.x >= row.size():
		return true
	var cell_val = row[idx.x]
	if not (cell_val is Dictionary):
		return true
	var cell: Dictionary = cell_val
	var tile_origin_val = cell.get("tile_origin", null)
	if not (tile_origin_val is Vector2i):
		return false
	var tile_origin: Vector2i = tile_origin_val
	if tile_origin == Vector2i(-1, -1):
		return false
	return is_intro_tile_revealed(tile_origin)

func is_world_pos_in_extension_panel(_world_pos: Vector2i) -> bool:
	return false

func is_interactive_world_pos(world_pos: Vector2i) -> bool:
	return _is_interactive_world_pos(world_pos)

func get_hidden_demand_counts_for_house(house_id: String) -> Dictionary:
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return {}
	var val = _hidden_demand_counts_by_house.get(hid, null)
	if val is Dictionary:
		return (val as Dictionary).duplicate(true)
	return {}

func _ensure_skin(modules: Array[String]) -> void:
	var key: String = str(modules)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key
	_skin = UiSkinCacheClass.get_skin_for_modules(_resolve_modules_base_dir(), modules, BASE_CELL_SIZE)

func _ensure_module_ui_metadata_for_state(state) -> Result:
	var modules: Array[String] = Array(state.modules, TYPE_STRING, "", null)
	var modules_base_dir := _resolve_modules_base_dir()

	if modules.is_empty():
		ModuleUiMetadataBootstrapClass.reset()
		return Result.success()

	var player_count := 1
	if state.players is Array:
		player_count = maxi(1, state.players.size())

	var engine := GameEngineClass.new()
	var init_r: Result = engine.initialize(player_count, int(state.seed), modules, modules_base_dir)
	if not init_r.ok:
		engine.dispose()
		return Result.failure("map snapshot: module UI metadata 初始化失败: %s" % init_r.error)

	var apply_r: Result = ModuleUiMetadataBootstrapClass.apply(engine)
	engine.dispose()
	if not apply_r.ok:
		return Result.failure("map snapshot: module UI metadata 装配失败: %s" % apply_r.error)

	return Result.success()

func _resolve_modules_base_dir() -> String:
	var fallback := str(GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR).strip_edges()
	var base_dir := fallback
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		var globals = (tree as SceneTree).root.get_node_or_null("Globals")
		if globals != null:
			var val = globals.get("modules_v2_base_dir")
			var s := str(val).strip_edges()
			if not s.is_empty():
				base_dir = s
	return ModuleDirSpecClass.primary_base_dir(base_dir, fallback)

func _is_valid_world_pos(world_pos: Vector2i) -> bool:
	var v := world_pos - _world_origin
	return v.x >= 0 and v.x < _grid_size.x and v.y >= 0 and v.y < _grid_size.y

func _is_interactive_world_pos(world_pos: Vector2i) -> bool:
	if not _interaction_enabled:
		return false
	if not _is_valid_world_pos(world_pos):
		return false
	if is_world_pos_in_extension_panel(world_pos):
		return false
	return true

func _get_cell_world(world_pos: Vector2i) -> Dictionary:
	var map_origin: Vector2i = _read_vector2i(_map_data.get("map_origin", null), Vector2i.ZERO)
	var idx := world_pos + map_origin
	if _base_grid_size != Vector2i.ZERO and MapUtils.is_valid_pos(idx, _base_grid_size):
		if idx.y < 0 or idx.y >= _cells.size():
			return {}
		var row_val = _cells[idx.y]
		if not (row_val is Array):
			return {}
		var row: Array = row_val
		if idx.x < 0 or idx.x >= row.size():
			return {}
		var cell_val = row[idx.x]
		if not (cell_val is Dictionary):
			return {}
		var cell: Dictionary = cell_val

		if _intro_reveal_enabled:
			var tile_origin_val = cell.get("tile_origin", null)
			if not (tile_origin_val is Vector2i):
				return _INTRO_VOID_CELL
			var tile_origin: Vector2i = tile_origin_val
			if tile_origin == Vector2i(-1, -1):
				return _INTRO_VOID_CELL
			if not is_intro_tile_revealed(tile_origin):
				return _INTRO_VOID_CELL
		return cell
	if _external_cells_by_pos.has(world_pos):
		var cell_val = _external_cells_by_pos[world_pos]
		if not (cell_val is Dictionary):
			return {}
		var cell: Dictionary = cell_val
		if _intro_reveal_enabled:
			var tile_origin_val = cell.get("tile_origin", null)
			if tile_origin_val is Vector2i:
				var tile_origin: Vector2i = tile_origin_val
				if tile_origin == Vector2i(-1, -1):
					return _INTRO_VOID_CELL
				if not is_intro_tile_revealed(tile_origin):
					return _INTRO_VOID_CELL
		return cell
	return {}

func _world_to_view(world_pos: Vector2i) -> Vector2i:
	return world_pos - _world_origin

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

func _compute_required_ui_outside_margin(map_data: Dictionary) -> int:
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

func _get_effective_ui_outside_margin() -> int:
	return maxi(int(_ui_outside_margin_override), int(_ui_outside_margin_required))

func _apply_bounds_for_current_margin(force_rebuild: bool = false) -> bool:
	if _map_data.is_empty() or _base_grid_size == Vector2i.ZERO:
		return false

	var eff := _get_effective_ui_outside_margin()
	if not force_rebuild and eff == _ui_outside_margin_applied:
		return false

	var map_origin: Vector2i = _read_vector2i(_map_data.get("map_origin", null), Vector2i.ZERO)
	var content_bounds := MapCanvasIndexerClass.compute_bounds(_base_grid_size, map_origin, _external_cells_by_pos, eff)
	var minp: Vector2i = content_bounds.get("min", Vector2i.ZERO)
	var maxp: Vector2i = content_bounds.get("max", Vector2i.ZERO)
	_world_origin = minp
	_grid_size = maxp - minp + Vector2i.ONE
	_ui_outside_margin_applied = eff
	MapCanvasIndexerClass.rebuild_overlay_indexes(self)
	return true

func _refresh_intro_reveal_totals() -> void:
	_rebuild_intro_reveal_tiles()
	_intro_reveal_total = _intro_reveal_tile_order.size()
	if not _intro_reveal_enabled:
		_intro_reveal_count = _intro_reveal_total
	else:
		_intro_reveal_count = clampi(_intro_reveal_count, 0, _intro_reveal_total)

func _rebuild_intro_reveal_tiles() -> void:
	_intro_reveal_tile_order.clear()
	_intro_reveal_tile_index_by_origin.clear()
	if _map_data.is_empty():
		return

	var tps: Array = []
	var base_val = _map_data.get("tile_placements", null)
	if base_val is Array:
		tps.append_array(base_val)
	var ext_val = _map_data.get("external_tile_placements", null)
	if ext_val is Array:
		tps.append_array(ext_val)

	var seen: Dictionary = {}
	for tp_val in tps:
		if not (tp_val is Dictionary):
			continue
		var tp: Dictionary = tp_val
		var bp_val = tp.get("board_pos", null)
		if not (bp_val is Vector2i):
			continue
		var bp: Vector2i = bp_val
		if seen.has(bp):
			continue
		seen[bp] = true
		_intro_reveal_tile_order.append(bp)

	if _intro_reveal_tile_order.is_empty() and _base_grid_size != Vector2i.ZERO:
		for y in range(_base_grid_size.y):
			if y < 0 or y >= _cells.size():
				continue
			var row_val = _cells[y]
			if not (row_val is Array):
				continue
			var row: Array = row_val
			for x in range(_base_grid_size.x):
				if x < 0 or x >= row.size():
					continue
				var cell_val = row[x]
				if not (cell_val is Dictionary):
					continue
				var cell: Dictionary = cell_val
				var tile_origin_val = cell.get("tile_origin", null)
				if not (tile_origin_val is Vector2i):
					continue
				var bp2: Vector2i = tile_origin_val
				if bp2 == Vector2i(-1, -1) or seen.has(bp2):
					continue
				seen[bp2] = true
				_intro_reveal_tile_order.append(bp2)

	_intro_reveal_tile_order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for i in range(_intro_reveal_tile_order.size()):
		_intro_reveal_tile_index_by_origin[_intro_reveal_tile_order[i]] = i

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
	var logo_seed := int(_state_seed) ^ int(0x4C4F474F)
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

func draw_set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	_transform_origin = position
	_transform_rotation = rotation
	_transform_scale = scale

func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0) -> void:
	if _image == null:
		return
	if _is_transform_identity():
		if filled:
			_fill_rect_float(rect, color)
		else:
			_draw_rect_outline(rect, color, width)
		return
	if filled:
		draw_colored_polygon(PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0),
			rect.position + rect.size,
			rect.position + Vector2(0, rect.size.y),
		]), color)

func draw_texture_rect(texture: Texture2D, rect: Rect2, _tile: bool, modulate: Color = Color(1, 1, 1, 1), _transpose: bool = false) -> void:
	if texture == null:
		return
	var size := Vector2i(maxi(1, int(round(absf(rect.size.x)))), maxi(1, int(round(absf(rect.size.y)))))
	var src_rect := Rect2(Vector2.ZERO, texture.get_size())
	_draw_texture_region_to_rect(texture, src_rect, rect, size, modulate)

func draw_texture_rect_region(texture: Texture2D, dst_rect: Rect2, src_rect: Rect2, modulate: Color = Color(1, 1, 1, 1), _transpose: bool = false, _clip_uv: bool = true) -> void:
	if texture == null:
		return
	var size := Vector2i(maxi(1, int(round(absf(dst_rect.size.x)))), maxi(1, int(round(absf(dst_rect.size.y)))))
	_draw_texture_region_to_rect(texture, src_rect, dst_rect, size, modulate)

func draw_circle(position: Vector2, radius: float, color: Color) -> void:
	if _image == null:
		return
	var center := _transform_point(position)
	var r := maxf(0.0, radius)
	var min_x := maxi(0, int(floor(center.x - r)))
	var min_y := maxi(0, int(floor(center.y - r)))
	var max_x := mini(_image.get_width() - 1, int(ceil(center.x + r)))
	var max_y := mini(_image.get_height() - 1, int(ceil(center.y + r)))
	var rr := r * r
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx := float(x) + 0.5 - center.x
			var dy := float(y) + 0.5 - center.y
			if dx * dx + dy * dy <= rr:
				_blend_pixel(x, y, color)

func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	if _image == null or points.size() < 3:
		return
	var pts: Array[Vector2] = []
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in points:
		var tp := _transform_point(p)
		pts.append(tp)
		minp.x = minf(minp.x, tp.x)
		minp.y = minf(minp.y, tp.y)
		maxp.x = maxf(maxp.x, tp.x)
		maxp.y = maxf(maxp.y, tp.y)
	var min_x := maxi(0, int(floor(minp.x)))
	var min_y := maxi(0, int(floor(minp.y)))
	var max_x := mini(_image.get_width() - 1, int(ceil(maxp.x)))
	var max_y := mini(_image.get_height() - 1, int(ceil(maxp.y)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), pts):
				_blend_pixel(x, y, color)

func draw_string(font: Font, pos: Vector2, text: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, font_size: int = 16, modulate: Color = Color(1, 1, 1, 1), justification_flags = 3, direction: TextServer.Direction = TextServer.DIRECTION_AUTO, orientation: TextServer.Orientation = TextServer.ORIENTATION_HORIZONTAL) -> void:
	if _image == null:
		return
	if modulate.a <= 0.001:
		return
	var s := str(text)
	if s.is_empty():
		return

	var fs := maxi(1, int(font_size))
	var effective_font := _choose_text_font(font, s)
	if effective_font == null:
		return
	var string_size := effective_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, justification_flags, direction, orientation)
	var x := pos.x
	if width >= 0.0:
		match alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				x = pos.x + (width - string_size.x) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = pos.x + width - string_size.x
			_:
				x = pos.x

	var clip_rect := Rect2()
	if width >= 0.0:
		var h := maxf(effective_font.get_height(fs), string_size.y)
		clip_rect = Rect2(pos.x, pos.y - h - float(fs), maxf(0.0, width), h + float(fs * 2))
	_draw_font_text(effective_font, Vector2(x, pos.y), s, fs, modulate, width >= 0.0, clip_rect)

func _install_project_fallback_font() -> void:
	var font := _get_project_fallback_font()
	if font == null:
		return
	ThemeDB.fallback_font = font
	var default_theme := ThemeDB.get_default_theme()
	if default_theme != null:
		default_theme.set_default_font(font)

func _get_project_fallback_font() -> Font:
	if _project_fallback_font != null:
		return _project_fallback_font
	var res = load(PROJECT_FALLBACK_FONT_PATH)
	if res is Font:
		_project_fallback_font = res
	return _project_fallback_font

func _choose_text_font(font: Font, text: String) -> Font:
	var fallback := _get_project_fallback_font()
	if font == null:
		return fallback
	if not _font_supports_text(font, text) and fallback != null:
		return fallback
	return font

static func _font_supports_text(font: Font, text: String) -> bool:
	if font == null:
		return false
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code <= 32:
			continue
		if not font.has_char(code):
			return false
	return true

func _get_font_rids_with_project_fallback(font: Font) -> Array[RID]:
	var rids: Array[RID] = []
	if font != null:
		rids = font.get_rids()
	var fallback := _get_project_fallback_font()
	if fallback != null and fallback != font:
		for rid in fallback.get_rids():
			if not rids.has(rid):
				rids.append(rid)
	return rids

func _draw_texture_region_to_rect(texture: Texture2D, src_rect: Rect2, dst_rect: Rect2, dst_size: Vector2i, modulate: Color) -> void:
	if _image == null:
		return
	var patch := _make_texture_patch(texture, src_rect, dst_size, modulate)
	if patch == null or patch.is_empty():
		return
	var transformed := _transform_patch(patch, dst_rect)
	var img: Image = transformed.get("image", null)
	if img == null or img.is_empty():
		return
	_blend_image(img, transformed.get("position", Vector2.ZERO))

func _make_texture_patch(texture: Texture2D, src_rect: Rect2, dst_size: Vector2i, modulate: Color) -> Image:
	var src_img := texture.get_image()
	if src_img == null or src_img.is_empty():
		return null
	if src_img.get_format() != Image.FORMAT_RGBA8:
		src_img.convert(Image.FORMAT_RGBA8)
	var image_size := Vector2i(src_img.get_width(), src_img.get_height())
	var clipped := _clip_src_rect(src_rect, image_size)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return null
	var region := src_img.get_region(clipped)
	if region.get_size() != dst_size:
		region.resize(dst_size.x, dst_size.y, Image.INTERPOLATE_LANCZOS)
	if not _is_white_modulate(modulate):
		_modulate_image(region, modulate)
	return region

func _transform_patch(patch: Image, dst_rect: Rect2) -> Dictionary:
	var quarter := _rotation_quarter()
	var img := patch
	if quarter != 0:
		img = _rotate_image_quarter(patch, quarter)
	var corners := [
		_transform_point(dst_rect.position),
		_transform_point(dst_rect.position + Vector2(dst_rect.size.x, 0)),
		_transform_point(dst_rect.position + dst_rect.size),
		_transform_point(dst_rect.position + Vector2(0, dst_rect.size.y)),
	]
	var minp := Vector2(INF, INF)
	for p in corners:
		minp.x = minf(minp.x, p.x)
		minp.y = minf(minp.y, p.y)
	return {"image": img, "position": minp}

func _blend_image(src: Image, dst_pos: Vector2) -> void:
	if _image == null or src == null or src.is_empty():
		return
	var dst := Vector2i(int(round(dst_pos.x)), int(round(dst_pos.y)))
	var src_rect := Rect2i(Vector2i.ZERO, Vector2i(src.get_width(), src.get_height()))
	if dst.x < 0:
		src_rect.position.x = -dst.x
		src_rect.size.x -= src_rect.position.x
		dst.x = 0
	if dst.y < 0:
		src_rect.position.y = -dst.y
		src_rect.size.y -= src_rect.position.y
		dst.y = 0
	if dst.x + src_rect.size.x > _image.get_width():
		src_rect.size.x = _image.get_width() - dst.x
	if dst.y + src_rect.size.y > _image.get_height():
		src_rect.size.y = _image.get_height() - dst.y
	if src_rect.size.x <= 0 or src_rect.size.y <= 0:
		return
	_image.blend_rect(src, src_rect, dst)

func _blend_image_clipped(src: Image, dst_pos: Vector2, clip_rect: Rect2) -> void:
	if _image == null or src == null or src.is_empty():
		return
	var dst := Vector2i(int(round(dst_pos.x)), int(round(dst_pos.y)))
	var src_rect := Rect2i(Vector2i.ZERO, Vector2i(src.get_width(), src.get_height()))

	var clip := _rect2_to_rect2i(clip_rect)
	if dst.x < clip.position.x:
		src_rect.position.x = clip.position.x - dst.x
		src_rect.size.x -= src_rect.position.x
		dst.x = clip.position.x
	if dst.y < clip.position.y:
		src_rect.position.y = clip.position.y - dst.y
		src_rect.size.y -= src_rect.position.y
		dst.y = clip.position.y
	if dst.x + src_rect.size.x > clip.position.x + clip.size.x:
		src_rect.size.x = clip.position.x + clip.size.x - dst.x
	if dst.y + src_rect.size.y > clip.position.y + clip.size.y:
		src_rect.size.y = clip.position.y + clip.size.y - dst.y
	if src_rect.size.x <= 0 or src_rect.size.y <= 0:
		return
	_blend_image(src.get_region(src_rect), Vector2(dst))

func _draw_font_text(font: Font, baseline: Vector2, text: String, font_size: int, color: Color, use_clip: bool, clip_rect: Rect2) -> void:
	var ts = TextServerManager.get_primary_interface()
	if ts == null:
		return
	var size_v := Vector2i(font_size, 0)
	var rids: Array[RID] = _get_font_rids_with_project_fallback(font)
	if rids.is_empty():
		return

	var cursor := 0.0
	var runs: Array[Dictionary] = []
	var prev_rid := RID()
	var prev_glyph := -1
	for i in range(text.length()):
		var code := text.unicode_at(i)
		var glyph_info := _resolve_font_glyph(ts, rids, font_size, code)
		if glyph_info.is_empty():
			cursor += font_size * 0.5
			prev_rid = RID()
			prev_glyph = -1
			continue
		var rid: RID = glyph_info["rid"]
		var glyph := int(glyph_info["glyph"])
		if prev_glyph >= 0 and rid == prev_rid:
			cursor += float(ts.font_get_kerning(rid, font_size, Vector2i(prev_glyph, glyph)).x)
		ts.font_render_glyph(rid, size_v, glyph)
		runs.append({
			"rid": rid,
			"glyph": glyph,
			"x": cursor,
		})
		cursor += float(ts.font_get_glyph_advance(rid, font_size, glyph).x)
		prev_rid = rid
		prev_glyph = glyph

	for run_val in runs:
		var run: Dictionary = run_val
		var rid2: RID = run["rid"]
		var glyph2 := int(run["glyph"])
		var tex_idx := int(ts.font_get_glyph_texture_idx(rid2, size_v, glyph2))
		if tex_idx < 0:
			continue
		var atlas: Image = ts.font_get_texture_image(rid2, size_v, tex_idx)
		if atlas == null or atlas.is_empty():
			continue
		if atlas.get_format() != Image.FORMAT_RGBA8:
			atlas.convert(Image.FORMAT_RGBA8)
		var uv: Rect2 = ts.font_get_glyph_uv_rect(rid2, size_v, glyph2)
		var uv_rect := _rect2_to_rect2i(uv)
		if uv_rect.size.x <= 0 or uv_rect.size.y <= 0:
			continue
		var glyph_img := atlas.get_region(uv_rect)
		_modulate_image(glyph_img, color)
		var glyph_offset: Vector2 = ts.font_get_glyph_offset(rid2, size_v, glyph2)
		var dst := baseline + Vector2(float(run["x"]), 0.0) + glyph_offset
		if use_clip:
			_blend_image_clipped(glyph_img, dst, clip_rect)
		else:
			_blend_image(glyph_img, dst)

static func _resolve_font_glyph(ts, rids: Array[RID], font_size: int, code: int) -> Dictionary:
	for rid in rids:
		if not (rid is RID):
			continue
		var glyph := int(ts.font_get_glyph_index(rid, font_size, code, 0))
		if glyph > 0:
			return {"rid": rid, "glyph": glyph}
	var fallback_code := "?".unicode_at(0)
	for rid2 in rids:
		if not (rid2 is RID):
			continue
		var fallback_glyph := int(ts.font_get_glyph_index(rid2, font_size, fallback_code, 0))
		if fallback_glyph > 0:
			return {"rid": rid2, "glyph": fallback_glyph}
	return {}

func _fill_rect_float(rect: Rect2, color: Color) -> void:
	var r := _rect2_to_rect2i(rect)
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var clipped := _clip_rect_to_image(r)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	var patch := Image.create(clipped.size.x, clipped.size.y, false, Image.FORMAT_RGBA8)
	patch.fill(color)
	_image.blend_rect(patch, Rect2i(Vector2i.ZERO, clipped.size), clipped.position)

func _draw_rect_outline(rect: Rect2, color: Color, width: float) -> void:
	var w := maxf(1.0, width)
	_fill_rect_float(Rect2(rect.position, Vector2(rect.size.x, w)), color)
	_fill_rect_float(Rect2(rect.position + Vector2(0, rect.size.y - w), Vector2(rect.size.x, w)), color)
	_fill_rect_float(Rect2(rect.position, Vector2(w, rect.size.y)), color)
	_fill_rect_float(Rect2(rect.position + Vector2(rect.size.x - w, 0), Vector2(w, rect.size.y)), color)

func _blend_pixel(x: int, y: int, color: Color) -> void:
	if _image == null:
		return
	if x < 0 or x >= _image.get_width() or y < 0 or y >= _image.get_height():
		return
	var dst := _image.get_pixel(x, y)
	var a := clampf(color.a, 0.0, 1.0)
	var inv := 1.0 - a
	var out := Color(
		color.r * a + dst.r * inv,
		color.g * a + dst.g * inv,
		color.b * a + dst.b * inv,
		a + dst.a * inv
	)
	_image.set_pixel(x, y, out)

func _clip_src_rect(src_rect: Rect2, image_size: Vector2i) -> Rect2i:
	var x := clampi(int(floor(src_rect.position.x)), 0, image_size.x)
	var y := clampi(int(floor(src_rect.position.y)), 0, image_size.y)
	var x2 := clampi(int(ceil(src_rect.position.x + src_rect.size.x)), 0, image_size.x)
	var y2 := clampi(int(ceil(src_rect.position.y + src_rect.size.y)), 0, image_size.y)
	return Rect2i(Vector2i(x, y), Vector2i(maxi(0, x2 - x), maxi(0, y2 - y)))

func _rect2_to_rect2i(rect: Rect2) -> Rect2i:
	var x := int(floor(rect.position.x))
	var y := int(floor(rect.position.y))
	var x2 := int(ceil(rect.position.x + rect.size.x))
	var y2 := int(ceil(rect.position.y + rect.size.y))
	return Rect2i(Vector2i(x, y), Vector2i(maxi(0, x2 - x), maxi(0, y2 - y)))

func _clip_rect_to_image(rect: Rect2i) -> Rect2i:
	if _image == null:
		return Rect2i()
	var x := clampi(rect.position.x, 0, _image.get_width())
	var y := clampi(rect.position.y, 0, _image.get_height())
	var x2 := clampi(rect.position.x + rect.size.x, 0, _image.get_width())
	var y2 := clampi(rect.position.y + rect.size.y, 0, _image.get_height())
	return Rect2i(Vector2i(x, y), Vector2i(maxi(0, x2 - x), maxi(0, y2 - y)))

func _transform_point(point: Vector2) -> Vector2:
	var scaled := Vector2(point.x * _transform_scale.x, point.y * _transform_scale.y)
	if absf(_transform_rotation) <= 0.0001:
		return _transform_origin + scaled
	var c := cos(_transform_rotation)
	var s := sin(_transform_rotation)
	return _transform_origin + Vector2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c)

func _is_transform_identity() -> bool:
	return _transform_origin == Vector2.ZERO and absf(_transform_rotation) <= 0.0001 and _transform_scale == Vector2.ONE

func _rotation_quarter() -> int:
	var deg := int(round(rad_to_deg(_transform_rotation))) % 360
	if deg < 0:
		deg += 360
	match deg:
		90:
			return 1
		180:
			return 2
		270:
			return 3
		_:
			return 0

func _rotate_image_quarter(src: Image, quarter: int) -> Image:
	var q := int(quarter) % 4
	if q == 0:
		return src
	var w := src.get_width()
	var h := src.get_height()
	var out_size := Vector2i(h, w) if q == 1 or q == 3 else Vector2i(w, h)
	var dst := Image.create(out_size.x, out_size.y, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))
	for y in range(h):
		for x in range(w):
			var c := src.get_pixel(x, y)
			match q:
				1:
					dst.set_pixel(h - 1 - y, x, c)
				2:
					dst.set_pixel(w - 1 - x, h - 1 - y, c)
				3:
					dst.set_pixel(y, w - 1 - x, c)
	return dst

func _modulate_image(img: Image, modulate: Color) -> void:
	if img == null or img.is_empty():
		return
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * modulate.r, c.g * modulate.g, c.b * modulate.b, c.a * modulate.a))

func _is_white_modulate(color: Color) -> bool:
	return absf(color.r - 1.0) <= 0.0001 and absf(color.g - 1.0) <= 0.0001 and absf(color.b - 1.0) <= 0.0001 and absf(color.a - 1.0) <= 0.0001

func _point_in_polygon(point: Vector2, points: Array[Vector2]) -> bool:
	var inside := false
	var j := points.size() - 1
	for i in range(points.size()):
		var pi: Vector2 = points[i]
		var pj: Vector2 = points[j]
		if ((pi.y > point.y) != (pj.y > point.y)):
			var denom := pj.y - pi.y
			if absf(denom) > 0.00001:
				var x_intersect := (pj.x - pi.x) * (point.y - pi.y) / denom + pi.x
				if point.x < x_intersect:
					inside = not inside
		j = i
	return inside

static func _read_vector2i(value, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("x") and d.has("y"):
			return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return fallback
