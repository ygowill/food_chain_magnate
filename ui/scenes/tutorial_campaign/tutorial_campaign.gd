class_name TutorialCampaignScene
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const RESERVE_CARD_ART_SIZE := Vector2(140, 218)
const MAP_PREVIEW_SIZE := Vector2(680, 380)
const MAP_SELECTED_FILL := Color(0.95, 0.25, 0.18, 0.22)
const MAP_SELECTED_BORDER := Color(0.80, 0.18, 0.12, 0.92)
const MAP_VALID_FILL := Color(0.20, 0.75, 0.36, 0.20)
const MAP_VALID_BORDER := Color(0.20, 0.62, 0.28, 0.92)
const MAP_DISTANCE_FILL := Color(0.97, 0.73, 0.18, 0.42)
const MAP_DISTANCE_BORDER := Color(0.65, 0.38, 0.05, 0.95)
const MAP_GROUND_COLOR := Color("#faf4da")
const TILE_SIZE := 5
const TILE_CONTENT_PATH_TEMPLATE := "res://modules/base_tiles/content/tiles/%s.json"

const FALLBACK_RESERVE_CARDS := [
	{"cash": 50, "ceo_slots": 2},
	{"cash": 100, "ceo_slots": 3},
	{"cash": 150, "ceo_slots": 4},
]

