# MapCanvas：_draw 分层渲染逻辑下沉
class_name MapCanvasDrawer
extends RefCounted

const RESTAURANT_LOGO_PIECE_IDS = [
	"restaurant_logo_fried_geese_donkey",
	"restaurant_logo_gluttony_inc_burgers",
	"restaurant_logo_golden_duck_diner",
	"restaurant_logo_santa_maria_pizza",
	"restaurant_logo_xango_blues_bar",
]

static func _draw_texture_aspect_fit(canvas, texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1), v_align: String = "center") -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return

	var scale := minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var size := ts * scale
	var pos := rect.position + (rect.size - size) * 0.5
	if v_align == "top":
		pos.y = rect.position.y
	elif v_align == "bottom":
		pos.y = rect.position.y + rect.size.y - size.y

	canvas.draw_texture_rect(texture, Rect2(pos, size), false, modulate)

static func _draw_texture_aspect_fill(canvas, texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1)) -> void:
	if texture == null:
		return
	var ts: Vector2 = texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var dest_ratio := rect.size.x / rect.size.y
	var src_ratio := ts.x / ts.y

	var src_rect := Rect2(Vector2.ZERO, ts)
	if src_ratio > dest_ratio:
		var w := ts.y * dest_ratio
		src_rect.position.x = (ts.x - w) * 0.5
		src_rect.size.x = w
	else:
		var h := ts.x / dest_ratio
		src_rect.position.y = (ts.y - h) * 0.5
		src_rect.size.y = h

	canvas.draw_texture_rect_region(texture, rect, src_rect, modulate)

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
	_draw_house_demands(canvas, cell_size)
	_draw_marketing(canvas, cell_size)
	_draw_tile_borders(canvas, cell_size)
	_draw_cell_highlights(canvas, cell_size)
	_draw_structure_preview(canvas, cell_size)
	_draw_selection(canvas, cell_size)

