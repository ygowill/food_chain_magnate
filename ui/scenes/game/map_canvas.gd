# 地图绘制画布（UI / M8）
# - Control._draw() 分层渲染（ground/road/drink/piece/marketing/selection）
# - 仅依赖 state.map（不读取 core 的 registry/Def），为后续“图片资源替换”预留接口
extends Control

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapSkinClass = preload("res://ui/visual/map_skin.gd")

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
	_external_cells_by_pos = _parse_external_cells(map_data)

	var map_origin: Vector2i = map_data.get("map_origin", Vector2i.ZERO)
	var bounds := _compute_bounds(_base_grid_size, map_origin, _external_cells_by_pos)
	_world_origin = bounds.get("min", Vector2i.ZERO)
	_grid_size = bounds.get("size", _base_grid_size)

	custom_minimum_size = Vector2(float(_grid_size.x * CELL_SIZE), float(_grid_size.y * CELL_SIZE))

	_rebuild_overlay_indexes()
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
	custom_minimum_size = Vector2.ZERO
	queue_redraw()

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

func _rebuild_overlay_indexes() -> void:
	_marketing_by_pos.clear()
	_structures_by_anchor.clear()

	# marketing placements
	if _map_data.has("marketing_placements") and (_map_data["marketing_placements"] is Dictionary):
		var placements: Dictionary = _map_data["marketing_placements"]
		for k in placements.keys():
			var p_val = placements[k]
			if not (p_val is Dictionary):
				continue
			var p: Dictionary = p_val
			var pos_val = p.get("world_pos", null)
			if pos_val is Vector2i:
				_marketing_by_pos[pos_val] = p

	# structures by anchor (scan all cells once)
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
			_index_structure_cell(Vector2i(x, y), row[x])

	var external_positions: Array[Vector2i] = []
	for k in _external_cells_by_pos.keys():
		if k is Vector2i:
			external_positions.append(k)
	external_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for p in external_positions:
		_index_structure_cell(p, _external_cells_by_pos[p])

func _index_structure_cell(world_pos: Vector2i, cell_val) -> void:
	if not (cell_val is Dictionary):
		return
	var cell: Dictionary = cell_val
	var structure_val = cell.get("structure", null)
	if not (structure_val is Dictionary):
		return
	var structure: Dictionary = structure_val
	if structure.is_empty():
		return

	var anchor_val = structure.get("parent_anchor", null)
	if not (anchor_val is Vector2i):
		return
	var anchor: Vector2i = anchor_val

	var piece_id: String = str(structure.get("piece_id", ""))
	var owner: int = int(structure.get("owner", -1))
	var rotation: int = int(structure.get("rotation", 0))
	var house_id: String = str(structure.get("house_id", ""))

	var pos := _world_to_view(world_pos)
	if not _structures_by_anchor.has(anchor):
		_structures_by_anchor[anchor] = {
			"piece_id": piece_id,
			"owner": owner,
			"rotation": rotation,
			"house_id": house_id,
			"min": pos,
			"max": pos,
		}
	else:
		var info: Dictionary = _structures_by_anchor[anchor]
		if not house_id.is_empty():
			info["house_id"] = house_id
		var min_pos: Vector2i = info.get("min", pos)
		var max_pos: Vector2i = info.get("max", pos)
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)
		info["min"] = min_pos
		info["max"] = max_pos
		_structures_by_anchor[anchor] = info

func _gui_input(event: InputEvent) -> void:
	if _grid_size == Vector2i.ZERO:
		return

	if event is InputEventMouseMotion:
		var e: InputEventMouseMotion = event
		var pos := _local_to_world_cell(e.position)
		if pos != _hover_pos:
			_hover_pos = pos
			_update_tooltip_for_hover()
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var e2: InputEventMouseButton = event
		if e2.button_index == MOUSE_BUTTON_LEFT and e2.pressed:
			var pos2 := _local_to_world_cell(e2.position)
			if _is_valid_world_pos(pos2):
				_selected_pos = pos2
				queue_redraw()
		return

func _update_tooltip_for_hover() -> void:
	if not _is_valid_world_pos(_hover_pos):
		tooltip_text = ""
		return
	var cell: Dictionary = _get_cell_world(_hover_pos)
	tooltip_text = _format_cell_tooltip(_hover_pos, cell)

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