class RealAssetMapPreview:
	extends Control

	const CELL_SIZE := 54
	const GRID_SIZE := Vector2i(10, 5)
	const GROUND_COLOR := Color("#faf4da")
	const ROAD_STRAIGHT_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_straight_new.png"
	const ROAD_CORNER_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_corner_new.png"
	const ROAD_TEE_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_tee_new.png"
	const ROAD_CROSS_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_cross_new.png"
	const ROAD_BRIDGE_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/bridge_default_new.png"
	const HOUSE_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/house.png"
	const GARDEN_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/garden_large.png"
	const RESTAURANT_LOGOS := [
		"res://modules/base_pieces/assets/map/logos/fried_geese_donkey.png",
		"res://modules/base_pieces/assets/map/logos/gluttony_inc_burgers.png",
		"res://modules/base_pieces/assets/map/logos/golden_duck_diner.png",
		"res://modules/base_pieces/assets/map/logos/santa_maria_pizza.png",
	]
	const HOUSE_BG_COLOR := Color("#733651")
	const GARDEN_BG_COLOR := Color("#699055")
	const RESTAURANT_BG_COLOR := Color("#f4edd1")
	const BOARD_EDGE_COLOR := Color("#2f261f")
	const BOARD_SHADOW_COLOR := Color(0, 0, 0, 0.22)

	var preview_state: Dictionary = {}
	var preview_options: Dictionary = {}
	var textures: Dictionary = {}

	func setup(state_data: Dictionary, options: Dictionary) -> void:
		preview_state = state_data.duplicate(true)
		preview_options = options.duplicate(true)
		custom_minimum_size = Vector2(GRID_SIZE.x * CELL_SIZE, GRID_SIZE.y * CELL_SIZE)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_load_textures()
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _load_textures() -> void:
		textures["road_straight"] = _load_texture_raw(ROAD_STRAIGHT_TEXTURE_PATH)
		textures["road_corner"] = _load_texture_raw(ROAD_CORNER_TEXTURE_PATH)
		textures["road_tee"] = _load_texture_raw(ROAD_TEE_TEXTURE_PATH)
		textures["road_cross"] = _load_texture_raw(ROAD_CROSS_TEXTURE_PATH)
		textures["road_bridge"] = _load_texture_raw(ROAD_BRIDGE_TEXTURE_PATH)
		textures["house"] = _load_texture_raw(HOUSE_TEXTURE_PATH)
		textures["garden_large"] = _load_texture_raw(GARDEN_TEXTURE_PATH)
		for i in range(RESTAURANT_LOGOS.size()):
			textures["logo_%d" % i] = _load_texture_raw(str(RESTAURANT_LOGOS[i]))

	static func _load_texture_raw(path: String) -> Texture2D:
		var raw_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
		var img := Image.load_from_file(raw_path)
		if img == null or img.is_empty():
			return null
		return ImageTexture.create_from_image(img)

	func _draw() -> void:
		_draw_cells()
		_draw_tile_boundary()
		_draw_option_overlays()
		_draw_houses()
		_draw_restaurants()
		_draw_structure_preview()

	func _draw_cells() -> void:
		for y in range(GRID_SIZE.y):
			for x in range(GRID_SIZE.x):
				var rect := _cell_rect(Vector2i(x, y))
				draw_rect(rect, GROUND_COLOR, true)
				_draw_road_segments(Vector2i(x, y), rect, _get_road_segments(Vector2i(x, y)))
				draw_rect(rect, Color(0.17, 0.13, 0.09, 0.14), false, 1.0)

	func _get_road_segments(pos: Vector2i) -> Array:
		var road_map_val = preview_state.get("road_segments", {})
		if not (road_map_val is Dictionary):
			return []
		var road_map: Dictionary = road_map_val
		var segments_val = road_map.get(pos, [])
		return segments_val if (segments_val is Array) else []

	func _draw_road_segments(_pos: Vector2i, rect: Rect2, segments: Array) -> void:
		if segments.is_empty():
			return
		var has_bridge := false
		for seg_val in segments:
			if seg_val is Dictionary and bool((seg_val as Dictionary).get("bridge", false)):
				has_bridge = true
				break
		var segments_to_draw: Array = []
		if has_bridge:
			for seg_val in segments:
				if seg_val is Dictionary and bool((seg_val as Dictionary).get("bridge", false)):
					segments_to_draw.append(seg_val)
		else:
			segments_to_draw = segments

		var center := rect.position + rect.size * 0.5
		for seg_index in range(segments_to_draw.size()):
			var seg_val = segments_to_draw[seg_index]
			if not (seg_val is Dictionary):
				continue
			var seg: Dictionary = seg_val
			var dirs_val = seg.get("dirs", [])
			if not (dirs_val is Array):
				continue
			var shape_info := _compute_road_shape_info(dirs_val)
			if shape_info.is_empty():
				continue
			var shape := str(shape_info.get("shape", "straight"))
			var tex_key := "road_bridge" if bool(seg.get("bridge", false)) else "road_%s" % shape
			var tex: Texture2D = textures.get(tex_key, null)
			if tex == null and shape == "end":
				tex = textures.get("road_straight", null)
			var margin := 0.0 if seg_index == 0 else 1.0
			var size := rect.size - Vector2(margin * 2.0, margin * 2.0)
			var offset := Vector2.ZERO if seg_index == 0 else Vector2(0.8, 0.8) * float(seg_index)
			if tex == null:
				draw_rect(Rect2(rect.position + offset, size).grow(-8), Color(0.42, 0.40, 0.35, 1.0), true)
				continue
			draw_set_transform(center + offset, deg_to_rad(float(shape_info.get("rotation_deg", 0))), Vector2.ONE)
			draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _compute_road_shape_info(dirs: Array) -> Dictionary:
		if dirs.is_empty():
			return {"shape": "straight", "rotation_deg": 0}
		var set := {}
		var unique: Array[String] = []
		for dir_val in dirs:
			var dir := str(dir_val).strip_edges()
			if dir.is_empty() or set.has(dir):
				continue
			set[dir] = true
			unique.append(dir)
		var n := unique.size()
		if n <= 0:
			return {"shape": "straight", "rotation_deg": 0}
		if n == 1:
			match unique[0]:
				"N":
					return {"shape": "end", "rotation_deg": 180}
				"S":
					return {"shape": "end", "rotation_deg": 0}
				"E":
					return {"shape": "end", "rotation_deg": 270}
				"W":
					return {"shape": "end", "rotation_deg": 90}
				_:
					return {"shape": "end", "rotation_deg": 0}
		if n == 2:
			var a := unique[0]
			var b := unique[1]
			var opp := (a == "N" and b == "S") or (a == "S" and b == "N") or (a == "E" and b == "W") or (a == "W" and b == "E")
			if opp:
				if (a == "N" and b == "S") or (a == "S" and b == "N"):
					return {"shape": "straight", "rotation_deg": 0}
				return {"shape": "straight", "rotation_deg": 90}
			if set.has("N") and set.has("E"):
				return {"shape": "corner", "rotation_deg": 180}
			if set.has("E") and set.has("S"):
				return {"shape": "corner", "rotation_deg": 270}
			if set.has("S") and set.has("W"):
				return {"shape": "corner", "rotation_deg": 0}
			if set.has("W") and set.has("N"):
				return {"shape": "corner", "rotation_deg": 90}
			return {"shape": "corner", "rotation_deg": 0}
		if n == 3:
			if not set.has("E"):
				return {"shape": "tee", "rotation_deg": 0}
			if not set.has("S"):
				return {"shape": "tee", "rotation_deg": 90}
			if not set.has("W"):
				return {"shape": "tee", "rotation_deg": 180}
			if not set.has("N"):
				return {"shape": "tee", "rotation_deg": 270}
			return {"shape": "tee", "rotation_deg": 0}
		return {"shape": "cross", "rotation_deg": 0}

	func _draw_tile_boundary() -> void:
		var x := float(5 * CELL_SIZE)
		draw_line(Vector2(x, 0), Vector2(x, GRID_SIZE.y * CELL_SIZE), Color(0.17, 0.13, 0.09, 0.75), 4.0)

	func _draw_option_overlays() -> void:
		var overlays_val = preview_options.get("overlays", [])
		if not (overlays_val is Array):
			return
		for overlay_val in overlays_val:
			if not (overlay_val is Dictionary):
				continue
			var overlay: Dictionary = overlay_val
			var style: Dictionary = overlay.get("style", {})
			var fill: Color = style.get("fill", Color(1, 1, 1, 0))
			var border: Color = style.get("border", Color(1, 1, 1, 0))
			var border_width := float(style.get("border_width", 2.0))
			var cells_val = overlay.get("cells", [])
			if not (cells_val is Array):
				continue
			for cell_val in cells_val:
				if cell_val is Vector2i:
					var cell_pos: Vector2i = cell_val
					var rect := _cell_rect(cell_pos)
					draw_rect(rect, fill, true)
					draw_rect(rect, border, false, border_width)

	func _draw_restaurants() -> void:
		var restaurants_val = preview_state.get("restaurants", [])
		if not (restaurants_val is Array):
			return
		for restaurant_val in restaurants_val:
			if not (restaurant_val is Dictionary):
				continue
			var restaurant: Dictionary = restaurant_val
			_draw_restaurant(
				restaurant.get("anchor", Vector2i.ZERO),
				int(restaurant.get("owner", 0)),
				Color(1, 1, 1, 1),
				true,
				restaurant
			)

	func _draw_houses() -> void:
		var houses_val = preview_state.get("houses", [])
		if not (houses_val is Array):
			return
		for house_val in houses_val:
			if not (house_val is Dictionary):
				continue
			var house: Dictionary = house_val
			_draw_house(house)

	func _draw_structure_preview() -> void:
		var preview_val = preview_options.get("structure_preview", null)
		if not (preview_val is Dictionary):
			return
		var preview: Dictionary = preview_val
		var info: Dictionary = preview.get("info", {})
		var anchor: Vector2i = info.get("anchor", Vector2i.ZERO)
		var owner := int(info.get("owner", 0))
		var valid := bool(preview.get("valid", true))
		_draw_restaurant(anchor, owner, Color(1, 1, 1, 0.72), valid, info)

	func _draw_restaurant(anchor_val, owner: int, modulate: Color, valid: bool, info: Dictionary) -> void:
		var anchor: Vector2i = anchor_val if anchor_val is Vector2i else Vector2i.ZERO
		var cells := _restaurant_cells(anchor)
		var rect := _rect_for_cells(cells)
		_draw_board_piece_background(rect, RESTAURANT_BG_COLOR, modulate.a)
		var logo: Texture2D = textures.get("logo_%d" % abs(owner % RESTAURANT_LOGOS.size()), null)
		if logo != null:
			_draw_texture_aspect_fit(logo, rect.grow(-maxf(2.0, float(CELL_SIZE) * 0.10)), Color(1, 1, 1, 0.98 * modulate.a))
		_draw_board_piece_surface_lines(rect, modulate.a)
		var drive_thru := bool(info.get("drive_thru", false))
		_draw_restaurant_entrance_marker(anchor, cells, modulate.a, drive_thru)
		if not valid:
			draw_rect(rect, Color(0.84, 0.12, 0.10, 0.22), true)
			draw_rect(rect, Color(0.84, 0.12, 0.10, 0.95), false, 4.0)

	func _draw_house(anchor_val) -> void:
		var info: Dictionary = anchor_val if (anchor_val is Dictionary) else {}
		var anchor_val2 = info.get("anchor", anchor_val)
		var anchor: Vector2i = anchor_val2 if anchor_val2 is Vector2i else Vector2i.ZERO
		var house_cells := _restaurant_cells(anchor)
		var garden_cells := _get_garden_cells(info, anchor)
		var all_cells: Array[Vector2i] = []
		all_cells.append_array(house_cells)
		all_cells.append_array(garden_cells)
		var house_rect := _rect_for_cells(house_cells)
		var structure_rect := _rect_for_cells(all_cells)

		_draw_board_piece_shadow(structure_rect, 1.0)
		_draw_board_piece_fill(house_rect, HOUSE_BG_COLOR, 1.0)
		if not garden_cells.is_empty():
			_draw_board_piece_fill(_rect_for_cells(garden_cells), GARDEN_BG_COLOR, 1.0)
		_draw_board_piece_bevel(structure_rect, HOUSE_BG_COLOR, 1.0)

		var house_tex: Texture2D = textures.get("house", null)
		if house_tex != null:
			var bottom_gap := maxf(2.0, float(CELL_SIZE) * 0.10)
			var house_pad := maxf(2.0, float(CELL_SIZE) * 0.08)
			var house_tex_rect := house_rect.grow(-house_pad)
			house_tex_rect.size.y = maxf(0.0, house_tex_rect.size.y - bottom_gap)
			_draw_texture_aspect_fit(house_tex, house_tex_rect, Color(1, 1, 1, 0.9), "bottom")
		else:
			draw_rect(house_rect.grow(-5), Color(0.78, 0.23, 0.18, 1.0), true)
		if not garden_cells.is_empty():
			var garden_tex: Texture2D = textures.get("garden_large", null)
			var garden_rect := _rect_for_cells(garden_cells).grow(-maxf(2.0, float(CELL_SIZE) * 0.08))
			if garden_tex != null:
				if garden_rect.size.y > garden_rect.size.x:
					_draw_texture_aspect_fit_rotated(garden_tex, garden_rect, 90.0, Color(1, 1, 1, 0.9))
				else:
					_draw_texture_aspect_fit(garden_tex, garden_rect, Color(1, 1, 1, 0.9))
		_draw_board_piece_surface_lines(structure_rect, 1.0)
		_draw_house_id(house_rect, str(info.get("house_number", info.get("house_id", ""))))

	func _restaurant_cells(anchor: Vector2i) -> Array[Vector2i]:
		return [
			anchor,
			anchor + Vector2i(1, 0),
			anchor + Vector2i(0, 1),
			anchor + Vector2i(1, 1),
		]

	func _get_garden_cells(info: Dictionary, anchor: Vector2i) -> Array[Vector2i]:
		var raw_cells = info.get("garden_cells", [])
		var out: Array[Vector2i] = []
		if raw_cells is Array:
			for cell_val in raw_cells:
				if cell_val is Vector2i:
					out.append(cell_val)
			if not out.is_empty():
				return out
		if str(info.get("piece_id", "house")) != "house_with_garden":
			return []
		var dir := str(info.get("garden_dir", "E")).strip_edges()
		match dir:
			"W":
				return [anchor + Vector2i(-2, 0), anchor + Vector2i(-1, 0)]
			"N":
				return [anchor + Vector2i(0, -1), anchor + Vector2i(1, -1)]
			"S":
				return [anchor + Vector2i(0, 2), anchor + Vector2i(1, 2)]
			_:
				return [anchor + Vector2i(2, 0), anchor + Vector2i(3, 0)]

	func _rect_for_cells(cells: Array[Vector2i]) -> Rect2:
		if cells.is_empty():
			return Rect2()
		var min_pos := Vector2i(2147483647, 2147483647)
		var max_pos := Vector2i(-2147483648, -2147483648)
		for cell_pos in cells:
			min_pos.x = mini(min_pos.x, cell_pos.x)
			min_pos.y = mini(min_pos.y, cell_pos.y)
			max_pos.x = maxi(max_pos.x, cell_pos.x)
			max_pos.y = maxi(max_pos.y, cell_pos.y)
		var size_cells := (max_pos - min_pos) + Vector2i.ONE
		return Rect2(Vector2(min_pos.x * CELL_SIZE, min_pos.y * CELL_SIZE), Vector2(size_cells.x * CELL_SIZE, size_cells.y * CELL_SIZE))

	func _draw_board_piece_shadow(rect: Rect2, alpha: float) -> void:
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return
		var offset := maxf(1.0, minf(6.0, float(CELL_SIZE) * 0.08))
		var shadow := BOARD_SHADOW_COLOR
		shadow.a *= clampf(alpha, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(offset, offset), rect.size), shadow, true)

	func _draw_board_piece_fill(rect: Rect2, fill_color: Color, alpha: float) -> void:
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return
		var face := fill_color
		face.a = clampf(alpha, 0.0, 1.0)
		draw_rect(rect, face, true)

	func _draw_board_piece_bevel(rect: Rect2, fill_color: Color, alpha: float) -> void:
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return
		var a := clampf(alpha, 0.0, 1.0)
		var edge := maxf(1.0, minf(5.0, float(CELL_SIZE) * 0.07))
		var highlight := fill_color.lightened(0.26)
		highlight.a = 0.48 * a
		var shade := Color("#4b3828")
		shade.a = 0.50 * a
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, edge)), highlight, true)
		draw_rect(Rect2(rect.position, Vector2(edge, rect.size.y)), highlight, true)
		draw_rect(Rect2(rect.position + Vector2(rect.size.x - edge, 0.0), Vector2(edge, rect.size.y)), shade, true)
		draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - edge), Vector2(rect.size.x, edge)), shade, true)

	func _draw_board_piece_background(rect: Rect2, fill_color: Color, alpha: float) -> void:
		_draw_board_piece_shadow(rect, alpha)
		_draw_board_piece_fill(rect, fill_color, alpha)
		_draw_board_piece_bevel(rect, fill_color, alpha)

	func _draw_board_piece_surface_lines(rect: Rect2, alpha: float) -> void:
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return
		var border := BOARD_EDGE_COLOR
		border.a = 0.82 * clampf(alpha, 0.0, 1.0)
		draw_rect(rect, border, false, maxf(1.0, minf(3.0, float(CELL_SIZE) * 0.045)))

	func _draw_texture_aspect_fit(texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1), v_align: String = "center") -> void:
		if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		var tex_size := texture.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return
		var scale := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
		var size := tex_size * scale
		var pos := rect.position + (rect.size - size) * 0.5
		if v_align == "top":
			pos.y = rect.position.y
		elif v_align == "bottom":
			pos.y = rect.position.y + rect.size.y - size.y
		draw_texture_rect(texture, Rect2(pos, size), false, modulate)

	func _draw_texture_aspect_fit_rotated(texture: Texture2D, rect: Rect2, rotation_degrees: float, modulate: Color = Color(1, 1, 1, 1)) -> void:
		if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		var tex_size := texture.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return
		var effective_size := Vector2(tex_size.y, tex_size.x)
		var scale := minf(rect.size.x / effective_size.x, rect.size.y / effective_size.y)
		var size := tex_size * scale
		var center := rect.position + rect.size * 0.5
		draw_set_transform(center, deg_to_rad(rotation_degrees), Vector2.ONE)
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_house_id(house_rect: Rect2, text: String) -> void:
		var label := str(text).strip_edges()
		if label.is_empty():
			return
		var pad := maxf(3.0, float(CELL_SIZE) * 0.10)
		var label_rect := Rect2(
			house_rect.position + Vector2(house_rect.size.x - float(CELL_SIZE) * 0.90 - pad, pad),
			Vector2(float(CELL_SIZE) * 0.90, float(CELL_SIZE) * 0.58)
		)
		var bg := Color(0, 0, 0, 0.48)
		draw_rect(label_rect, bg, true)
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(11, int(round(float(CELL_SIZE) * 0.34)))
		var baseline := label_rect.position + Vector2(0.0, label_rect.size.y - maxf(3.0, float(CELL_SIZE) * 0.12))
		draw_string(font, baseline + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(0, 0, 0, 0.85))
		draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(1, 1, 1, 1))

	func _draw_restaurant_entrance_marker(anchor: Vector2i, cells: Array[Vector2i], alpha: float, drive_thru: bool) -> void:
		if cells.is_empty():
			return
		if drive_thru:
			for cell_pos in cells:
				_draw_entrance_l_marker(cell_pos, cells, alpha)
			return
		_draw_entrance_l_marker(anchor, cells, alpha)

	func _draw_entrance_l_marker(entrance_view: Vector2i, cells: Array[Vector2i], alpha: float) -> void:
		var min_pos := Vector2i(2147483647, 2147483647)
		var max_pos := Vector2i(-2147483648, -2147483648)
		for cell_pos in cells:
			min_pos.x = mini(min_pos.x, cell_pos.x)
			min_pos.y = mini(min_pos.y, cell_pos.y)
			max_pos.x = maxi(max_pos.x, cell_pos.x)
			max_pos.y = maxi(max_pos.y, cell_pos.y)
		var rect := _cell_rect(entrance_view)
		var col := Color(0, 0, 0, 0.88 * alpha)
		var pad := maxf(2.0, float(CELL_SIZE) * 0.12)
		var thickness := maxf(1.0, float(CELL_SIZE) * 0.06)
		var length := float(CELL_SIZE) * 0.32
		var is_left := entrance_view.x <= min_pos.x
		var is_right := entrance_view.x >= max_pos.x
		var is_top := entrance_view.y <= min_pos.y
		var is_bottom := entrance_view.y >= max_pos.y
		if is_top and is_left:
			draw_rect(Rect2(rect.position + Vector2(pad, pad), Vector2(length, thickness)), col, true)
			draw_rect(Rect2(rect.position + Vector2(pad, pad), Vector2(thickness, length)), col, true)
		elif is_top and is_right:
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - pad - length, pad), Vector2(length, thickness)), col, true)
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - pad - thickness, pad), Vector2(thickness, length)), col, true)
		elif is_bottom and is_left:
			draw_rect(Rect2(rect.position + Vector2(pad, rect.size.y - pad - thickness), Vector2(length, thickness)), col, true)
			draw_rect(Rect2(rect.position + Vector2(pad, rect.size.y - pad - length), Vector2(thickness, length)), col, true)
		elif is_bottom and is_right:
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - pad - length, rect.size.y - pad - thickness), Vector2(length, thickness)), col, true)
			draw_rect(Rect2(rect.position + Vector2(rect.size.x - pad - thickness, rect.size.y - pad - length), Vector2(thickness, length)), col, true)

	func _cell_rect(pos: Vector2i) -> Rect2:
		return Rect2(Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))