static func _hash_string_32(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h ^= text.unicode_at(i)
		h = int((h * 16777619) & 0xFFFFFFFF)
	return h

static func _compute_demand_scatter_seed(canvas, house_id: String) -> int:
	var seed := _hash_string_32(house_id)
	var state_seed := 0
	if canvas != null:
		state_seed = int(canvas._state_seed)
	return int((seed ^ state_seed) & 0x7FFFFFFF)

static func _compute_house_id_rect(cell_size: int, structure_rect: Rect2) -> Rect2:
	var pad := maxf(3.0, float(cell_size) * 0.10)
	var bg_size := Vector2(float(cell_size) * 0.90, float(cell_size) * 0.58)
	var pos := structure_rect.position + Vector2(structure_rect.size.x - bg_size.x - pad, pad)
	return Rect2(pos, bg_size)

static func _is_scatter_rect_free(candidate: Rect2, taken: Array[Rect2], min_spacing: float) -> bool:
	var grow := maxf(min_spacing, 0.0)
	var cand := candidate.grow(grow)
	for r in taken:
		if cand.intersects(r.grow(grow)):
			return false
	return true

static func _find_scatter_rect(
	rng: RandomNumberGenerator,
	taken: Array[Rect2],
	area: Rect2,
	icon_size: float,
	min_spacing: float,
	fallback_index: int
) -> Rect2:
	var margin := maxf(2.0, min_spacing)
	var min_x := area.position.x + margin
	var min_y := area.position.y + margin
	var max_x := area.position.x + area.size.x - icon_size - margin
	var max_y := area.position.y + area.size.y - icon_size - margin
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y

	for _attempt in range(32):
		# Center-biased sampling: triangular distribution peaks at 0.5.
		var tx := (rng.randf() + rng.randf()) * 0.5
		var ty := (rng.randf() + rng.randf()) * 0.5
		var x := lerpf(min_x, max_x, tx)
		var y := lerpf(min_y, max_y, ty)
		var rect := Rect2(Vector2(x, y), Vector2(icon_size, icon_size))
		if _is_scatter_rect_free(rect, taken, min_spacing):
			return rect

	var cols := maxi(1, int(floor(area.size.x / maxf(icon_size + min_spacing, 1.0))))
	var col := int(fallback_index % cols)
	var row := int(fallback_index / cols)
	var x2 := min_x + float(col) * (icon_size + min_spacing)
	var y2 := min_y + float(row) * (icon_size + min_spacing)
	x2 = clampf(x2, min_x, max_x)
	y2 = clampf(y2, min_y, max_y)
	return Rect2(Vector2(x2, y2), Vector2(icon_size, icon_size))

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

	var preview_info_val = canvas._structure_preview_info
	if preview_info_val is Dictionary and not preview_info_val.is_empty():
		_draw_structure_preview_piece(canvas, cell_size, preview_info_val)

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

static func _draw_structure_preview_piece(canvas, cell_size: int, preview_info: Dictionary) -> void:
	if canvas._skin == null:
		return
	var piece_id := str(preview_info.get("piece_id", "")).strip_edges()
	if piece_id.is_empty():
		return
	var anchor_val = preview_info.get("anchor", null)
	if not (anchor_val is Vector2i):
		return
	var anchor: Vector2i = anchor_val
	var rotation: int = int(preview_info.get("rotation", 0))
	var owner: int = int(preview_info.get("owner", -1))

	var vmin := Vector2i(2147483647, 2147483647)
	var vmax := Vector2i(-2147483648, -2147483648)
	var any := false
	for world_pos in canvas._structure_preview_cells:
		if not (world_pos is Vector2i):
			continue
		var vpos: Vector2i = canvas._world_to_view(world_pos)
		any = true
		vmin.x = min(vmin.x, vpos.x)
		vmin.y = min(vmin.y, vpos.y)
		vmax.x = max(vmax.x, vpos.x)
		vmax.y = max(vmax.y, vpos.y)
	if not any:
		return

	var size_cells := (vmax - vmin) + Vector2i.ONE
	var structure_rect := Rect2(
		Vector2(vmin.x * cell_size, vmin.y * cell_size),
		Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	)

	var alpha := 0.65
	var info := {
		"piece_id": piece_id,
		"rotation": rotation,
		"owner": owner,
		"min": vmin,
		"max": vmax,
	}

	if piece_id == "restaurant":
		_draw_restaurant(canvas, cell_size, anchor, info, structure_rect, alpha)
	elif piece_id == "house" or piece_id == "house_with_garden":
		_draw_house_and_garden(canvas, cell_size, anchor, info, alpha)

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
			_draw_texture_aspect_fit(canvas, tex, Rect2(icon_pos, icon_size))

static func _draw_structures(canvas, cell_size: int) -> void:
	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = canvas._structures_by_anchor[anchor]
		var piece_id: String = str(info.get("piece_id", ""))
		if piece_id.is_empty():
			continue

		if piece_id == "house" or piece_id == "house_with_garden":
			_draw_house_and_garden(canvas, cell_size, anchor, info)
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var max_pos: Vector2i = info.get("max", anchor)
		var size_cells := (max_pos - min_pos) + Vector2i.ONE

		var tex: Texture2D = canvas._skin.get_piece_texture(piece_id)
		var offset_px: Vector2i = canvas._skin.get_piece_offset_px(piece_id)
		var scale: Vector2 = canvas._skin.get_piece_scale(piece_id)

		var pos_px := Vector2(min_pos.x * cell_size, min_pos.y * cell_size) + Vector2(offset_px.x, offset_px.y)
		var size_px := Vector2(size_cells.x * cell_size, size_cells.y * cell_size) * scale
		var rect := Rect2(pos_px, size_px)
		if piece_id == "restaurant":
			_draw_restaurant(canvas, cell_size, anchor, info, rect)
			continue

		if piece_id == "house":
			_draw_texture_aspect_fit(canvas, tex, rect, Color(1, 1, 1, 0.85), "bottom")
		else:
			canvas.draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.85))

static func _draw_restaurant(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, structure_rect: Rect2, alpha: float = 1.0) -> void:
	var owner := int(info.get("owner", -1))
	if owner < 0:
		return
	if canvas._skin == null:
		return
	if RESTAURANT_LOGO_PIECE_IDS.is_empty():
		return

	var logo_map: Dictionary = canvas._player_restaurant_logo_ids
	var logo_id := int(logo_map.get(owner, -1))
	if logo_id < 0 or logo_id >= RESTAURANT_LOGO_PIECE_IDS.size():
		return

	var logo_key: String = RESTAURANT_LOGO_PIECE_IDS[logo_id]
	var tex: Texture2D = canvas._skin.get_piece_texture(logo_key)
	var bg := Color("#f4edd1")
	bg.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(structure_rect, bg, true)

	var logo_rect := structure_rect.grow(-maxf(2.0, float(cell_size) * 0.10))
	_draw_texture_aspect_fit(canvas, tex, logo_rect, Color(1, 1, 1, 0.98 * alpha))

	_draw_restaurant_entrance_marker(canvas, cell_size, anchor, info, alpha)