func _parse_external_cells(map_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw = map_data.get("external_cells", null)
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	for k in d.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2:
			continue
		if not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		var cell_val = d[k]
		if cell_val is Dictionary:
			out[pos] = cell_val
	return out

func _compute_bounds(base_grid_size: Vector2i, map_origin: Vector2i, external_cells: Dictionary) -> Dictionary:
	var min_pos := Vector2i.ZERO
	var max_pos := Vector2i(max(0, base_grid_size.x - 1), max(0, base_grid_size.y - 1))
	if base_grid_size != Vector2i.ZERO:
		min_pos = -map_origin
		max_pos = Vector2i(
			base_grid_size.x - map_origin.x - 1,
			base_grid_size.y - map_origin.y - 1
		)
	for pos in external_cells.keys():
		if not (pos is Vector2i):
			continue
		var p: Vector2i = pos
		min_pos.x = min(min_pos.x, p.x)
		min_pos.y = min(min_pos.y, p.y)
		max_pos.x = max(max_pos.x, p.x)
		max_pos.y = max(max_pos.y, p.y)
	var size := max_pos - min_pos + Vector2i.ONE
	return {"min": min_pos, "max": max_pos, "size": size}

func _draw() -> void:
	if _grid_size == Vector2i.ZERO:
		return
	if _skin == null:
		return

	_draw_ground_and_blocked()
	_draw_roads()
	_draw_drink_sources()
	_draw_structures()
	_draw_marketing()
	_draw_house_demands()
	_draw_selection()

func _draw_ground_and_blocked() -> void:
	var ground_tex: Texture2D = _skin.get_ground_texture()
	var blocked_tex: Texture2D = _skin.get_blocked_overlay_texture()

	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			draw_texture_rect(ground_tex, rect, false)

			var cell: Dictionary = _get_cell_world(_world_origin + Vector2i(x, y))
			if bool(cell.get("blocked", false)):
				draw_texture_rect(blocked_tex, rect, false, Color(1, 1, 1, 0.85))

func _draw_roads() -> void:
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var world_pos := _world_origin + Vector2i(x, y)
			var cell: Dictionary = _get_cell_world(world_pos)
			var segments_val = cell.get("road_segments", null)
			if not (segments_val is Array):
				continue
			var segments: Array = segments_val
			if segments.is_empty():
				continue

			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var center := rect.position + rect.size * 0.5

			for seg_index in range(segments.size()):
				var seg_val = segments[seg_index]
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				var dirs: Array = dirs_val
				if dirs.is_empty():
					continue
				var is_bridge := bool(seg.get("bridge", false))

				var shape_info := _compute_road_shape_info(dirs)
				if shape_info.is_empty():
					continue
				var shape: String = str(shape_info.get("shape", "default"))
				var rot_deg: int = int(shape_info.get("rotation_deg", 0))

				var key := "road_bridge" if is_bridge else shape
				var tex: Texture2D = _skin.get_road_texture(key)

				var margin := 0.0 if seg_index == 0 else 1.0
				var size := rect.size - Vector2(margin * 2.0, margin * 2.0)
				var offset := Vector2.ZERO
				if seg_index > 0:
					offset = Vector2(0.8, 0.8) * float(seg_index)

				draw_set_transform(center + offset, deg_to_rad(float(rot_deg)), Vector2.ONE)
				draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _compute_road_shape_info(dirs: Array) -> Dictionary:
	var set := {}
	for d in dirs:
		var s: String = str(d)
		if s.is_empty():
			continue
		set[s] = true

	var n := set.size()
	if n <= 0:
		return {}

	if n == 1:
		# base: end points to N
		if set.has("N"):
			return {"shape": "end", "rotation_deg": 0}
		if set.has("E"):
			return {"shape": "end", "rotation_deg": 90}
		if set.has("S"):
			return {"shape": "end", "rotation_deg": 180}
		if set.has("W"):
			return {"shape": "end", "rotation_deg": 270}
		return {"shape": "end", "rotation_deg": 0}

	if n == 2:
		var has_n := set.has("N")
		var has_e := set.has("E")
		var has_s := set.has("S")
		var has_w := set.has("W")

		# straight: base texture is N-S
		if (has_e and has_w) or (has_n and has_s):
			return {"shape": "straight", "rotation_deg": 0 if (has_n and has_s) else 90}

		# corner: base texture is W-S
		if has_w and has_s:
			return {"shape": "corner", "rotation_deg": 0}
		if has_n and has_w:
			return {"shape": "corner", "rotation_deg": 90}
		if has_n and has_e:
			return {"shape": "corner", "rotation_deg": 180}
		if has_e and has_s:
			return {"shape": "corner", "rotation_deg": 270}

		return {"shape": "corner", "rotation_deg": 0}

	if n == 3:
		# tee: base texture is N-W-S (missing E)
		if not set.has("E"):
			return {"shape": "tee", "rotation_deg": 0}
		if not set.has("S"):
			return {"shape": "tee", "rotation_deg": 90}
		if not set.has("W"):
			return {"shape": "tee", "rotation_deg": 180}
		if not set.has("N"):
			return {"shape": "tee", "rotation_deg": 270}
		return {"shape": "tee", "rotation_deg": 0}

	# n >= 4
	return {"shape": "cross", "rotation_deg": 0}

func _draw_drink_sources() -> void:
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var world_pos := _world_origin + Vector2i(x, y)
			var cell: Dictionary = _get_cell_world(world_pos)
			var drink_val = cell.get("drink_source", null)
			if not (drink_val is Dictionary):
				continue
			var drink: Dictionary = drink_val
			if drink.is_empty():
				continue
			var product_id: String = str(drink.get("type", ""))
			if product_id.is_empty():
				continue
			var tex: Texture2D = _skin.get_product_icon_texture(product_id)

			var rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var icon_size := rect.size * 0.6
			var icon_pos := rect.position + (rect.size - icon_size) * 0.5
			draw_texture_rect(tex, Rect2(icon_pos, icon_size), false)

func _draw_structures() -> void:
	for anchor_val in _structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = _structures_by_anchor[anchor]
		var piece_id: String = str(info.get("piece_id", ""))
		if piece_id.is_empty():
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var max_pos: Vector2i = info.get("max", anchor)
		var size_cells := (max_pos - min_pos) + Vector2i.ONE

		var tex: Texture2D = _skin.get_piece_texture(piece_id)
		var offset_px: Vector2i = _skin.get_piece_offset_px(piece_id)
		var scale: Vector2 = _skin.get_piece_scale(piece_id)

		var pos_px := Vector2(min_pos.x * CELL_SIZE, min_pos.y * CELL_SIZE) + Vector2(offset_px.x, offset_px.y)
		var size_px := Vector2(size_cells.x * CELL_SIZE, size_cells.y * CELL_SIZE) * scale
		draw_texture_rect(tex, Rect2(pos_px, size_px), false, Color(1, 1, 1, 0.85))

func _draw_marketing() -> void:
	for pos_val in _marketing_by_pos.keys():
		if not (pos_val is Vector2i):
			continue
		var world_pos: Vector2i = pos_val
		if not _is_valid_world_pos(world_pos):
			continue
		var p: Dictionary = _marketing_by_pos[world_pos]
		var pos := _world_to_view(world_pos)

		var key: String = "default"
		var type_val = p.get("type", null)
		if type_val is String and not str(type_val).is_empty():
			key = str(type_val)
		var tex: Texture2D = _skin.get_marketing_texture(key)

		var rect := Rect2(Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
		var icon_size := rect.size * 0.7
		var icon_pos := rect.position + (rect.size - icon_size) * 0.5
		draw_texture_rect(tex, Rect2(icon_pos, icon_size), false, Color(1, 1, 1, 0.8))

		var product_id: String = str(p.get("product", ""))
		if not product_id.is_empty():
			var product_tex: Texture2D = _skin.get_product_icon_texture(product_id)
			var badge_size := rect.size * 0.35
			var badge_pos := rect.position + Vector2(rect.size.x - badge_size.x - 2.0, 2.0)
			draw_texture_rect(product_tex, Rect2(badge_pos, badge_size), false)

func _draw_house_demands() -> void:
	if _map_data.is_empty():
		return
	if not _map_data.has("houses") or not (_map_data["houses"] is Dictionary):
		return

	var icon_size := float(CELL_SIZE) * 0.25
	var spacing := 2.0
	var cols := 3

	for anchor_val in _structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = _structures_by_anchor[anchor]

		var piece_id: String = str(info.get("piece_id", ""))
		if not piece_id.begins_with("house"):
			continue

		var house_id: String = str(info.get("house_id", ""))
		if house_id.is_empty():
			continue
		var house := _get_house_info(house_id)
		if house.is_empty():
			continue
		var demands_val = house.get("demands", null)
		if not (demands_val is Array):
			continue
		var demands: Array = demands_val
		if demands.is_empty():
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var rect := Rect2(Vector2(min_pos.x * CELL_SIZE, min_pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))

		var count: int = min(demands.size(), 6)
		var rows: int = int((count + cols - 1) / cols)
		var bg_size := Vector2(float(cols) * icon_size + float(cols + 1) * spacing, float(rows) * icon_size + float(rows + 1) * spacing)
		var bg_pos := rect.position + Vector2(1.0, 1.0)
		draw_rect(Rect2(bg_pos, bg_size), Color(0, 0, 0, 0.25), true)

		for i in range(count):
			var d_val = demands[i]
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			var product_id: String = str(d.get("product", ""))
			if product_id.is_empty():
				continue
			var tex: Texture2D = _skin.get_product_icon_texture(product_id)

			var row := int(i / cols)
			var col := int(i % cols)
			var pos_px := bg_pos + Vector2(spacing + float(col) * (icon_size + spacing), spacing + float(row) * (icon_size + spacing))
			draw_texture_rect(tex, Rect2(pos_px, Vector2(icon_size, icon_size)), false)

func _draw_selection() -> void:
	if _is_valid_world_pos(_selected_pos):
		var v := _world_to_view(_selected_pos)
		var rect := Rect2(Vector2(v.x * CELL_SIZE, v.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.9), false, 2.0)
	if _is_valid_world_pos(_hover_pos):
		var v2 := _world_to_view(_hover_pos)
		var rect2 := Rect2(Vector2(v2.x * CELL_SIZE, v2.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(rect2, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

func _format_cell_tooltip(pos: Vector2i, cell: Dictionary) -> String:
	if cell.is_empty():
		return "pos=(%d,%d)" % [pos.x, pos.y]

	var lines: Array[String] = []
	lines.append("pos=(%d,%d)" % [pos.x, pos.y])

	var tile_origin: Vector2i = cell.get("tile_origin", Vector2i(-1, -1))
	if tile_origin != Vector2i(-1, -1):
		lines.append("tile_origin=(%d,%d)" % [tile_origin.x, tile_origin.y])

	if bool(cell.get("blocked", false)):
		lines.append("blocked=true")

	var road_segments: Array = cell.get("road_segments", [])
	if not road_segments.is_empty():
		lines.append("road_segments=%d" % road_segments.size())

	var drink_source_val = cell.get("drink_source", null)
	if drink_source_val is Dictionary:
		var drink_source: Dictionary = drink_source_val
		if not drink_source.is_empty():
			lines.append("drink=%s" % str(drink_source.get("type", "")))

	var structure: Dictionary = cell.get("structure", {})
	if not structure.is_empty():
		var piece_id := str(structure.get("piece_id", ""))
		var owner: int = int(structure.get("owner", -1))
		lines.append("structure=%s owner=%d" % [piece_id, owner])
		if structure.has("house_id") and not str(structure.get("house_id", "")).is_empty():
			lines.append("house_id=%s" % str(structure.get("house_id", "")))
		if structure.has("house_number"):
			lines.append("house_number=%s" % str(structure.get("house_number", "")))
		lines.append("rotation=%s" % str(structure.get("rotation", 0)))

		if piece_id == "house":
			var house_id := str(structure.get("house_id", ""))
			var info := _get_house_info(house_id)
			if not info.is_empty():
				lines.append("has_garden=%s" % str(bool(info.get("has_garden", false))))
				var demands_val = info.get("demands", null)
				if demands_val is Array:
					var demands: Array = demands_val
					lines.append("demands=%d" % demands.size())

	if _marketing_by_pos.has(pos):
		var mk: Dictionary = _marketing_by_pos[pos]
		var bn = mk.get("board_number", null)
		var t := str(mk.get("type", ""))
		var product := str(mk.get("product", ""))
		var owner = mk.get("owner", null)
		var rd = mk.get("remaining_duration", null)
		lines.append("marketing=%s type=%s product=%s owner=%s duration=%s" % [
			str(bn), t, product, str(owner), str(rd)
		])

	return "\n".join(lines)

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