const LESSONS := [
	{
		"id": "overview",
		"title": "1. 游戏背景与胜利目标",
		"kicker": "先知道自己在做什么",
		"summary": "你经营一家快餐公司，通过雇人、开店、定价、生产和广告，把地图上的需求转化成现金。默认规则下，游戏结束时现金最多的未弃权玩家获胜。",
	},
	{
		"id": "reserve_bank",
		"title": "2. 储备卡与银行",
		"kicker": "开局 Setup",
		"summary": "储备卡是开局暗选的银行保险，不是玩家收入。基础规则下，第一次破产会揭示所有玩家已选储备卡，按卡面向银行注资，并用已选卡决定之后的 CEO 直属槽位。",
	},
	{
		"id": "initial_restaurant",
		"title": "3. 起始餐厅放置",
		"kicker": "入口与板块",
		"summary": "起始餐厅必须入口邻接道路；起始放置阶段还要求每个地图板块最多只有一个餐厅入口。这个限制看入口所在板块，不看整个餐厅占地。",
	},
	{
		"id": "distance",
		"title": "4. 距离不是格子数",
		"kicker": "地图距离",
		"summary": "游戏里的道路距离以跨越地图板块边界的次数为主。道路步数只是辅助信息，不等于晚餐选店里使用的距离。",
	},
]