static func _draw_restaurant_entrance_marker(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, alpha: float = 1.0) -> void:
	var min_pos_val = info.get("min", null)
	var max_pos_val = info.get("max", null)
	if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
		return
	var min_pos: Vector2i = min_pos_val
	var max_pos: Vector2i = max_pos_val

	var entrance_view: Vector2i = canvas._world_to_view(anchor)
	if entrance_view.x < min_pos.x or entrance_view.x > max_pos.x or entrance_view.y < min_pos.y or entrance_view.y > max_pos.y:
		return

	var r := Rect2(Vector2(entrance_view.x * cell_size, entrance_view.y * cell_size), Vector2(cell_size, cell_size))
	var pad := maxf(2.0, float(cell_size) * 0.12)
	var thickness := maxf(1.0, float(cell_size) * 0.06)
	var length := float(cell_size) * 0.32
	if length <= thickness:
		length = thickness + 1.0

	var is_left := entrance_view.x <= min_pos.x
	var is_right := entrance_view.x >= max_pos.x
	var is_top := entrance_view.y <= min_pos.y
	var is_bottom := entrance_view.y >= max_pos.y

	var col := Color(0, 0, 0, 0.9 * clampf(alpha, 0.0, 1.0))
	if is_top and is_left:
		canvas.draw_rect(Rect2(r.position + Vector2(pad, pad), Vector2(length, thickness)), col, true)
		canvas.draw_rect(Rect2(r.position + Vector2(pad, pad), Vector2(thickness, length)), col, true)
	elif is_top and is_right:
		canvas.draw_rect(Rect2(r.position + Vector2(r.size.x - pad - length, pad), Vector2(length, thickness)), col, true)
		canvas.draw_rect(Rect2(r.position + Vector2(r.size.x - pad - thickness, pad), Vector2(thickness, length)), col, true)
	elif is_bottom and is_left:
		canvas.draw_rect(Rect2(r.position + Vector2(pad, r.size.y - pad - thickness), Vector2(length, thickness)), col, true)
		canvas.draw_rect(Rect2(r.position + Vector2(pad, r.size.y - pad - length), Vector2(thickness, length)), col, true)
	elif is_bottom and is_right:
		canvas.draw_rect(Rect2(r.position + Vector2(r.size.x - pad - length, r.size.y - pad - thickness), Vector2(length, thickness)), col, true)
		canvas.draw_rect(Rect2(r.position + Vector2(r.size.x - pad - thickness, r.size.y - pad - length), Vector2(thickness, length)), col, true)

static func _draw_house_and_garden(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, alpha: float = 1.0) -> void:
	var min_pos_val = info.get("min", null)
	var max_pos_val = info.get("max", null)
	if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
		return
	var min_pos: Vector2i = min_pos_val
	var max_pos: Vector2i = max_pos_val
	var size_cells := (max_pos - min_pos) + Vector2i.ONE

	var rotation: int = int(info.get("rotation", 0))
	var house_tex: Texture2D = canvas._skin.get_piece_texture("house")
	var garden_tex: Texture2D = canvas._skin.get_piece_texture("garden_large")

	# 计算“房屋主体”的 2x2 占地（考虑 rotation；anchor 不一定是左上角）
	var house_mask := [[1, 1], [1, 1]]
	var house_cells_world: Array[Vector2i] = MapUtils.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
	var house_min := Vector2i(2147483647, 2147483647)
	var house_max := Vector2i(-2147483648, -2147483648)
	var house_cell_set := {}
	for wpos in house_cells_world:
		var vpos: Vector2i = canvas._world_to_view(wpos)
		house_cell_set[vpos] = true
		house_min.x = min(house_min.x, vpos.x)
		house_min.y = min(house_min.y, vpos.y)
		house_max.x = max(house_max.x, vpos.x)
		house_max.y = max(house_max.y, vpos.y)

	var house_size_cells := (house_max - house_min) + Vector2i.ONE
	var house_rect := Rect2(Vector2(house_min.x * cell_size, house_min.y * cell_size), Vector2(house_size_cells.x * cell_size, house_size_cells.y * cell_size))

	# 底色：房屋
	var house_bg := Color("#733651")
	house_bg.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(house_rect, house_bg, true)

	# 底色：花园（绿，仅 house_with_garden）
	var garden_rect := Rect2()
	var has_garden := str(info.get("piece_id", "")) == "house_with_garden"
	if has_garden:
		var garden_min := Vector2i(2147483647, 2147483647)
		var garden_max := Vector2i(-2147483648, -2147483648)
		var any := false
		for y in range(min_pos.y, max_pos.y + 1):
			for x in range(min_pos.x, max_pos.x + 1):
				var v := Vector2i(x, y)
				if house_cell_set.has(v):
					continue
				any = true
				garden_min.x = min(garden_min.x, v.x)
				garden_min.y = min(garden_min.y, v.y)
				garden_max.x = max(garden_max.x, v.x)
				garden_max.y = max(garden_max.y, v.y)
		if any:
			var garden_size_cells := (garden_max - garden_min) + Vector2i.ONE
			garden_rect = Rect2(Vector2(garden_min.x * cell_size, garden_min.y * cell_size), Vector2(garden_size_cells.x * cell_size, garden_size_cells.y * cell_size))
			var garden_bg := Color("#22C55E")
			garden_bg.a = 0.30 * clampf(alpha, 0.0, 1.0)
			canvas.draw_rect(garden_rect, garden_bg, true)

	# 贴图：房屋主体
	var bottom_gap := maxf(2.0, float(cell_size) * 0.10)
	var house_tex_rect := Rect2(house_rect.position, house_rect.size)
	house_tex_rect.size.y = maxf(0.0, house_tex_rect.size.y - bottom_gap)
	_draw_texture_aspect_fit(canvas, house_tex, house_tex_rect, Color(1, 1, 1, 0.9 * alpha), "bottom")

	# 贴图：花园围栏
	if has_garden and garden_rect.size != Vector2.ZERO:
		_draw_texture_aspect_fit(canvas, garden_tex, garden_rect, Color(1, 1, 1, 0.9 * alpha))

	# 房屋 ID：右上角（仅房屋 2x2 区域）
	var house_id: String = str(info.get("house_id", ""))
	_draw_house_id(canvas, cell_size, house_rect, house_id)

