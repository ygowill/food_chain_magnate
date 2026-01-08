# MapCanvas：_draw 分层渲染逻辑下沉
class_name MapCanvasDrawer
extends RefCounted

static func draw(canvas) -> void:
	if canvas._grid_size == Vector2i.ZERO:
		return
	if canvas._skin == null:
		return

	var cell_size: int = int(canvas.get_cell_size())

	_draw_ground_and_blocked(canvas, cell_size)
	_draw_roads(canvas, cell_size)
	_draw_drink_sources(canvas, cell_size)
	_draw_structures(canvas, cell_size)
	_draw_marketing(canvas, cell_size)
	_draw_house_demands(canvas, cell_size)
	_draw_cell_highlights(canvas, cell_size)
	_draw_structure_preview(canvas, cell_size)
	_draw_selection(canvas, cell_size)

static func _draw_cell_highlights(canvas, cell_size: int) -> void:
	if canvas._highlighted_cells.is_empty():
		return

	for pos_val in canvas._highlighted_cells.keys():
		if not (pos_val is Vector2i):
			continue
		var world_pos: Vector2i = pos_val
		if not canvas._is_valid_world_pos(world_pos):
			continue
		var v = canvas._world_to_view(world_pos)
		var rect := Rect2(Vector2(v.x * cell_size, v.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, Color(0.2, 0.9, 0.35, 0.12), true)
		canvas.draw_rect(rect, Color(0.2, 0.9, 0.35, 0.35), false, 1.0)

static func _draw_structure_preview(canvas, cell_size: int) -> void:
	if canvas._structure_preview_cells.is_empty():
		return

	var fill := Color(0.2, 0.9, 0.35, 0.28) if canvas._structure_preview_valid else Color(0.95, 0.25, 0.25, 0.25)
	var border := Color(0.2, 0.9, 0.35, 0.75) if canvas._structure_preview_valid else Color(0.95, 0.25, 0.25, 0.75)

	for world_pos in canvas._structure_preview_cells:
		if not (world_pos is Vector2i):
			continue
		var p: Vector2i = world_pos
		if not canvas._is_valid_world_pos(p):
			continue
		var v = canvas._world_to_view(p)
		var rect := Rect2(Vector2(v.x * cell_size, v.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, fill, true)
		canvas.draw_rect(rect, border, false, 2.0)

static func _draw_ground_and_blocked(canvas, cell_size: int) -> void:
	var ground_tex: Texture2D = canvas._skin.get_ground_texture()
	var blocked_tex: Texture2D = canvas._skin.get_blocked_overlay_texture()

	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			canvas.draw_texture_rect(ground_tex, rect, false)

			var cell: Dictionary = canvas._get_cell_world(canvas._world_origin + Vector2i(x, y))
			if bool(cell.get("blocked", false)):
				canvas.draw_texture_rect(blocked_tex, rect, false, Color(1, 1, 1, 0.85))

static func _draw_roads(canvas, cell_size: int) -> void:
	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var world_pos = canvas._world_origin + Vector2i(x, y)
			var cell: Dictionary = canvas._get_cell_world(world_pos)
			var segments_val = cell.get("road_segments", null)
			if not (segments_val is Array):
				continue
			var segments: Array = segments_val
			if segments.is_empty():
				continue

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
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
				var tex: Texture2D = canvas._skin.get_road_texture(key)

				var margin := 0.0 if seg_index == 0 else 1.0
				var size := rect.size - Vector2(margin * 2.0, margin * 2.0)
				var offset := Vector2.ZERO
				if seg_index > 0:
					offset = Vector2(0.8, 0.8) * float(seg_index)

				canvas.draw_set_transform(center + offset, deg_to_rad(float(rot_deg)), Vector2.ONE)
				canvas.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _compute_road_shape_info(dirs: Array) -> Dictionary:
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

static func _draw_drink_sources(canvas, cell_size: int) -> void:
	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var world_pos = canvas._world_origin + Vector2i(x, y)
			var cell: Dictionary = canvas._get_cell_world(world_pos)
			var drink_val = cell.get("drink_source", null)
			if not (drink_val is Dictionary):
				continue
			var drink: Dictionary = drink_val
			if drink.is_empty():
				continue
			var product_id: String = str(drink.get("type", ""))
			if product_id.is_empty():
				continue
			var tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			var icon_size := rect.size * 0.6
			var icon_pos := rect.position + (rect.size - icon_size) * 0.5
			canvas.draw_texture_rect(tex, Rect2(icon_pos, icon_size), false)

static func _draw_structures(canvas, cell_size: int) -> void:
	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = canvas._structures_by_anchor[anchor]
		var piece_id: String = str(info.get("piece_id", ""))
		if piece_id.is_empty():
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var max_pos: Vector2i = info.get("max", anchor)
		var size_cells := (max_pos - min_pos) + Vector2i.ONE

		var tex: Texture2D = canvas._skin.get_piece_texture(piece_id)
		var offset_px: Vector2i = canvas._skin.get_piece_offset_px(piece_id)
		var scale: Vector2 = canvas._skin.get_piece_scale(piece_id)

		var pos_px := Vector2(min_pos.x * cell_size, min_pos.y * cell_size) + Vector2(offset_px.x, offset_px.y)
		var size_px := Vector2(size_cells.x * cell_size, size_cells.y * cell_size) * scale
		canvas.draw_texture_rect(tex, Rect2(pos_px, size_px), false, Color(1, 1, 1, 0.85))

static func _draw_marketing(canvas, cell_size: int) -> void:
	for pos_val in canvas._marketing_by_pos.keys():
		if not (pos_val is Vector2i):
			continue
		var world_pos: Vector2i = pos_val
		if not canvas._is_valid_world_pos(world_pos):
			continue
		var p: Dictionary = canvas._marketing_by_pos[world_pos]
		var pos = canvas._world_to_view(world_pos)

		var key: String = "default"
		var type_val = p.get("type", null)
		if type_val is String and not str(type_val).is_empty():
			key = str(type_val)
		var tex: Texture2D = canvas._skin.get_marketing_texture(key)

		var rect := Rect2(Vector2(pos.x * cell_size, pos.y * cell_size), Vector2(cell_size, cell_size))
		var icon_size := rect.size * 0.7
		var icon_pos := rect.position + (rect.size - icon_size) * 0.5
		canvas.draw_texture_rect(tex, Rect2(icon_pos, icon_size), false, Color(1, 1, 1, 0.8))

		var product_id: String = str(p.get("product", ""))
		if not product_id.is_empty():
			var product_tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)
			var badge_size := rect.size * 0.35
			var badge_pos := rect.position + Vector2(rect.size.x - badge_size.x - 2.0, 2.0)
			canvas.draw_texture_rect(product_tex, Rect2(badge_pos, badge_size), false)

static func _draw_house_demands(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	if not canvas._map_data.has("houses") or not (canvas._map_data["houses"] is Dictionary):
		return

	var icon_size := float(cell_size) * 0.25
	var spacing := 2.0
	var cols := 3

	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = canvas._structures_by_anchor[anchor]

		var piece_id: String = str(info.get("piece_id", ""))
		if not piece_id.begins_with("house"):
			continue

		var house_id: String = str(info.get("house_id", ""))
		if house_id.is_empty():
			continue
		var house = canvas._get_house_info(house_id)
		if house.is_empty():
			continue
		var demands_val = house.get("demands", null)
		if not (demands_val is Array):
			continue
		var demands: Array = demands_val
		if demands.is_empty():
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var rect := Rect2(Vector2(min_pos.x * cell_size, min_pos.y * cell_size), Vector2(cell_size, cell_size))

		var count: int = min(demands.size(), 6)
		var rows: int = int((count + cols - 1) / cols)
		var bg_size := Vector2(float(cols) * icon_size + float(cols + 1) * spacing, float(rows) * icon_size + float(rows + 1) * spacing)
		var bg_pos := rect.position + Vector2(1.0, 1.0)
		canvas.draw_rect(Rect2(bg_pos, bg_size), Color(0, 0, 0, 0.25), true)

		for i in range(count):
			var d_val = demands[i]
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			var product_id: String = str(d.get("product", ""))
			if product_id.is_empty():
				continue
			var tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)

			var row := int(i / cols)
			var col := int(i % cols)
			var pos_px := bg_pos + Vector2(spacing + float(col) * (icon_size + spacing), spacing + float(row) * (icon_size + spacing))
			canvas.draw_texture_rect(tex, Rect2(pos_px, Vector2(icon_size, icon_size)), false)

static func _draw_selection(canvas, cell_size: int) -> void:
	if canvas._is_valid_world_pos(canvas._selected_pos):
		var v = canvas._world_to_view(canvas._selected_pos)
		var rect := Rect2(Vector2(v.x * cell_size, v.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, Color(0.2, 0.8, 1.0, 0.9), false, 2.0)
	if canvas._is_valid_world_pos(canvas._hover_pos):
		var v2 = canvas._world_to_view(canvas._hover_pos)
		var rect2 := Rect2(Vector2(v2.x * cell_size, v2.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect2, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)