var _sidebar: VBoxContainer = null
var _lesson_title_label: Label = null
var _lesson_kicker_label: Label = null
var _lesson_summary_label: RichTextLabel = null
var _content_body: VBoxContainer = null
var _prev_button: Button = null
var _next_button: Button = null
var _lesson_buttons: Array[Button] = []

var _selected_lesson: int = 0
var _selected_reserve_index: int = 1
var _placement_case: String = "no_road"
var _distance_case: String = "same_board"

func _ready() -> void:
	GameLog.info("TutorialCampaign", "游戏介绍已加载")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	_build_shell()
	_select_lesson(0)

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.name = "WallBackground"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	bg.color = Color(0.90, 0.86, 0.75, 1.0)
	add_child(bg)
	UiStylesClass.apply_tiled_texture(bg, UiStylesClass.WALL_TEXTURE_PATHS, 3.0, Color(0.90, 0.86, 0.75, 1.0))

	var vignette := ColorRect.new()
	vignette.name = "VignetteOverlay"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	add_child(vignette)
	UiStylesClass.apply_vignette(vignette, 0.25, 0.5)

	var margin := MarginContainer.new()
	margin.name = "RootMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := HBoxContainer.new()
	root.name = "RootLayout"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	root.add_child(_build_sidebar_panel())
	root.add_child(_build_content_panel())