static func _draw_house_id(canvas, cell_size: int, structure_rect: Rect2, house_id) -> void:
	var text := str(house_id).strip_edges()
	if text.is_empty():
		return
	var pad := maxf(3.0, float(cell_size) * 0.12)
	var font_size := maxi(11, int(round(float(cell_size) * 0.34)))
	var label_rect := _compute_house_id_rect(cell_size, structure_rect)

	var font: Font = ThemeDB.fallback_font
	var baseline := label_rect.position + Vector2(0.0, label_rect.size.y - pad)
	canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(0, 0, 0, 0.85))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(1, 1, 1, 1))

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
		_draw_texture_aspect_fit(canvas, tex, Rect2(icon_pos, icon_size), Color(1, 1, 1, 0.8))

		var product_id: String = str(p.get("product", ""))
		if not product_id.is_empty():
			var product_tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)
			var badge_size := rect.size * 0.35
			var badge_pos := rect.position + Vector2(rect.size.x - badge_size.x - 2.0, 2.0)
			_draw_texture_aspect_fit(canvas, product_tex, Rect2(badge_pos, badge_size))

static func _draw_house_demands(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	if not canvas._map_data.has("houses") or not (canvas._map_data["houses"] is Dictionary):
		return

	var icon_size := float(cell_size) * 0.40
	var min_spacing := float(cell_size) * 0.08

	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = canvas._structures_by_anchor[anchor]

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

		var min_pos_val = info.get("min", null)
		var max_pos_val = info.get("max", null)
		if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
			continue
		var min_pos: Vector2i = min_pos_val
		var max_pos: Vector2i = max_pos_val
		var size_cells := (max_pos - min_pos) + Vector2i.ONE
		var structure_rect := Rect2(
			Vector2(min_pos.x * cell_size, min_pos.y * cell_size),
			Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
		)

		var demand_area_rect := structure_rect
		var rotation: int = int(info.get("rotation", 0))
		var house_mask := [[1, 1], [1, 1]]
		var house_cells_world: Array[Vector2i] = MapUtils.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
		if not house_cells_world.is_empty():
			var hmin := Vector2i(2147483647, 2147483647)
			var hmax := Vector2i(-2147483648, -2147483648)
			for wpos in house_cells_world:
				var vpos: Vector2i = canvas._world_to_view(wpos)
				hmin.x = min(hmin.x, vpos.x)
				hmin.y = min(hmin.y, vpos.y)
				hmax.x = max(hmax.x, vpos.x)
				hmax.y = max(hmax.y, vpos.y)
			var hsize_cells := (hmax - hmin) + Vector2i.ONE
			demand_area_rect = Rect2(Vector2(hmin.x * cell_size, hmin.y * cell_size), Vector2(hsize_cells.x * cell_size, hsize_cells.y * cell_size))

		var product_ids: Array[String] = []
		for d_val in demands:
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			var product_id: String = str(d.get("product", ""))
			if product_id.is_empty():
				continue
			product_ids.append(product_id)
		if product_ids.is_empty():
			continue
		product_ids.sort()
		var count: int = min(product_ids.size(), 6)

		var seed := _compute_demand_scatter_seed(canvas, house_id)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		rng.state = int(seed)

		var scatter_area_rect := demand_area_rect.grow(-float(cell_size) * 0.15)
		if scatter_area_rect.size.x < icon_size or scatter_area_rect.size.y < icon_size:
			scatter_area_rect = demand_area_rect

		var taken: Array[Rect2] = []
		if not house_id.is_empty():
			taken.append(_compute_house_id_rect(cell_size, demand_area_rect))

		for i in range(count):
			var product_id: String = product_ids[i]
			if product_id.is_empty():
				continue
			var tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)
			var icon_rect := _find_scatter_rect(rng, taken, scatter_area_rect, icon_size, min_spacing, i)
			taken.append(icon_rect)
			_draw_texture_aspect_fit(canvas, tex, icon_rect, Color(1, 1, 1, 0.95))