func _build_sidebar_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "LessonSidebarPanel"
	panel.custom_minimum_size = Vector2(310, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	_sidebar = VBoxContainer.new()
	_sidebar.add_theme_constant_override("separation", 10)
	pad.add_child(_sidebar)

	var title := Label.new()
	title.text = "游戏介绍"
	title.add_theme_font_size_override("font_size", 28)
	UiStylesClass.apply_label_dark(title)
	_sidebar.add_child(title)

	var hint := Label.new()
	hint.text = "规则说明"
	hint.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_hint_dark(hint)
	_sidebar.add_child(hint)

	var separator := HSeparator.new()
	_sidebar.add_child(separator)

	for i in range(LESSONS.size()):
		var lesson: Dictionary = LESSONS[i]
		var btn := Button.new()
		btn.text = str(lesson.get("title", "章节"))
		btn.custom_minimum_size = Vector2(0, 48)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_lesson.bind(i))
		UiStylesClass.apply_button_secondary(btn)
		_lesson_buttons.append(btn)
		_sidebar.add_child(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar.add_child(spacer)

	var back := Button.new()
	back.text = "返回主菜单"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_on_back_pressed)
	UiStylesClass.apply_button_secondary(back)
	_sidebar.add_child(back)

	return panel

func _build_content_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "LessonContentPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_panel_poster_alt(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	pad.add_child(vbox)

	_lesson_kicker_label = Label.new()
	_lesson_kicker_label.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_hint_dark(_lesson_kicker_label)
	vbox.add_child(_lesson_kicker_label)

	_lesson_title_label = Label.new()
	_lesson_title_label.add_theme_font_size_override("font_size", 30)
	_lesson_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_label_dark(_lesson_title_label)
	vbox.add_child(_lesson_title_label)

	_lesson_summary_label = _make_rich_text("", 70)
	vbox.add_child(_lesson_summary_label)

	var scroll := ScrollContainer.new()
	scroll.name = "LessonScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_content_body = VBoxContainer.new()
	_content_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_content_body)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	vbox.add_child(nav)

	_prev_button = Button.new()
	_prev_button.text = "上一节"
	_prev_button.custom_minimum_size = Vector2(140, 44)
	_prev_button.pressed.connect(_on_prev_pressed)
	UiStylesClass.apply_button_secondary(_prev_button)
	nav.add_child(_prev_button)

	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_spacer)

	_next_button = Button.new()
	_next_button.text = "下一节"
	_next_button.custom_minimum_size = Vector2(140, 44)
	_next_button.pressed.connect(_on_next_pressed)
	UiStylesClass.apply_button_primary(_next_button)
	nav.add_child(_next_button)

	return panel

func _select_lesson(index: int) -> void:
	_selected_lesson = clampi(index, 0, LESSONS.size() - 1)
	for i in range(_lesson_buttons.size()):
		var btn := _lesson_buttons[i]
		btn.disabled = i == _selected_lesson
		btn.text = str(LESSONS[i].get("title", "章节"))
	_render_lesson()

func _render_lesson() -> void:
	var lesson: Dictionary = LESSONS[_selected_lesson]
	_lesson_kicker_label.text = str(lesson.get("kicker", ""))
	_lesson_title_label.text = str(lesson.get("title", ""))
	_lesson_summary_label.text = str(lesson.get("summary", ""))
	_prev_button.disabled = _selected_lesson <= 0
	_next_button.disabled = _selected_lesson >= LESSONS.size() - 1

	_clear_content_body()
	match str(lesson.get("id", "")):
		"overview":
			_render_overview_lesson()
		"reserve_bank":
			_render_reserve_lesson()
		"initial_restaurant":
			_render_initial_restaurant_lesson()
		"distance":
			_render_distance_lesson()

func _clear_content_body() -> void:
	for child in _content_body.get_children():
		_content_body.remove_child(child)
		child.queue_free()

func _render_overview_lesson() -> void:
	var premise := _make_section("你经营什么")
	premise.add_child(_make_rich_text(
		"这是一局快餐连锁经营游戏。每位玩家代表一家餐厅公司，核心循环是：安排公司结构、用员工执行行动、生产食物饮料、开餐厅、投放广告，然后在晚餐阶段把房屋需求卖出去。\n\n餐厅数量、员工数量和广告覆盖都只是手段；最后真正比较的是玩家手里的现金。",
		145
	))
	_content_body.add_child(premise)

	var win := _make_section("胜利目标")
	win.add_child(_make_rich_text(
		"游戏结束时，未弃权玩家按现金从高到低排名，现金最多者获胜；现金相同则玩家编号靠前者排名靠前。\n\n最常见的终局来自银行破产：默认两次破产规则下，第一次破产后游戏继续；第二次破产会完成当前晚餐结算，然后跳过 Payday 进入最终排名。",
		145
	))
	_content_body.add_child(win)

	var phases := _make_section("一轮大致做什么")
	phases.add_child(_make_rich_text(
		"重组结构：决定哪些员工上班、哪些留在储备区。\n商业秩序：确定玩家行动顺序。\n工作时间：招聘、培训、生产、开店、定价、投放营销等。\n晚餐时间：房屋按需求、价格、距离等规则选择餐厅并购买。\nPayday / 营销 / 清理：支付薪水、结算广告持续时间、清理库存并进入下一轮。",
		170
	))
	_content_body.add_child(phases)

func _render_reserve_lesson() -> void:
	var card := _make_section("开局暗选")

	card.add_child(_make_rich_text(
		"银行是游戏的公共现金池，不属于任何玩家。晚餐销售收入、部分奖金等从银行付给玩家；Payday 发薪等玩家支出则会回到银行。储备卡只在银行破产时影响银行和公司结构，不会在开局直接变成玩家现金。",
		105
	))

	var row := HBoxContainer.new()
	row.name = "ReserveCardArtRow"
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var reserve_cards := _get_reserve_cards()
	for i in range(reserve_cards.size()):
		var reserve: Dictionary = reserve_cards[i]
		row.add_child(_build_reserve_card_choice(reserve, i, i == _selected_reserve_index))

	var selected_details := _describe_reserve_card(_selected_reserve_index)
	card.add_child(_make_label(
		"示例选择：%s。每位玩家在 Setup 的储备卡阶段秘密选择 1 张；确认后不可更改。选择结果在第一次破产前对其他玩家隐藏。" % str(selected_details.get("summary", "")),
		15,
		UiStylesClass.COLOR_TEXT_PRIMARY
	))
	card.add_child(_build_first_bankruptcy_case_card())
	card.add_child(_build_reserve_prices_variant_card())
	_content_body.add_child(card)

func _render_initial_restaurant_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "no_road", "label": "入口无路"},
		{"id": "same_board", "label": "入口板块冲突"},
		{"id": "valid", "label": "合法放置"},
	], _placement_case, Callable(self, "_on_placement_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("起始放置演示")
	var preview_state = _build_restaurant_preview_state(_placement_case)
	card.add_child(_build_real_map_preview(preview_state, _build_restaurant_preview_options(_placement_case)))
	card.add_child(_make_rich_text(_get_placement_explanation(_placement_case), 120))
	_content_body.add_child(card)

func _render_distance_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "same_board", "label": "同板块长路线"},
		{"id": "cross_board", "label": "跨板块短路线"},
	], _distance_case, Callable(self, "_on_distance_case_selected"))
	_content_body.add_child(controls)

	var card := _make_section("距离工具演示")
	var preview_state = _build_distance_preview_state(_distance_case)
	card.add_child(_build_real_map_preview(preview_state, _build_distance_preview_options(_distance_case)))
	if _distance_case == "same_board":
		card.add_child(_make_rich_text("同板块路线：示意路径都留在左侧板块内，没有跨过地图板块边界，所以规则距离 = 0。\n\n这就是为什么距离不能理解成格子数。晚餐选店使用的是跨板块次数。", 130))
	else:
		card.add_child(_make_rich_text("跨板块路线：示意路径穿过左、右两个板块之间的边界 1 次，所以规则距离 = 1。\n\n如果两家餐厅价格相同，这 1 点距离就可能改变房屋选择。", 130))
	_content_body.add_child(card)

func _get_reserve_cards() -> Array[Dictionary]:
	var fallback: Array[Dictionary] = []
	for card_val in FALLBACK_RESERVE_CARDS:
		if card_val is Dictionary:
			fallback.append((card_val as Dictionary).duplicate(true))
	return fallback

func _get_reserve_card(index: int) -> Dictionary:
	var cards := _get_reserve_cards()
	if cards.is_empty():
		return {}
	var idx := clampi(index, 0, cards.size() - 1)
	return cards[idx]

func _describe_reserve_card(index: int) -> Dictionary:
	return _describe_reserve_card_data(_get_reserve_card(index), index)

func _describe_reserve_card_data(card_data: Dictionary, index: int) -> Dictionary:
	var cash := int(card_data.get("cash", 0))
	var slots := int(card_data.get("ceo_slots", 0))
	if cash > 0 and slots > 0:
		return {
			"index": index,
			"title": "已选储备卡",
			"desc": "基础规则：银行注资 +$%d\n参与 CEO 槽位投票：%d" % [cash, slots],
			"summary": "选项#%d，基础规则下注资 $%d，CEO 槽位候选 %d" % [index + 1, cash, slots],
			"image_path": "res://assets/images/reserve_cards/reserve_%d.png" % (index + 2),
		}
	var price := int(card_data.get("type", 0))
	return {
		"index": index,
		"title": "已选储备卡",
		"desc": "储备价格扩展：基础单价候选 $%d\n首次破产后按多数决定" % price,
		"summary": "选项#%d，储备价格扩展候选 $%d" % [index + 1, price],
		"image_path": "res://assets/images/reserve_cards/reserve_%d.png" % (index + 2),
	}