static func _draw_selection(canvas, cell_size: int) -> void:
	if canvas._is_valid_world_pos(canvas._selected_pos):
		var v = canvas._world_to_view(canvas._selected_pos)
		var rect := Rect2(Vector2(v.x * cell_size, v.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, Color(0.2, 0.8, 1.0, 0.9), false, 2.0)
	if canvas._is_valid_world_pos(canvas._hover_pos):
		var v2 = canvas._world_to_view(canvas._hover_pos)
		var rect2 := Rect2(Vector2(v2.x * cell_size, v2.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect2, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

static func _draw_tile_borders(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	var tps_val = canvas._map_data.get("tile_placements", null)
	if not (tps_val is Array):
		return
	var tps: Array = tps_val
	if tps.is_empty():
		return

	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return

	var thickness := maxf(1.5, float(cell_size) * 0.05)
	thickness = minf(thickness, float(cell_size))
	var col := Color(0, 0, 0, 0.9)

	var show_tile_ids := false
	if Globals != null:
		show_tile_ids = bool(Globals.show_tile_ids)

	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(10, int(round(float(cell_size) * 0.28)))
	var pad := maxf(2.0, float(cell_size) * 0.12)

	for tp_val in tps:
		if not (tp_val is Dictionary):
			continue
		var tp: Dictionary = tp_val
		var board_pos_val = tp.get("board_pos", null)
		if not (board_pos_val is Vector2i):
			continue
		var board_pos: Vector2i = board_pos_val
		var world_min := board_pos * tile_size
		var vmin = canvas._world_to_view(world_min)
		var rect := Rect2(
			Vector2(vmin.x * cell_size, vmin.y * cell_size),
			Vector2(tile_size * cell_size, tile_size * cell_size)
		)

		# 向内黑边框（允许覆盖道路/建筑）
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, thickness)), col, true)
		canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - thickness), Vector2(rect.size.x, thickness)), col, true)
		canvas.draw_rect(Rect2(rect.position, Vector2(thickness, rect.size.y)), col, true)
		canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - thickness, 0), Vector2(thickness, rect.size.y)), col, true)

		if not show_tile_ids:
			continue
		var tile_id := str(tp.get("tile_id", "")).strip_edges()
		if tile_id.is_empty():
			continue
		var rotation := int(tp.get("rotation", 0)) % 360

		var align := HORIZONTAL_ALIGNMENT_LEFT
		match rotation:
			90:
				align = HORIZONTAL_ALIGNMENT_RIGHT
			180:
				align = HORIZONTAL_ALIGNMENT_RIGHT
			270:
				align = HORIZONTAL_ALIGNMENT_LEFT
			_:
				align = HORIZONTAL_ALIGNMENT_LEFT

		var baseline_y := rect.position.y + pad + float(font_size)
		if rotation == 180 or rotation == 270:
			baseline_y = rect.position.y + rect.size.y - pad
		var baseline := Vector2(rect.position.x + pad, baseline_y)
		var width := rect.size.x - pad * 2.0
		canvas.draw_string(font, baseline + Vector2(1, 1), tile_id, align, width, font_size, Color(0, 0, 0, 0.85))
		canvas.draw_string(font, baseline, tile_id, align, width, font_size, Color(1, 1, 1, 1))