func _build_reserve_card_choice(card_data: Dictionary, index: int, selected: bool) -> Control:
	var details := _describe_reserve_card_data(card_data, index)
	var panel := PanelContainer.new()
	panel.name = "ReserveCardChoice%d" % (index + 1)
	panel.custom_minimum_size = Vector2(190, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := Color(0.17, 0.13, 0.09, 0.24)
	var border_width := 1
	if selected:
		border = Color(0.73, 0.23, 0.18, 0.92)
		border_width = 3
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.92), border, border_width, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	vbox.add_child(_build_reserve_card_art(str(details.get("image_path", ""))))

	var title := Label.new()
	title.text = "选项 %d" % (index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	UiStylesClass.apply_label_dark(title)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = str(details.get("desc", "")).strip_edges()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	vbox.add_child(desc)

	return panel

func _build_reserve_card_art(image_path: String) -> Control:
	var frame := CenterContainer.new()
	frame.custom_minimum_size = RESERVE_CARD_ART_SIZE
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var image := TextureRect.new()
	image.custom_minimum_size = RESERVE_CARD_ART_SIZE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var raw_path := ProjectSettings.globalize_path(image_path) if image_path.begins_with("res://") else image_path
	var raw_image := Image.load_from_file(raw_path)
	if raw_image != null and not raw_image.is_empty():
		image.texture = ImageTexture.create_from_image(raw_image)
	else:
		image.modulate = Color(1, 1, 1, 0.35)
	frame.add_child(image)
	return frame

func _build_first_bankruptcy_case_card() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 22)

	var frame := PanelContainer.new()
	frame.name = "FirstBankruptcyCaseFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.95, 0.89, 0.76, 0.92), Color(0.17, 0.13, 0.09, 0.24), 1, 6))
	frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := _make_label("基础规则：第一次破产案例", 20, UiStylesClass.COLOR_TEXT_PRIMARY)
	vbox.add_child(title)

	var details := "假设银行只剩 $15，但当前晚餐需要向玩家支付 $20：\n"
	details += "1. 银行余额不足，触发第一次破产；如果某次支付后银行刚好变成 $0，也会立刻触发破产。\n"
	details += "2. 所有玩家翻开自己已选的储备卡。未选中的卡仍然不公开。\n"
	details += "3. 例：甲选第 2 张，银行注资 $100、CEO 槽位候选 3；乙选第 3 张，银行注资 $150、CEO 槽位候选 4。\n"
	details += "4. 银行先获得 $250 注资，余额从 $15 变为 $265，然后继续完成刚才那笔 $20 支付，支付后剩 $245；第一次破产不会立刻结束游戏。\n"
	details += "5. CEO 槽位按所有已选卡投票决定，票数相同取更大的槽位。本例 3 和 4 各一票，所以之后所有玩家的 CEO 直属槽位变为 4。"
	vbox.add_child(_make_rich_text(details, 140))

	var slot_note := _make_label(
		"槽位的作用：CEO 直属槽位决定 CEO 下面能直接放多少个员工或经理。经理员工再提供自己的下级槽位；如果重组时员工放不进结构，就只能留在储备区。",
		15,
		UiStylesClass.COLOR_TEXT_MUTED
	)
	vbox.add_child(slot_note)
	return frame

func _build_reserve_prices_variant_card() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 22)

	var frame := PanelContainer.new()
	frame.name = "ReservePricesVariantFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.92, 0.87, 0.76, 0.92), Color(0.17, 0.13, 0.09, 0.24), 1, 6))
	frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := _make_label("储备价格扩展：规则会替换", 20, UiStylesClass.COLOR_TEXT_PRIMARY)
	vbox.add_child(title)

	var details := "如果房间启用了 Reserve Prices / 储备价格扩展，第一次破产规则不是上面的基础规则：\n"
	details += "1. 开局储备卡改为 5 / 10 / 20 三种基础单价候选。\n"
	details += "2. 第一次破产时，银行固定注资 $200 × 玩家人数，不再按卡面现金相加。\n"
	details += "3. 这些卡不再改变 CEO 槽位；第一次破产不会因为储备卡投票去重设公司结构槽位。\n"
	details += "4. 所有玩家已选的 5 / 10 / 20 参与投票，出现最多的数值成为之后晚餐使用的基础单价；平票按 20 > 5 > 10 决胜。\n"
	details += "5. 第二次破产仍然是终局触发：完成当前晚餐结算后进入最终排名。"
	vbox.add_child(_make_rich_text(details, 160))
	return frame

func _build_preview_map_state(tile_ids: Array = []) -> Dictionary:
	var ids := tile_ids.duplicate()
	if ids.is_empty():
		ids = ["tile_a", "tile_b"]
	var state := {
		"road_segments": {},
		"houses": [],
		"restaurants": [],
	}
	for i in range(ids.size()):
		_apply_preview_tile(state, str(ids[i]), Vector2i(i * TILE_SIZE, 0))
	return state

func _apply_preview_tile(state: Dictionary, tile_id: String, origin: Vector2i) -> void:
	var tile_data := _load_json_dict(TILE_CONTENT_PATH_TEMPLATE % tile_id)
	if tile_data.is_empty():
		return

	var road_map: Dictionary = state.get("road_segments", {})
	var road_rows_val = tile_data.get("road_segments", [])
	if road_rows_val is Array:
		var road_rows: Array = road_rows_val
		for y in range(road_rows.size()):
			var row_val = road_rows[y]
			if not (row_val is Array):
				continue
			var row: Array = row_val
			for x in range(row.size()):
				var segments_val = row[x]
				if not (segments_val is Array):
					continue
				var segments: Array = segments_val
				if segments.is_empty():
					continue
				road_map[origin + Vector2i(x, y)] = segments.duplicate(true)
	state["road_segments"] = road_map

	var houses: Array = state.get("houses", [])
	var structures_val = tile_data.get("printed_structures", [])
	if structures_val is Array:
		for structure_val in structures_val:
			if not (structure_val is Dictionary):
				continue
			var structure: Dictionary = (structure_val as Dictionary).duplicate(true)
			var piece_id := str(structure.get("piece_id", "")).strip_edges()
			if piece_id != "house" and piece_id != "house_with_garden":
				continue
			var local_anchor := _variant_to_vector2i(structure.get("anchor", [0, 0]))
			structure["anchor"] = origin + local_anchor
			houses.append(structure)
	state["houses"] = houses

func _load_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _variant_to_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		var vec2: Vector2 = value
		return Vector2i(int(vec2.x), int(vec2.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

func _build_restaurant_preview_state(_case_id: String) -> Dictionary:
	var state := _build_preview_map_state()
	var restaurants: Array = state.get("restaurants", [])
	restaurants.append({"restaurant_id": "rest_demo_opponent", "owner": 1, "anchor": Vector2i(3, 3)})
	state["restaurants"] = restaurants
	return state

func _build_restaurant_preview_options(case_id: String) -> Dictionary:
	var preview_anchor := Vector2i(8, 3)
	var valid := true
	match case_id:
		"no_road":
			preview_anchor = Vector2i(5, 0)
			valid = false
		"same_board":
			preview_anchor = Vector2i(0, 3)
			valid = false
		_:
			preview_anchor = Vector2i(8, 3)
			valid = true
	var cells := _restaurant_cells_for_anchor(preview_anchor, 0)
	return {
		"structure_preview": {
			"cells": cells,
			"valid": valid,
			"info": {
				"piece_id": "restaurant",
				"anchor": preview_anchor,
				"owner": 0,
				"rotation": 0,
			},
		},
		"overlays": [
			{
				"id": "entry_board",
				"cells": _board_cells_for_world(preview_anchor),
				"style": {
					"fill": MAP_VALID_FILL if valid else MAP_SELECTED_FILL,
					"border": MAP_VALID_BORDER if valid else MAP_SELECTED_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _build_distance_preview_state(case_id: String) -> Dictionary:
	var state := _build_preview_map_state()
	var restaurants: Array = state.get("restaurants", [])
	if case_id == "same_board":
		restaurants.append({"restaurant_id": "rest_distance_a", "owner": 0, "anchor": Vector2i(0, 3)})
		restaurants.append({"restaurant_id": "rest_distance_b", "owner": 1, "anchor": Vector2i(3, 3)})
	else:
		restaurants.append({"restaurant_id": "rest_distance_a", "owner": 0, "anchor": Vector2i(3, 3)})
		restaurants.append({"restaurant_id": "rest_distance_b", "owner": 1, "anchor": Vector2i(8, 3)})
	state["restaurants"] = restaurants
	return state

func _build_distance_preview_options(case_id: String) -> Dictionary:
	var path: Array[Vector2i] = []
	if case_id == "same_board":
		path = [
			Vector2i(0, 2),
			Vector2i(1, 2),
			Vector2i(2, 2),
			Vector2i(2, 3),
		]
	else:
		path = [
			Vector2i(2, 3),
			Vector2i(2, 2),
			Vector2i(3, 2),
			Vector2i(4, 2),
			Vector2i(5, 2),
			Vector2i(6, 2),
			Vector2i(7, 2),
			Vector2i(7, 3),
		]
	return {
		"highlights": path,
		"overlays": [
			{
				"id": "distance_path",
				"cells": path,
				"style": {
					"fill": MAP_DISTANCE_FILL,
					"border": MAP_DISTANCE_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _restaurant_cells_for_anchor(anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	if rotation == 90 or rotation == 180 or rotation == 270:
		# 餐厅是 2x2，占地旋转后不变；入口教学统一用锚点角。
		pass
	for offset in offsets:
		cells.append(anchor + offset)
	return cells

func _board_cells_for_world(world_pos: Vector2i) -> Array[Vector2i]:
	var board_origin := Vector2i(floori(float(world_pos.x) / 5.0) * 5, floori(float(world_pos.y) / 5.0) * 5)
	var cells: Array[Vector2i] = []
	for y in range(5):
		for x in range(5):
			cells.append(board_origin + Vector2i(x, y))
	return cells

func _build_real_map_preview(state, options: Dictionary) -> Control:
	if state == null:
		var fallback := PanelContainer.new()
		fallback.custom_minimum_size = MAP_PREVIEW_SIZE
		fallback.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.92), Color(0.73, 0.23, 0.18, 0.65), 2, 6))
		var label := _make_label("真实地图预览暂不可用", 15, UiStylesClass.COLOR_TEXT_ERROR)
		fallback.add_child(label)
		return fallback

	var frame := PanelContainer.new()
	frame.name = "RealMapPreviewFrame"
	frame.custom_minimum_size = MAP_PREVIEW_SIZE
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(MAP_GROUND_COLOR, Color(0.17, 0.13, 0.09, 0.24), 1, 6))

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(center)

	var preview := RealAssetMapPreview.new()
	preview.setup(state if state is Dictionary else {}, options)
	center.add_child(preview)
	return frame

func _get_placement_explanation(case_id: String) -> String:
	match case_id:
		"no_road":
			return "非法原因：你的餐厅入口没有邻接道路。\n\n教学界面应直接指出“入口不邻接道路”，而不是只提示不能放置。"
		"same_board":
			return "非法原因：你的入口邻接道路，但入口所在板块已经有对手的起始餐厅入口。\n\n注意：这是起始放置专用限制。"
		_:
			return "合法原因：你的入口落在右侧板块，并且入口邻接道路；对手入口在左侧板块，所以起始入口板块不冲突。\n\n起始限制只看入口所在板块，不看整张地图是否已有其他餐厅。"

func _make_segmented_row(options: Array, active_id: String, callback: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for opt_val in options:
		var opt: Dictionary = opt_val
		var btn := Button.new()
		btn.text = str(opt.get("label", ""))
		btn.custom_minimum_size = Vector2(170, 42)
		var id := str(opt.get("id", ""))
		btn.disabled = id == active_id
		btn.pressed.connect(callback.bind(id))
		UiStylesClass.apply_button_secondary(btn)
		row.add_child(btn)
	return row

func _make_section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 21)
	UiStylesClass.apply_label_dark(label)
	section.add_child(label)
	return section

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_rich_text(text: String, min_height: int) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = false
	rich.text = text
	rich.fit_content = true
	rich.scroll_active = false
	rich.custom_minimum_size = Vector2(0, min_height)
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStylesClass.apply_rich_text_dark(rich)
	return rich

func _make_style(bg: Color, border: Color, width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _on_placement_case_selected(case_id: String) -> void:
	_placement_case = case_id
	_render_lesson()

func _on_distance_case_selected(case_id: String) -> void:
	_distance_case = case_id
	_render_lesson()

func _on_prev_pressed() -> void:
	_select_lesson(_selected_lesson - 1)

func _on_next_pressed() -> void:
	_select_lesson(_selected_lesson + 1)

func _on_back_pressed() -> void:
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()
