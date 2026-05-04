class_name TutorialCampaignScene
extends Control

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const PhaseTrackStripClass = preload("res://ui/components/phase_track/phase_track_strip.gd")

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
	const HOUSE_ID_FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.otf"
	const HOUSE_ID_LABEL_TEXTURE_PATHS := {
		"π": "res://assets/images/house_labels/pi.png",
		"9¾": "res://assets/images/house_labels/nine_three_quarters.png",
		"√2": "res://assets/images/house_labels/sqrt2.png",
	}
	const ROAD_STRAIGHT_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_straight_new.png"
	const ROAD_CORNER_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_corner_new.png"
	const ROAD_TEE_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_tee_new.png"
	const ROAD_CROSS_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/road_cross_new.png"
	const ROAD_BRIDGE_TEXTURE_PATH := "res://modules/base_tiles/assets/map/roads/bridge_default_new.png"
	const HOUSE_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/house.png"
	const GARDEN_TEXTURE_PATH := "res://modules/base_pieces/assets/map/pieces/garden_large.png"
	const APARTMENT_TEXTURE_PATH := "res://modules/new_districts/assets/map/pieces/apartment.png"
	const MARKETING_ICON_PATHS := {
		"default": "res://modules/base_marketing/assets/map/icons/marketing.png",
		"billboard": "res://modules/base_marketing/assets/map/icons/billboard.png",
		"mailbox": "res://modules/base_marketing/assets/map/icons/mailbox.png",
		"radio": "res://modules/base_marketing/assets/map/icons/radio.png",
		"airplane": "res://modules/base_marketing/assets/map/icons/airplane.png",
	}
	const PRODUCT_ICON_PATHS := {
		"burger": "res://modules/base_products/assets/map/icons/burger.png",
		"pizza": "res://modules/base_products/assets/map/icons/pizza.png",
		"soda": "res://modules/base_products/assets/map/icons/soda.png",
		"beer": "res://modules/base_products/assets/map/icons/beer.png",
		"lemonade": "res://modules/base_products/assets/map/icons/lemonade.png",
	}
	const DRINK_SOURCE_ICON_PATHS := {
		"soda": "res://modules/base_products/assets/map/drink_sources/soda.png",
		"beer": "res://modules/base_products/assets/map/drink_sources/beer.png",
		"lemonade": "res://modules/base_products/assets/map/drink_sources/lemonade.png",
	}
	const RESTAURANT_LOGOS := [
		"res://modules/base_pieces/assets/map/logos/fried_geese_donkey.png",
		"res://modules/base_pieces/assets/map/logos/gluttony_inc_burgers.png",
		"res://modules/base_pieces/assets/map/logos/golden_duck_diner.png",
		"res://modules/base_pieces/assets/map/logos/santa_maria_pizza.png",
	]
	const HOUSE_BG_COLOR := Color("#733651")
	const GARDEN_BG_COLOR := Color("#699055")
	const RESTAURANT_BG_COLOR := Color("#f4edd1")
	const MARKETING_BG_COLOR := Color("#98a295")
	const BOARD_EDGE_COLOR := Color("#2f261f")
	const BOARD_SHADOW_COLOR := Color(0, 0, 0, 0.22)

	var preview_state: Dictionary = {}
	var preview_options: Dictionary = {}
	var textures: Dictionary = {}
	var house_id_label_textures: Dictionary = {}
	var house_id_font: Font = null

	func setup(state_data: Dictionary, options: Dictionary) -> void:
		preview_state = state_data.duplicate(true)
		preview_options = options.duplicate(true)
		var margin := _preview_margin_cells()
		var margin_left := int(margin.get("left", 0))
		var margin_right := int(margin.get("right", 0))
		var margin_top := int(margin.get("top", 0))
		var margin_bottom := int(margin.get("bottom", 0))
		custom_minimum_size = Vector2(
			(GRID_SIZE.x + margin_left + margin_right) * CELL_SIZE,
			(GRID_SIZE.y + margin_top + margin_bottom) * CELL_SIZE
		)
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
		textures["apartment"] = _load_texture_raw(APARTMENT_TEXTURE_PATH)
		for key in MARKETING_ICON_PATHS.keys():
			textures["marketing_%s" % str(key)] = _load_texture_raw(str(MARKETING_ICON_PATHS[key]))
		for key2 in PRODUCT_ICON_PATHS.keys():
			textures["product_%s" % str(key2)] = _load_texture_raw(str(PRODUCT_ICON_PATHS[key2]))
		for key3 in DRINK_SOURCE_ICON_PATHS.keys():
			textures["drink_source_%s" % str(key3)] = _load_texture_raw(str(DRINK_SOURCE_ICON_PATHS[key3]))
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
		_draw_drink_sources()
		_draw_houses()
		_draw_restaurants()
		_draw_structure_preview()
		_draw_option_overlays()
		_draw_marketing()

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

	func _draw_drink_sources() -> void:
		var sources_val = preview_state.get("drink_sources", [])
		if not (sources_val is Array):
			return
		for source_val in sources_val:
			if not (source_val is Dictionary):
				continue
			var source: Dictionary = source_val
			var pos_read := _try_vector2i(source.get("world_pos", source.get("pos", null)))
			if not bool(pos_read.get("ok", false)):
				continue
			var product_id := str(source.get("type", source.get("product", ""))).strip_edges()
			if product_id == "cola":
				product_id = "soda"
			if product_id.is_empty():
				continue
			var rect := _cell_rect(pos_read["value"])
			var tex: Texture2D = textures.get("drink_source_%s" % product_id, null)
			if tex != null:
				_draw_texture_aspect_fit(tex, rect, Color(1, 1, 1, 0.95))
			else:
				draw_rect(rect.grow(-6), Color(0.35, 0.55, 0.88, 0.82), true)

	func _draw_tile_boundary() -> void:
		var origin := _board_origin_px()
		var x := origin.x + float(5 * CELL_SIZE)
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y + GRID_SIZE.y * CELL_SIZE), Color(0.17, 0.13, 0.09, 0.75), 4.0)

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

	func _draw_marketing() -> void:
		var placements_val = preview_state.get("marketing_placements", [])
		if not (placements_val is Array):
			return
		for placement_val in placements_val:
			if not (placement_val is Dictionary):
				continue
			var placement: Dictionary = placement_val
			_draw_marketing_placement(placement)

	func _draw_marketing_placement(placement: Dictionary) -> void:
		var type_id := str(placement.get("type", "default")).strip_edges()
		if type_id.is_empty():
			type_id = "default"
		var anchor_read := _try_vector2i(placement.get("world_pos", placement.get("anchor", null)))
		if not bool(anchor_read.get("ok", false)):
			return
		var anchor: Vector2i = anchor_read["value"]
		var base_size := _read_positive_size(placement.get("footprint_size", Vector2i.ONE), Vector2i.ONE)
		var rotation := int(placement.get("rotation", 0))
		var rect := _marketing_rect(anchor, type_id, base_size, rotation, str(placement.get("axis", "")).strip_edges())
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return

		_draw_board_piece_background(rect, MARKETING_BG_COLOR, 1.0)
		var tex: Texture2D = textures.get("marketing_%s" % type_id, textures.get("marketing_default", null))
		var icon_rect := rect.grow(-maxf(2.0, float(CELL_SIZE) * 0.08))
		if tex != null:
			if type_id == "airplane" and icon_rect.size.y > icon_rect.size.x:
				_draw_texture_aspect_fit_rotated(tex, icon_rect, 90.0, Color(1, 1, 1, 0.45))
			else:
				_draw_texture_aspect_fit(tex, icon_rect, Color(1, 1, 1, 0.45))
		_draw_board_piece_surface_lines(rect, 1.0)

		var board_number := int(placement.get("board_number", 0))
		if board_number > 0:
			_draw_marketing_board_number_badge(rect, board_number)
		var product_id := str(placement.get("product", "")).strip_edges()
		if not product_id.is_empty():
			_draw_marketing_product_icon(rect, product_id, int(placement.get("remaining_duration", 0)))

	func _marketing_rect(anchor: Vector2i, type_id: String, base_size: Vector2i, rotation: int, axis: String) -> Rect2:
		var size := base_size
		if type_id == "airplane":
			var length := 0
			var thickness := 2
			if base_size.x == 2 and base_size.y != 2:
				length = base_size.y
			elif base_size.y == 2 and base_size.x != 2:
				length = base_size.x
			else:
				thickness = mini(base_size.x, base_size.y)
				length = maxi(base_size.x, base_size.y)
			if axis == "row":
				size = Vector2i(maxi(1, thickness), maxi(1, length))
			else:
				size = Vector2i(maxi(1, length), maxi(1, thickness))
			var board_origin := _board_origin_px()
			var rect := Rect2(board_origin + Vector2(anchor.x * CELL_SIZE, anchor.y * CELL_SIZE), Vector2(size.x * CELL_SIZE, size.y * CELL_SIZE))
			if axis == "row":
				if anchor.x <= 0:
					rect.position.x = board_origin.x - rect.size.x
				else:
					rect.position.x = board_origin.x + GRID_SIZE.x * CELL_SIZE
			else:
				if anchor.y <= 0:
					rect.position.y = board_origin.y - rect.size.y
				else:
					rect.position.y = board_origin.y + GRID_SIZE.y * CELL_SIZE
			return rect

		if rotation == 90 or rotation == 270:
			size = Vector2i(base_size.y, base_size.x)
		var cells := _cells_in_rect(anchor, anchor + size - Vector2i.ONE)
		return _rect_for_cells(cells)

	func _read_positive_size(value, fallback: Vector2i) -> Vector2i:
		var read := _try_vector2i(value)
		if bool(read.get("ok", false)):
			var size: Vector2i = read["value"]
			if size.x > 0 and size.y > 0:
				return size
		return fallback

	func _draw_marketing_board_number_badge(rect: Rect2, board_number: int) -> void:
		var badge_size := maxf(18.0, float(CELL_SIZE) * 0.46)
		var pad := maxf(2.0, float(CELL_SIZE) * 0.06)
		var badge_rect := Rect2(rect.position + Vector2(rect.size.x - badge_size - pad, pad), Vector2(badge_size, badge_size))
		draw_circle(badge_rect.position + badge_rect.size * 0.5, badge_size * 0.5, Color(1, 1, 1, 0.92))
		draw_arc(badge_rect.position + badge_rect.size * 0.5, badge_size * 0.5, 0.0, TAU, 36, Color(0.12, 0.10, 0.08, 0.85), 1.5)
		var font: Font = ThemeDB.fallback_font
		var text := str(board_number)
		var font_size := maxi(10, int(round(badge_size * 0.54)))
		if text.length() >= 2:
			font_size = int(round(float(font_size) * 0.86))
		var baseline := badge_rect.position + Vector2(0.0, badge_rect.size.y * 0.69)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x, font_size, Color(0.08, 0.07, 0.06, 1.0))

	func _draw_marketing_product_icon(rect: Rect2, product_id: String, remaining_duration: int) -> void:
		var key := "soda" if product_id == "cola" else product_id
		var tex: Texture2D = textures.get("product_%s" % key, null)
		if tex == null:
			return
		var pad := maxf(4.0, float(CELL_SIZE) * 0.12)
		var avail := rect.size - Vector2(pad * 2.0, pad * 2.0)
		var size := minf(avail.x, avail.y) * 0.72
		var icon_rect := Rect2(rect.position + (rect.size - Vector2(size, size)) * 0.5, Vector2(size, size))
		_draw_texture_aspect_fit(tex, icon_rect, Color(1, 1, 1, 0.95))
		if remaining_duration == 0:
			return
		var text := "无限" if remaining_duration < 0 else str(remaining_duration)
		var font: Font = ThemeDB.fallback_font
		var font_size := maxi(10, int(round(size * 0.48)))
		var baseline := icon_rect.position + Vector2(0.0, icon_rect.size.y * 0.60)
		draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, icon_rect.size.x, font_size, Color(0, 0, 0, 0.85))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, icon_rect.size.x, font_size, Color(1, 1, 1, 1.0))

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
		var house_cells := _house_body_cells_for_info(info, anchor)
		var structure_cells := _structure_cells_for_info(info, anchor)
		var garden_cells := _get_garden_cells(info, anchor, house_cells, structure_cells)
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

		var piece_id := str(info.get("piece_id", "house")).strip_edges()
		var house_tex: Texture2D = textures.get("apartment", null) if piece_id == "apartment" else textures.get("house", null)
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
		_draw_house_id(house_rect, _format_house_display_label(info))

	func _house_body_cells_for_info(info: Dictionary, anchor: Vector2i) -> Array[Vector2i]:
		if str(info.get("piece_id", "")).strip_edges() == "apartment":
			var cells: Array[Vector2i] = []
			for y in range(3):
				for x in range(3):
					cells.append(anchor + Vector2i(x, y))
			return cells
		if str(info.get("piece_id", "")).strip_edges() == "house_with_garden":
			return _footprint_cells(anchor, Vector2i(2, 2), int(info.get("rotation", 0)))
		return _restaurant_cells(anchor)

	func _structure_cells_for_info(info: Dictionary, anchor: Vector2i) -> Array[Vector2i]:
		var piece_id := str(info.get("piece_id", "")).strip_edges()
		var house_cells := _house_body_cells_for_info(info, anchor)
		if piece_id != "house_with_garden":
			return house_cells

		var min_read := _try_vector2i(info.get("min", null))
		var max_read := _try_vector2i(info.get("max", null))
		if bool(min_read.get("ok", false)) and bool(max_read.get("ok", false)):
			var min_pos: Vector2i = min_read["value"]
			var max_pos: Vector2i = max_read["value"]
			return _cells_in_rect(min_pos, max_pos)

		var garden_cells := _get_raw_garden_cells(info)
		if garden_cells.is_empty():
			if info.has("garden_dir"):
				garden_cells = _garden_cells_for_direction(anchor, str(info.get("garden_dir", "E")).strip_edges())
			else:
				return _footprint_cells(anchor, Vector2i(3, 2), int(info.get("rotation", 0)))
		var all_cells: Array[Vector2i] = []
		all_cells.append_array(house_cells)
		all_cells.append_array(garden_cells)
		return all_cells

	func _footprint_cells(anchor: Vector2i, size: Vector2i, rotation: int) -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		for y in range(size.y):
			for x in range(size.x):
				cells.append(anchor + _rotate_offset(Vector2i(x, y), rotation))
		return cells

	func _rotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
		match rotation:
			90:
				return Vector2i(-offset.y, offset.x)
			180:
				return Vector2i(-offset.x, -offset.y)
			270:
				return Vector2i(offset.y, -offset.x)
			_:
				return offset

	func _try_vector2i(value) -> Dictionary:
		if value is Vector2i:
			return {"ok": true, "value": value}
		if value is Vector2:
			var vec: Vector2 = value
			return {"ok": true, "value": Vector2i(int(vec.x), int(vec.y))}
		if value is Array:
			var arr: Array = value
			if arr.size() >= 2:
				return {"ok": true, "value": Vector2i(int(arr[0]), int(arr[1]))}
		return {"ok": false, "value": Vector2i.ZERO}

	func _cells_in_rect(min_pos: Vector2i, max_pos: Vector2i) -> Array[Vector2i]:
		var cells: Array[Vector2i] = []
		var x0 := mini(min_pos.x, max_pos.x)
		var x1 := maxi(min_pos.x, max_pos.x)
		var y0 := mini(min_pos.y, max_pos.y)
		var y1 := maxi(min_pos.y, max_pos.y)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				cells.append(Vector2i(x, y))
		return cells

	func _restaurant_cells(anchor: Vector2i) -> Array[Vector2i]:
		return [
			anchor,
			anchor + Vector2i(1, 0),
			anchor + Vector2i(0, 1),
			anchor + Vector2i(1, 1),
		]

	func _get_raw_garden_cells(info: Dictionary) -> Array[Vector2i]:
		var raw_cells = info.get("garden_cells", [])
		var out: Array[Vector2i] = []
		if raw_cells is Array:
			for cell_val in raw_cells:
				if cell_val is Vector2i:
					out.append(cell_val)
				else:
					var read := _try_vector2i(cell_val)
					if bool(read.get("ok", false)):
						out.append(read["value"])
		return out

	func _get_garden_cells(info: Dictionary, anchor: Vector2i, house_cells: Array[Vector2i], structure_cells: Array[Vector2i]) -> Array[Vector2i]:
		var raw_cells := _get_raw_garden_cells(info)
		if not raw_cells.is_empty():
			return raw_cells
		if str(info.get("piece_id", "house")) != "house_with_garden":
			return []

		if not house_cells.is_empty() and not structure_cells.is_empty():
			var house_set := {}
			for house_cell in house_cells:
				house_set[house_cell] = true
			var garden_from_structure: Array[Vector2i] = []
			for structure_cell in structure_cells:
				if not house_set.has(structure_cell):
					garden_from_structure.append(structure_cell)
			if not garden_from_structure.is_empty():
				return garden_from_structure

		return _garden_cells_for_direction(anchor, str(info.get("garden_dir", "E")).strip_edges())

	func _garden_cells_for_direction(anchor: Vector2i, dir: String) -> Array[Vector2i]:
		match dir:
			"W":
				return [anchor + Vector2i(-1, 0), anchor + Vector2i(-1, 1)]
			"N":
				return [anchor + Vector2i(0, -1), anchor + Vector2i(1, -1)]
			"S":
				return [anchor + Vector2i(0, 2), anchor + Vector2i(1, 2)]
			_:
				return [anchor + Vector2i(2, 0), anchor + Vector2i(2, 1)]

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
		return Rect2(_board_origin_px() + Vector2(min_pos.x * CELL_SIZE, min_pos.y * CELL_SIZE), Vector2(size_cells.x * CELL_SIZE, size_cells.y * CELL_SIZE))

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

	func _format_house_display_label(info: Dictionary) -> String:
		var house_number = info.get("house_number", null)
		var house_id := str(info.get("house_id", "")).strip_edges()
		match house_id:
			"π", "9¾", "√2":
				return house_id
		return _format_house_display_number(house_number, "")

	func _format_house_display_number(value, fallback: String = "?") -> String:
		if value is int:
			return str(int(value))
		if value is float:
			var f: float = float(value)
			if f == floor(f):
				return str(int(f))
			var rounded := snappedf(f, 0.01)
			var text := "%.2f" % rounded
			while text.ends_with("0"):
				text = text.left(text.length() - 1)
			if text.ends_with("."):
				text = text.left(text.length() - 1)
			return text if not text.is_empty() else fallback
		if value is String:
			var s := str(value).strip_edges()
			if s.is_empty():
				return fallback
			var aliases := {
				"π": "3.14",
				"pi": "3.14",
				"9¾": "9.75",
				"√2": "1.41",
				"sqrt2": "1.41",
				"e": "2.72",
			}
			if aliases.has(s):
				return str(aliases[s])
			if s.is_valid_float():
				return _format_house_display_number(s.to_float(), fallback)
			var ascii_only := true
			for i in range(s.length()):
				if s.unicode_at(i) > 127:
					ascii_only = false
					break
			return s if ascii_only else fallback
		return fallback

	func _get_house_id_font() -> Font:
		if house_id_font != null:
			return house_id_font
		if not FileAccess.file_exists(HOUSE_ID_FONT_PATH):
			return ThemeDB.fallback_font
		var font := FontFile.new()
		if font.load_dynamic_font(HOUSE_ID_FONT_PATH) != OK:
			return ThemeDB.fallback_font
		font.set_allow_system_fallback(true)
		house_id_font = font
		return house_id_font

	func _get_house_id_label_texture(text: String) -> Texture2D:
		var key := str(text)
		if not HOUSE_ID_LABEL_TEXTURE_PATHS.has(key):
			return null
		if house_id_label_textures.has(key):
			var cached = house_id_label_textures[key]
			if cached is Texture2D:
				return cached
			return null
		var tex = _load_texture_raw(str(HOUSE_ID_LABEL_TEXTURE_PATHS[key]))
		if tex is Texture2D:
			house_id_label_textures[key] = tex
			return tex
		house_id_label_textures[key] = null
		return null

	func _compute_house_id_rect(structure_rect: Rect2) -> Rect2:
		var pad := maxf(3.0, float(CELL_SIZE) * 0.10)
		var bg_size := Vector2(float(CELL_SIZE) * 0.90, float(CELL_SIZE) * 0.58)
		var pos := structure_rect.position + Vector2(structure_rect.size.x - bg_size.x - pad, pad)
		return Rect2(pos, bg_size)

	func _fit_house_id_font_size(font: Font, text: String, max_width: float, base_size: int, min_size: int) -> int:
		if font == null or text.is_empty() or max_width <= 1.0:
			return base_size
		var size := maxi(min_size, base_size)
		while size > min_size:
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
			if text_size.x <= max_width:
				return size
			size -= 1
		return min_size

	func _draw_house_id(house_rect: Rect2, display_label) -> void:
		var text := str(display_label).strip_edges()
		if text.is_empty():
			return
		var pad := maxf(3.0, float(CELL_SIZE) * 0.12)
		var label_rect := _compute_house_id_rect(house_rect)
		var house_id_font := _get_house_id_font()
		var font: Font = house_id_font if house_id_font != null else ThemeDB.fallback_font
		if _draw_special_house_id_label(label_rect, text, font):
			return
		var base_font_size := maxi(11, int(round(float(CELL_SIZE) * 0.34)))
		var min_font_size := maxi(8, int(round(float(CELL_SIZE) * 0.22)))
		var font_size := _fit_house_id_font_size(font, text, maxf(1.0, label_rect.size.x - 2.0), base_font_size, min_font_size)
		var baseline := label_rect.position + Vector2(0.0, label_rect.size.y - pad)
		draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(0, 0, 0, 0.85))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(1, 1, 1, 1))

	func _draw_special_house_id_label(label_rect: Rect2, text: String, font: Font) -> bool:
		var tex := _get_house_id_label_texture(text)
		if tex != null:
			_draw_house_id_label_texture(label_rect, tex, Vector2(1, 1), Color(0, 0, 0, 0.85))
			_draw_house_id_label_texture(label_rect, tex, Vector2.ZERO, Color(1, 1, 1, 1))
			return true
		match text:
			"π":
				_draw_pi_house_id_label(label_rect, Vector2(1, 1), Color(0, 0, 0, 0.85))
				_draw_pi_house_id_label(label_rect, Vector2.ZERO, Color(1, 1, 1, 1))
				return true
			"9¾":
				if font == null:
					return false
				_draw_fraction_house_id_label(label_rect, "9", "3/4", font, Vector2(1, 1), Color(0, 0, 0, 0.85))
				_draw_fraction_house_id_label(label_rect, "9", "3/4", font, Vector2.ZERO, Color(1, 1, 1, 1))
				return true
			"√2":
				if font == null:
					return false
				_draw_sqrt_house_id_label(label_rect, font, Vector2(1, 1), Color(0, 0, 0, 0.85))
				_draw_sqrt_house_id_label(label_rect, font, Vector2.ZERO, Color(1, 1, 1, 1))
				return true
		return false

	func _draw_house_id_label_texture(label_rect: Rect2, tex: Texture2D, offset: Vector2, color: Color) -> void:
		if tex == null:
			return
		var tex_size := tex.get_size()
		if tex_size.x <= 0.0 or tex_size.y <= 0.0:
			return
		var max_size := Vector2(maxf(1.0, label_rect.size.x - 2.0), maxf(1.0, label_rect.size.y - 2.0))
		var scale := minf(max_size.x / tex_size.x, max_size.y / tex_size.y)
		var draw_size := tex_size * scale
		var pos := label_rect.position + (label_rect.size - draw_size) * 0.5 + offset
		draw_texture_rect(tex, Rect2(pos, draw_size), false, color)

	func _draw_pi_house_id_label(label_rect: Rect2, offset: Vector2, color: Color) -> void:
		var glyph_h := label_rect.size.y * 0.62
		var glyph_w := minf(label_rect.size.x * 0.52, glyph_h * 0.88)
		var center_x := label_rect.position.x + label_rect.size.x * 0.5
		var top_y := label_rect.position.y + label_rect.size.y * 0.30
		var bottom_y := top_y + glyph_h
		var left_x := center_x - glyph_w * 0.5
		var right_x := center_x + glyph_w * 0.5
		var stroke := maxf(2.0, glyph_h * 0.15)
		var top_slant := stroke * 0.45
		var serif := stroke * 0.65
		var top_points := PackedVector2Array([
			Vector2(left_x - serif, top_y + top_slant) + offset,
			Vector2(left_x - serif * 0.35, top_y) + offset,
			Vector2(right_x + serif, top_y) + offset,
			Vector2(right_x + serif * 0.35, top_y + stroke) + offset,
			Vector2(left_x - serif * 0.70, top_y + stroke) + offset,
		])
		draw_colored_polygon(top_points, color)

		var left_leg_x := left_x + glyph_w * 0.25
		var right_leg_x := left_x + glyph_w * 0.72
		var leg_top := top_y + stroke * 0.78
		var leg_h := maxf(1.0, bottom_y - leg_top)
		draw_rect(Rect2(Vector2(left_leg_x, leg_top) + offset, Vector2(stroke, leg_h)), color, true)
		draw_rect(Rect2(Vector2(right_leg_x, leg_top) + offset, Vector2(stroke, leg_h * 0.94)), color, true)

		var foot_w := stroke * 1.45
		var foot_h := maxf(1.0, stroke * 0.42)
		draw_rect(Rect2(Vector2(left_leg_x - foot_w * 0.25, bottom_y - foot_h) + offset, Vector2(foot_w, foot_h)), color, true)
		draw_rect(Rect2(Vector2(right_leg_x - foot_w * 0.15, bottom_y - foot_h - leg_h * 0.06) + offset, Vector2(foot_w, foot_h)), color, true)

	func _draw_fraction_house_id_label(label_rect: Rect2, whole: String, fraction: String, font: Font, offset: Vector2, color: Color) -> void:
		if font == null:
			return
		var whole_size := maxi(8, int(round(label_rect.size.y * 0.68)))
		var frac_size := maxi(7, int(round(label_rect.size.y * 0.42)))
		var gap := maxf(1.0, label_rect.size.x * 0.05)
		for _i in range(12):
			var whole_w := font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1.0, whole_size).x
			var frac_w := font.get_string_size(fraction, HORIZONTAL_ALIGNMENT_LEFT, -1.0, frac_size).x
			if whole_w + gap + frac_w <= label_rect.size.x - 2.0:
				break
			whole_size = maxi(7, whole_size - 1)
			frac_size = maxi(6, frac_size - 1)
		var final_whole_w := font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1.0, whole_size).x
		var final_frac_w := font.get_string_size(fraction, HORIZONTAL_ALIGNMENT_LEFT, -1.0, frac_size).x
		var start_x := label_rect.position.x + label_rect.size.x - final_whole_w - gap - final_frac_w
		var whole_baseline := label_rect.position.y + label_rect.size.y * 0.78
		var frac_baseline := label_rect.position.y + label_rect.size.y * 0.56
		draw_string(font, Vector2(start_x, whole_baseline) + offset, whole, HORIZONTAL_ALIGNMENT_LEFT, final_whole_w, whole_size, color)
		draw_string(font, Vector2(start_x + final_whole_w + gap, frac_baseline) + offset, fraction, HORIZONTAL_ALIGNMENT_LEFT, final_frac_w, frac_size, color)

	func _draw_sqrt_house_id_label(label_rect: Rect2, font: Font, offset: Vector2, color: Color) -> void:
		if font == null:
			return
		var text := "sqrt2"
		var font_size := _fit_house_id_font_size(font, text, label_rect.size.x - 2.0, maxi(8, int(round(label_rect.size.y * 0.52))), 7)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var baseline := label_rect.position + Vector2(label_rect.size.x - text_size.x, label_rect.size.y * 0.72)
		draw_string(font, baseline + offset, text, HORIZONTAL_ALIGNMENT_LEFT, text_size.x, font_size, color)

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
		return Rect2(_board_origin_px() + Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))

	func _board_origin_px() -> Vector2:
		var margin := _preview_margin_cells()
		return Vector2(int(margin.get("left", 0)) * CELL_SIZE, int(margin.get("top", 0)) * CELL_SIZE)

	func _preview_margin_cells() -> Dictionary:
		var result := {"left": 0, "right": 0, "top": 0, "bottom": 0}
		var margin_val = preview_options.get("margin_cells", {})
		if not (margin_val is Dictionary):
			return result
		var margin: Dictionary = margin_val
		for key in result.keys():
			var raw_val = margin.get(key, 0)
			if raw_val is int:
				result[key] = maxi(0, int(raw_val))
			elif raw_val is float:
				var f: float = float(raw_val)
				if f == floor(f):
					result[key] = maxi(0, int(f))
		return result

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
		"kicker": "开局设置",
		"summary": "储备卡是开局暗选的银行保险，不是玩家收入。基础规则下，第一次破产会揭示所有玩家已选储备卡，按卡面向银行注资，并用已选卡决定之后的 CEO 直属槽位。",
	},
	{
		"id": "round_flow",
		"title": "3. 一轮如何推进",
		"kicker": "阶段顺序",
		"summary": "每轮不是所有行动混在一起做，而是先重组公司，再决定商业秩序，然后依次进入工作时间的各个子阶段，最后由晚餐、发薪、营销和清理收尾。",
	},
	{
		"id": "employees",
		"title": "4. 员工与经理体系",
		"kicker": "谁负责什么",
		"summary": "员工的作用由公司结构、员工卡和阶段共同决定。经理负责扩展槽位；厨师生产食物；采购员拿饮料；营销员投广告；区域经理和大区经理负责开店，并会让你的餐厅获得免下车服务。",
	},
	{
		"id": "recruit_train_payday",
		"title": "5. 招聘、培训与薪水",
		"kicker": "员工成长",
		"summary": "招聘只能直接拿入门员工，高级员工通常靠培训链升级。带薪员工会在发薪日产生薪水压力，招聘经理和人力资源总监未用掉的招聘次数会转化为薪水折扣。",
	},
	{
		"id": "inventory",
		"title": "6. 生产、采购与库存",
		"kicker": "供应链",
		"summary": "晚餐销售必须先有库存。厨师生产汉堡或披萨，采购员工取得饮料；库存保留到晚餐后，清理阶段默认会清空没有冰箱保护的食物和饮料。",
	},
	{
		"id": "initial_restaurant",
		"title": "7. 起始餐厅放置",
		"kicker": "入口与板块",
		"summary": "起始餐厅必须入口邻接道路；起始放置阶段还要求每个地图板块最多只有一个餐厅入口。这个限制看入口所在板块，不看整个餐厅占地。",
	},
	{
		"id": "distance",
		"title": "8. 距离不是格子数",
		"kicker": "地图距离",
		"summary": "游戏里的道路距离以跨越地图板块边界的次数为主。道路步数只是辅助信息，不等于晚餐选店里使用的距离。",
	},
	{
		"id": "dinnertime",
		"title": "9. 晚餐阶段如何选店",
		"kicker": "结算核心",
		"summary": "已经有需求的房屋会按房屋编号顺序结算。每个房屋只考虑能完整供应它全部需求的餐厅，然后比较“决策单价 + 距离”，数值最小的餐厅获得这笔销售。",
	},
	{
		"id": "housing",
		"title": "10. 房屋、花园与公寓",
		"kicker": "需求容量与收入",
		"summary": "普通房屋默认最多容纳 3 个需求；带花园房屋默认最多 5 个需求，晚餐售卖时单价部分翻倍；公寓来自新区域扩展，营销放置需求会翻倍且没有需求上限。",
	},
	{
		"id": "marketing",
		"title": "11. 营销板件与街区",
		"kicker": "广告如何生效",
		"summary": "营销板件在营销结算阶段按编号结算并向覆盖房屋添加需求。广告牌看邻接，邮箱看街区，电波看周围板块，飞机看整条行或列。",
	},
	{
		"id": "milestones",
		"title": "12. 里程碑与终局",
		"kicker": "长期加成",
		"summary": "里程碑由游戏中的关键事件触发，提供员工、价格、收入、冰箱、顺序等长期效果。同回合获得的里程碑会在清理阶段从公共池移除；第二次银行破产会结束游戏并按现金排名。",
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
var _marketing_case: String = "billboard"

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

	var lesson_scroll := ScrollContainer.new()
	lesson_scroll.name = "LessonButtonScroll"
	lesson_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lesson_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar.add_child(lesson_scroll)

	var lesson_list := VBoxContainer.new()
	lesson_list.name = "LessonButtonList"
	lesson_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lesson_list.add_theme_constant_override("separation", 10)
	lesson_scroll.add_child(lesson_list)

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
		lesson_list.add_child(btn)

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
		"dinnertime":
			_render_dinnertime_lesson()
		"housing":
			_render_housing_lesson()
		"marketing":
			_render_marketing_lesson()
		"employees":
			_render_employees_lesson()
		"round_flow":
			_render_round_flow_lesson()
		"recruit_train_payday":
			_render_recruit_train_payday_lesson()
		"inventory":
			_render_inventory_lesson()
		"milestones":
			_render_milestones_lesson()

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
		"游戏结束时，未弃权玩家按现金从高到低排名，现金最多者获胜；现金相同则玩家编号靠前者排名靠前。\n\n最常见的终局来自银行破产：默认两次破产规则下，第一次破产后游戏继续；第二次破产会完成当前晚餐结算，然后跳过发薪日进入最终排名。",
		145
	))
	_content_body.add_child(win)

	var phases := _make_section("一轮大致做什么")
	phases.add_child(_make_rich_text(
		"重组结构：决定哪些员工上班、哪些留在储备区。\n商业秩序：确定玩家行动顺序。\n工作时间：招聘、培训、生产、开店、定价、投放营销等。\n晚餐时间：房屋按需求、价格、距离等规则选择餐厅并购买。\n发薪日、营销结算和清理阶段：支付薪水、结算广告持续时间、清理库存并进入下一轮。",
		170
	))
	_content_body.add_child(phases)

func _render_reserve_lesson() -> void:
	var card := _make_section("开局暗选")

	card.add_child(_make_rich_text(
		"银行是游戏的公共现金池，不属于任何玩家。晚餐销售收入、部分奖金等从银行付给玩家；发薪日等玩家支出则会回到银行。储备卡只在银行破产时影响银行和公司结构，不会在开局直接变成玩家现金。",
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
		"示例选择：%s。每位玩家在开局设置的储备卡阶段秘密选择 1 张；确认后不可更改。选择结果在第一次破产前对其他玩家隐藏。" % str(selected_details.get("summary", "")),
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

func _render_dinnertime_lesson() -> void:
	var overview := _make_section("房屋会怎样选择餐厅")
	overview.add_child(_build_real_map_preview(_build_dinnertime_preview_state(), _build_dinnertime_preview_options()))
	overview.add_child(_make_rich_text(
		"晚餐阶段按房屋编号从小到大处理。一个房屋如果没有需求，会直接跳过；如果有需求，会把这些需求合并成“需要哪些商品、各几个”。\n\n候选餐厅必须能完整供应这张需求清单。比如房屋有 1 个汉堡和 1 瓶可乐需求，餐厅库存里两种商品都够，才有资格参与比较；缺任意一种就不会被考虑。",
		150
	))
	_content_body.add_child(overview)

	var choice := _make_section("比较链")
	choice.add_child(_make_rich_text(
		"核心分数 = 决策单价 + 距离，分数越小越优先。\n\n决策单价来自基础单价和定价类效果：定价经理 -1，折扣经理 -3，奢侈品经理 +10，里程碑或扩展也可能修改基础单价。距离使用前一章介绍的板块边界距离，并可被扩展效果修正。\n\n如果分数相同，先比较平局分；基础规则里服务员会提高平局分。仍相同则按商业秩序靠前者获胜；如果还是同一玩家的多个餐厅，再选距离更短、道路步数更短、餐厅 ID 更靠前的那个。",
		190
	))
	_content_body.add_child(choice)

	var payout := _make_section("卖出后发生什么")
	payout.add_child(_make_rich_text(
		"获胜餐厅会扣除对应库存，房屋需求被清空。基础收入 = 单价 × 商品数量；花园只让这部分收入翻倍，不会让“单价 + 距离”的选店分数翻倍，也不会翻倍额外奖金。\n\n之后会叠加销售奖金、服务员收入、首席财务官收入加成等效果。所有这些从银行付给玩家，因此晚餐阶段也是最常触发银行第一次或第二次破产的阶段。",
		165
	))
	_content_body.add_child(payout)

func _render_housing_lesson() -> void:
	var preview := _make_section("普通房屋、花园房屋、公寓")
	preview.add_child(_build_real_map_preview(_build_housing_preview_state(), _build_housing_preview_options()))
	preview.add_child(_make_rich_text(
		"普通房屋是 2×2 结构，默认最多容纳 3 个需求。\n\n带花园房屋仍然只有房屋主体承载编号：默认需求上限提高到 5，并且晚餐售卖时“单价 × 数量”这部分收入翻倍。玩家口头说的豪宅效果，对应的就是带花园房屋的规则效果。\n\n公寓来自新区域扩展，使用 3×3 公寓素材。广告影响公寓时，每次会放入更多需求，而且不受普通需求上限限制。",
		210
	))
	_content_body.add_child(preview)

	var placement := _make_section("花园怎么来")
	placement.add_child(_make_rich_text(
		"新业务拓展经理可以放置房屋或给已有普通房屋加花园。加花园时，花园必须贴在房屋外侧，占地不能越界，不能压道路、建筑、阻塞格，也不能与已放置的营销板件重叠。\n\n花园改变的是房屋属性和收入结算，不会改变房屋编号顺序；晚餐仍然按房屋编号处理。",
		140
	))
	_content_body.add_child(placement)

func _render_marketing_lesson() -> void:
	var controls := _make_segmented_row([
		{"id": "billboard", "label": "广告牌"},
		{"id": "mailbox", "label": "邮箱"},
		{"id": "radio", "label": "电波"},
		{"id": "airplane", "label": "飞机"},
	], _marketing_case, Callable(self, "_on_marketing_case_selected"))
	_content_body.add_child(controls)

	var ranges := _make_section(_get_marketing_case_title(_marketing_case))
	ranges.add_child(_build_real_map_preview(_build_marketing_preview_state(_marketing_case), _build_marketing_preview_options(_marketing_case)))
	ranges.add_child(_make_rich_text(_get_marketing_case_text(_marketing_case), 190))
	_content_body.add_child(ranges)

	var settlement := _make_section("广告何时生效")
	settlement.add_child(_make_rich_text(
		"营销员在工作时间发起广告，通常选择 1 种商品和持续时间。基础员工的上限不同：营销实习生只能放广告牌，最多 2 回合；营销经理可放邮箱或广告牌，最多 3 回合；品牌经理可放飞机或以下广告，最多 4 回合；品牌总监可放电波或以下广告，最多 5 回合。\n\n营销结算阶段按营销板件编号从小到大结算。每次结算会向覆盖房屋添加需求，受普通房屋和花园房屋的需求上限影响；公寓会获得更多需求，且不受普通需求上限限制。广告持续时间用完后会移除，对应忙碌营销员才释放。",
		210
	))
	_content_body.add_child(settlement)

func _get_marketing_case_title(case_id: String) -> String:
	match case_id:
		"mailbox":
			return "邮箱：同一街区"
		"radio":
			return "电波：周围 3×3 板块"
		"airplane":
			return "飞机：整条行或列"
		_:
			return "广告牌：正交相邻"

func _get_marketing_case_text(case_id: String) -> String:
	match case_id:
		"mailbox":
			return "邮箱影响同一个街区里的房屋。这里的街区不是地图板块，而是道路图切出来的一片连续非道路区域；道路会把街区隔开。\n\n图中蓝色区域表示同一街区，灰色营销板件是邮箱位置，绿色房屋会被这次广告覆盖。邮箱常用于给一片被道路围起来的房屋同时放需求。"
		"radio":
			return "电波按地图板块计算范围：取营销板件所在板块，再向周围扩展成 3×3 板块范围。教程预览只有两块板，所以图中蓝色显示的是这个范围在当前可见地图里的切片。\n\n电波本身通常是小板件，但覆盖范围很大；首个进行电波营销的里程碑还会强化电波放置需求的数量。"
		"airplane":
			return "飞机放在地图边缘外，不占用棋盘内部格子。它的长度决定飞过多少行或列；被飞过的行/列会横跨整张地图。\n\n图中蓝色横带表示飞机飞过的区域，绿色房屋会被覆盖。飞机不是看街区，也不是看道路，只看这条横向或纵向带状区域。"
		_:
			return "广告牌只影响与营销板件占地正交相邻的房屋。斜角接触不算，隔着道路或空格不算；营销板件越大，可能接触到的房屋边也越多。\n\n图中灰色营销板件是广告牌占地，绿色房屋与它贴边，因此会被这次广告覆盖。"

func _render_employees_lesson() -> void:
	var structure := _make_section("公司结构先决定谁能工作")
	structure.add_child(_build_employee_card_row(["ceo", "management_trainee", "trainer", "kitchen_trainee"], 0.82))
	structure.add_child(_make_rich_text(
		"CEO 默认有 3 个直属槽位，第一次破产后基础储备卡规则可能把这个值改成 2 / 3 / 4。CEO 下面可以直接放普通员工或经理；经理只能向 CEO 汇报，不能放在另一个经理下面；经理下面只能放普通员工。\n\n员工放不进结构就留在储备区，本回合不会执行在岗效果。忙碌中的营销员不占结构槽位，直到广告到期才回来。",
		165
	))
	_content_body.add_child(structure)

	var roles := _make_section("基础员工怎么分工")
	roles.add_child(_build_employee_card_row(["kitchen_trainee", "errand_boy", "pricing_manager", "marketing_trainee", "local_manager"], 0.80))
	roles.add_child(_make_rich_text(
		"招聘/培训：人力资源专员、人力资源经理、人力资源总监负责拿员工或减少薪水；培训讲师、培训指导员、培训专家负责升级员工。\n生产：见习厨师、汉堡厨师/主厨、披萨厨师/主厨生产食物。\n采购：跑腿伙计拿 1 瓶饮料；手推车操作员和货车驾驶员沿道路从进货点拿饮料；飞艇驾驶员无视道路。\n定价：定价经理 -1，折扣经理 -3，奢侈品经理 +10；这些是强制动作。\n营销：营销实习生、营销经理、品牌经理、品牌总监决定能放哪类广告和持续多久。\n开店/地图：区域经理放置即将开业餐厅；大区经理可放置立即开业餐厅或移动现有餐厅；新业务拓展经理放房屋或花园。\n结算辅助：服务员提供收入并赢平局；首席财务官让本回合收入增加 50%。",
		260
	))
	_content_body.add_child(roles)

	var drive_thru := _make_section("区域经理、大区经理与免下车")
	drive_thru.add_child(_build_employee_card_row(["local_manager", "regional_manager"], 0.88))
	drive_thru.add_child(_build_real_map_preview(_build_drive_thru_preview_state(), _build_drive_thru_preview_options()))
	drive_thru.add_child(_make_rich_text(
		"只要你本回合有区域经理或大区经理在岗，你的所有餐厅都会获得免下车服务。\n\n图中餐厅横跨左右两个板块。没有免下车时，只能从原入口角进店，右侧房屋要沿橙色路线跨过板块边界；启用免下车后，四个角都可以作为入口/出口，右侧房屋可沿绿色路线留在同一板块内进店。价格相近时，这种距离变化会直接影响晚餐选店。",
		185
	))
	_content_body.add_child(drive_thru)

func _render_round_flow_lesson() -> void:
	var full_round := _make_section("完整阶段顺序")
	full_round.add_child(_build_phase_track_preview())
	full_round.add_child(_make_rich_text(
		"开局设置只在开局出现：选择储备卡并放起始餐厅。\n\n正常回合按这个顺序推进：重组结构，商业秩序，工作时间，晚餐时间，发薪日，营销结算，清理阶段。清理阶段会清理库存、打开即将开业餐厅，并处理里程碑池。",
		180
	))
	_content_body.add_child(full_round)

	var order := _make_section("商业秩序怎么选")
	order.add_child(_make_rich_text(
		"进入商业秩序时，系统先计算每位玩家公司结构里的空槽位。空槽位越多，越早选择自己在本轮行动顺序中的位置；空槽位相同则按上一轮顺序靠前者先选。\n\n最终选出来的行动顺序会影响工作时间中谁先行动，也会参与晚餐阶段的平局决胜。",
		145
	))
	_content_body.add_child(order)

	var working := _make_section("工作时间的子阶段")
	working.add_child(_build_process_chip_row(["招聘", "培训", "营销", "生产食物", "采购饮料", "放置房屋/花园", "放置或移动餐厅"]))
	working.add_child(_make_rich_text(
		"工作时间不是一个自由行动池，而是固定子阶段依次处理：招聘、培训、营销、生产食物、采购饮料、放置房屋/花园、放置或移动餐厅。\n\n每个子阶段内按本轮行动顺序轮流执行。某个子阶段没有可用动作时可以跳过；强制定价类动作属于工作时间强制动作，可以在工作时间的任意子阶段处理。",
		165
	))
	_content_body.add_child(working)

func _render_recruit_train_payday_lesson() -> void:
	var recruit := _make_section("招聘只拿入门员工")
	recruit.add_child(_build_employee_card_row(["ceo", "recruiting_girl", "trainer", "kitchen_trainee", "errand_boy"], 0.80))
	recruit.add_child(_make_rich_text(
		"基础规则里，直接招聘的目标必须是入门员工：管理培训生、见习厨师、跑腿伙计、人力资源专员、培训讲师、定价经理、营销实习生、服务员等。\n\nCEO 自带 1 次招聘能力；人力资源专员 1 次，人力资源经理 2 次，人力资源总监 4 次。招聘来的员工进入储备区，是否能立刻上班取决于下一次重组时公司结构有没有位置。",
		175
	))
	_content_body.add_child(recruit)

	var train := _make_section("培训沿着升级链走")
	train.add_child(_build_training_chain_preview())
	train.add_child(_make_rich_text(
		"培训必须沿员工定义里的升级链逐步进行。例：见习厨师可以升汉堡厨师或披萨厨师，再升对应主厨；跑腿伙计可以升手推车操作员、货车驾驶员、飞艇驾驶员；营销实习生可以升营销经理、品牌经理、品牌总监。\n\n培训讲师提供 1 次培训，培训指导员 2 次，培训专家 3 次。默认同一名员工不能随意换不同培训员连续培训；获得“首个支付 $20+ 薪水”里程碑后，可以让多个培训员集中培训同一名员工。",
		205
	))
	_content_body.add_child(train)

	var payday := _make_section("发薪日会把扩张压力算回来")
	payday.add_child(_build_employee_card_row(["recruiting_manager", "hr_director", "burger_cook", "waitress"], 0.86))
	payday.add_child(_make_rich_text(
		"需要发薪的员工会在发薪日产生薪水，基础薪水是每人 $5。薪水从玩家现金付给银行；如果现金不够且没有允许欠薪的效果，本阶段会要求先处理薪水问题。\n\n人力资源经理和人力资源总监带有薪水折扣效果：本回合未用掉的招聘次数会按每次 $5 抵扣薪水。首个培训员工的里程碑还会让总薪水永久 -$15，最低应付不会低于 $0。",
		175
	))
	_content_body.add_child(payday)

func _render_inventory_lesson() -> void:
	var food := _make_section("食物先进入玩家库存")
	food.add_child(_build_product_icon_row(["burger", "pizza"], ["汉堡", "披萨"]))
	food.add_child(_build_employee_card_row(["kitchen_trainee", "burger_cook", "pizza_cook", "burger_chef", "pizza_chef"], 0.78))
	food.add_child(_make_rich_text(
		"生产食物发生在工作时间的生产食物子阶段。见习厨师可以选择生产 1 个汉堡或 1 个披萨；汉堡厨师/披萨厨师各生产 3 个对应食物；汉堡主厨/披萨主厨各生产 8 个。\n\n这些食物先进入玩家库存，不会自动分配给某一家餐厅。晚餐阶段检查的是玩家餐厅是否能用该玩家库存完整满足房屋需求。",
		165
	))
	_content_body.add_child(food)

	var drinks := _make_section("饮料来自采购")
	drinks.add_child(_build_real_map_preview(_build_inventory_preview_state(), _build_inventory_preview_options()))
	drinks.add_child(_build_employee_card_row(["errand_boy", "cart_operator", "truck_driver", "zeppelin_pilot"], 0.82))
	drinks.add_child(_make_rich_text(
		"采购饮料发生在工作时间的采购饮料子阶段，而且玩家必须已经有餐厅。跑腿伙计直接获得 1 瓶指定饮料；手推车操作员和货车驾驶员需要沿道路从路线经过的进货点拿饮料；飞艇驾驶员可以无视道路。\n\n基础路线采购每个饮料源提供 2 瓶。首个使用跑腿伙计的里程碑会让采购每个来源 +1；首个使用手推车操作员的里程碑会让手推车、货车、飞艇的采购距离能力提高。",
		185
	))
	_content_body.add_child(drinks)

	var cleanup := _make_section("清理阶段为什么会丢库存")
	cleanup.add_child(_make_rich_text(
		"晚餐后没卖掉的食物和饮料仍在库存里。清理阶段默认会清空没有冰箱保护的食物/饮料；因此早期过量生产可能只是在浪费银行前的行动机会。\n\n首次在清理阶段丢弃食物或饮料会触发“首个丢弃食物/饮品”里程碑，获得容量 10 的冰箱。之后如果食物/饮料总量超过冰箱容量，清理阶段会要求玩家选择保留哪些库存。",
		170
	))
	_content_body.add_child(cleanup)

func _render_milestones_lesson() -> void:
	var trigger := _make_section("里程碑由事件触发")
	trigger.add_child(_build_product_icon_row(["burger", "pizza", "soda"], ["生产/售出", "营销商品", "饮料销售"]))
	trigger.add_child(_make_rich_text(
		"里程碑不是手动购买，而是在动作或结算产生关键结果时自动检查。例：首次生产汉堡、首次发起某类广告、首次让房屋被广告添加需求，或晚餐收入让现金达到特定门槛，都可能触发对应里程碑。\n\n同一回合内，多名玩家可能先后获得同一种里程碑；清理阶段会根据本回合领取记录，从公共里程碑池移除对应数量。",
		175
	))
	_content_body.add_child(trigger)

	var effects := _make_section("基础里程碑给什么")
	effects.add_child(_build_employee_card_row(["burger_cook", "pizza_cook", "cfo", "waitress"], 0.84))
	effects.add_child(_make_rich_text(
		"生产类：首个生产汉堡/披萨会给对应厨师卡。\n营销类：首个营销汉堡/披萨/饮料会给对应商品销售奖金；首个广告牌让营销免薪并可永久；首个电波强化电波需求；首个飞机给商业秩序空槽位加成。\n经营类：首个拥有 $20 可查看所有储备卡；首个拥有 $100 让 CEO 从下一回合起获得首席财务官收入能力，并禁用首席财务官卡；首个降价让基础价格再 -1；首个服务员提高服务员小费。",
		230
	))
	_content_body.add_child(effects)

	var endgame := _make_section("终局和排名")
	endgame.add_child(_make_rich_text(
		"默认银行最多破产两次。第一次破产会处理储备卡或相关扩展规则，然后游戏继续；第二次破产会让本局在当前晚餐时间结束后进入游戏结束，后续发薪日不再结算。\n\n游戏结束排名只看现金：未弃权玩家排在弃权玩家前面；现金高者胜；现金相同则玩家编号靠前者排前。",
		150
	))
	_content_body.add_child(endgame)

func _build_phase_track_preview() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.82), Color(0.17, 0.13, 0.09, 0.20), 1, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	frame.add_child(margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	var strip := PhaseTrackStripClass.new()
	strip.set_font_size(14)
	strip.set_current_phase("Working")
	center.add_child(strip)
	return frame

func _build_process_chip_row(labels: Array) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	for label_text in labels:
		row.add_child(_build_process_chip(str(label_text)))
	return row

func _build_process_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.82), Color(0.17, 0.13, 0.09, 0.22), 1, 5))

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	chip.add_child(label)
	return chip

func _build_employee_card_row(employee_ids: Array, scale: float = 0.84) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	for employee_id in employee_ids:
		row.add_child(_build_employee_card(str(employee_id), scale))
	return row

func _build_employee_card(employee_id: String, scale: float) -> Control:
	var def := _load_employee_card_data(employee_id)
	var card := EmployeeCardClass.new()
	card.variant = EmployeeCardClass.CardVariant.COMPACT
	card.draggable = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_display_scale(scale)
	card.setup(def)
	return card

func _load_employee_card_data(employee_id: String) -> Dictionary:
	var path := "res://modules/base_employees/content/employees/%s.json" % employee_id
	var data := _load_json_dict(path)
	if data.is_empty():
		return {
			"id": employee_id,
			"name": employee_id,
			"description": "",
			"salary": false,
			"role": "special",
			"manager_slots": 0,
			"range": {"type": null, "value": 0},
			"train_to": [],
			"tags": [],
			"pool": {"type": "none"},
		}
	var produces_val = data.get("produces", {})
	if produces_val is Dictionary:
		var produces: Dictionary = produces_val
		data["produces_food_type"] = str(produces.get("food_type", "")).strip_edges()
		data["produces_amount"] = int(produces.get("amount", 0))
	data["salary"] = false
	data["range"] = {"type": null, "value": 0}
	data["tags"] = []
	data["pool"] = {"type": "none"}
	return data

func _build_training_chain_preview() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	box.add_child(_build_employee_chain(["kitchen_trainee", "burger_cook", "burger_chef"], 0.78))
	box.add_child(_build_employee_chain(["errand_boy", "cart_operator", "truck_driver", "zeppelin_pilot"], 0.74))
	box.add_child(_build_employee_chain(["marketing_trainee", "campaign_manager", "brand_manager", "brand_director"], 0.74))
	return box

func _build_employee_chain(employee_ids: Array, scale: float) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	for i in range(employee_ids.size()):
		if i > 0:
			row.add_child(_build_arrow_label())
		row.add_child(_build_employee_card(str(employee_ids[i]), scale))
	return row

func _build_arrow_label() -> Control:
	var label := Label.new()
	label.text = "→"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(24, 80)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	return label

func _build_product_icon_row(product_ids: Array, labels: Array) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	for i in range(product_ids.size()):
		var product_id := str(product_ids[i])
		var label_text := product_id
		if i < labels.size():
			label_text = str(labels[i])
		row.add_child(_build_product_icon_chip(product_id, label_text))
	return row

func _build_product_icon_chip(product_id: String, label_text: String) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _make_style(Color(0.96, 0.92, 0.82, 0.82), Color(0.17, 0.13, 0.09, 0.18), 1, 6))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	chip.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(34, 34)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture = _load_texture_from_res_path(_product_icon_path(product_id))
	row.add_child(tex_rect)

	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	row.add_child(label)
	return chip

func _product_icon_path(product_id: String) -> String:
	var normalized := "soda" if product_id == "cola" else product_id
	return "res://modules/base_products/assets/map/icons/%s.png" % normalized

func _load_texture_from_res_path(path: String) -> Texture2D:
	var raw_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var raw_image := Image.load_from_file(raw_path)
	if raw_image == null or raw_image.is_empty():
		return null
	return ImageTexture.create_from_image(raw_image)

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

	var details := "如果房间启用了储备价格扩展，第一次破产规则不是上面的基础规则：\n"
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
			if piece_id != "house" and piece_id != "house_with_garden" and piece_id != "apartment":
				continue
			var local_anchor := _variant_to_vector2i(structure.get("anchor", [0, 0]))
			structure["anchor"] = origin + local_anchor
			var props_val = structure.get("house_props", {})
			if props_val is Dictionary:
				for prop_key in (props_val as Dictionary).keys():
					structure[prop_key] = (props_val as Dictionary)[prop_key]
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

func _build_dinnertime_preview_state() -> Dictionary:
	var state := _build_preview_map_state()
	var restaurants: Array = state.get("restaurants", [])
	restaurants.append({"restaurant_id": "rest_dinner_close", "owner": 0, "anchor": Vector2i(3, 3)})
	restaurants.append({"restaurant_id": "rest_dinner_far", "owner": 1, "anchor": Vector2i(8, 3)})
	state["restaurants"] = restaurants
	return state

func _build_dinnertime_preview_options() -> Dictionary:
	return {
		"overlays": [
			{
				"id": "active_house",
				"cells": _restaurant_cells_for_anchor(Vector2i(0, 0), 0),
				"style": {
					"fill": MAP_DISTANCE_FILL,
					"border": MAP_DISTANCE_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _build_housing_preview_state() -> Dictionary:
	return {
		"road_segments": {},
		"houses": [
			{
				"piece_id": "house",
				"anchor": Vector2i(0, 0),
				"house_id": "2",
				"house_number": 2,
			},
			{
				"piece_id": "house_with_garden",
				"anchor": Vector2i(3, 0),
				"house_id": "5",
				"house_number": 5,
				"garden_dir": "E",
				"garden_cells": [Vector2i(5, 0), Vector2i(5, 1)],
			},
			{
				"piece_id": "apartment",
				"anchor": Vector2i(7, 1),
				"house_id": "π",
				"house_number": 3.14,
			},
		],
		"restaurants": [],
	}

func _build_housing_preview_options() -> Dictionary:
	return {
		"overlays": [
			{
				"id": "garden_house",
				"cells": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 0), Vector2i(5, 1)],
				"style": {
					"fill": MAP_VALID_FILL,
					"border": MAP_VALID_BORDER,
					"border_width": 2,
				},
			},
			{
				"id": "apartment",
				"cells": [Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1), Vector2i(7, 2), Vector2i(8, 2), Vector2i(9, 2), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3)],
				"style": {
					"fill": MAP_DISTANCE_FILL,
					"border": MAP_DISTANCE_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _build_marketing_preview_state(case_id: String = "billboard") -> Dictionary:
	var state := _build_marketing_demo_base_state()
	var placements: Array[Dictionary] = []
	match case_id:
		"mailbox":
			placements.append(_make_marketing_placement("mailbox", 9, Vector2i(3, 1), Vector2i(1, 1)))
		"radio":
			placements.append(_make_marketing_placement("radio", 1, Vector2i(3, 1), Vector2i(1, 1)))
		"airplane":
			placements.append(_make_marketing_placement("airplane", 5, Vector2i(0, 0), Vector2i(3, 2), "row"))
		_:
			placements.append(_make_marketing_placement("billboard", 14, Vector2i(2, 1), Vector2i(2, 1)))
	state["marketing_placements"] = placements
	return state

func _build_marketing_preview_options(case_id: String = "billboard") -> Dictionary:
	var overlays: Array[Dictionary] = []
	var state := _build_marketing_preview_state(case_id)
	match case_id:
		"mailbox":
			overlays.append(_make_map_overlay("mailbox_block", _compute_preview_block_cells(state, Vector2i(3, 1)), Color(0.29, 0.55, 0.90, 0.14), Color(0.16, 0.31, 0.62, 0.80), 2))
			overlays.append(_make_map_overlay("mailbox_affected_houses", _marketing_demo_house_cells(["2", "5"]), MAP_VALID_FILL, MAP_VALID_BORDER, 2))
		"radio":
			var visible_radio_range: Array[Vector2i] = []
			for y2 in range(5):
				for x2 in range(10):
					visible_radio_range.append(Vector2i(x2, y2))
			overlays.append(_make_map_overlay("radio_visible_range", visible_radio_range, Color(0.29, 0.55, 0.90, 0.12), Color(0.16, 0.31, 0.62, 0.62), 2))
			overlays.append(_make_map_overlay("radio_affected_houses", _marketing_demo_house_cells(["2", "4", "5", "7"]), MAP_VALID_FILL, MAP_VALID_BORDER, 2))
		"airplane":
			var stripe: Array[Vector2i] = []
			for x3 in range(10):
				stripe.append(Vector2i(x3, 0))
				stripe.append(Vector2i(x3, 1))
				stripe.append(Vector2i(x3, 2))
			overlays.append(_make_map_overlay("airplane_stripe", stripe, Color(0.29, 0.55, 0.90, 0.14), Color(0.16, 0.31, 0.62, 0.78), 2))
			overlays.append(_make_map_overlay("airplane_affected_houses", _marketing_demo_house_cells(["2", "4"]), MAP_VALID_FILL, MAP_VALID_BORDER, 2))
		_:
			overlays.append(_make_map_overlay("billboard_affected_house", _marketing_demo_house_cells(["2"]), MAP_VALID_FILL, MAP_VALID_BORDER, 2))
	var options := {"overlays": overlays}
	if case_id == "airplane":
		options["margin_cells"] = {"left": 2, "right": 0, "top": 0, "bottom": 0}
	return options

func _build_marketing_demo_base_state() -> Dictionary:
	var road_map: Dictionary = {}
	for y in range(5):
		road_map[Vector2i(4, y)] = [_make_vertical_road_segment(y)]
	return {
		"road_segments": road_map,
		"houses": [
			{"piece_id": "house", "anchor": Vector2i(0, 0), "house_id": "2", "house_number": 2},
			{"piece_id": "house", "anchor": Vector2i(6, 0), "house_id": "4", "house_number": 4},
			{"piece_id": "house", "anchor": Vector2i(0, 3), "house_id": "5", "house_number": 5},
			{"piece_id": "house", "anchor": Vector2i(6, 3), "house_id": "7", "house_number": 7},
		],
		"restaurants": [],
	}

func _make_vertical_road_segment(y: int) -> Dictionary:
	var dirs: Array[String] = []
	if y > 0:
		dirs.append("N")
	if y < 4:
		dirs.append("S")
	return {"dirs": dirs, "bridge": false}

func _make_road_segment(dirs: Array[String]) -> Dictionary:
	return {"dirs": dirs, "bridge": false}

func _make_marketing_placement(type_id: String, board_number: int, world_pos: Vector2i, footprint_size: Vector2i, axis: String = "") -> Dictionary:
	var placement := {
		"type": type_id,
		"board_number": board_number,
		"world_pos": world_pos,
		"footprint_size": footprint_size,
		"rotation": 0,
		"product": "burger",
		"remaining_duration": 2,
	}
	if not axis.is_empty():
		placement["axis"] = axis
	return placement

func _marketing_demo_house_cells(house_ids: Array[String]) -> Array[Vector2i]:
	var anchors := {
		"2": Vector2i(0, 0),
		"4": Vector2i(6, 0),
		"5": Vector2i(0, 3),
		"7": Vector2i(6, 3),
	}
	var out: Array[Vector2i] = []
	for house_id in house_ids:
		if not anchors.has(house_id):
			continue
		out.append_array(_restaurant_cells_for_anchor(anchors[house_id], 0))
	return out

func _compute_preview_block_cells(state: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _has_preview_road_at(state, start):
		return out
	var visited := {}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		if visited.has(pos):
			continue
		visited[pos] = true
		if pos.x < 0 or pos.y < 0 or pos.x >= 10 or pos.y >= 5:
			continue
		if _has_preview_road_at(state, pos):
			continue
		out.append(pos)
		queue.append(pos + Vector2i(1, 0))
		queue.append(pos + Vector2i(-1, 0))
		queue.append(pos + Vector2i(0, 1))
		queue.append(pos + Vector2i(0, -1))
	return out

func _has_preview_road_at(state: Dictionary, pos: Vector2i) -> bool:
	var road_map_val = state.get("road_segments", {})
	if not (road_map_val is Dictionary):
		return false
	var road_map: Dictionary = road_map_val
	var segments_val = road_map.get(pos, [])
	return segments_val is Array and not (segments_val as Array).is_empty()

func _make_map_overlay(id: String, cells: Array, fill: Color, border: Color, border_width: int = 2) -> Dictionary:
	return {
		"id": id,
		"cells": cells,
		"style": {
			"fill": fill,
			"border": border,
			"border_width": border_width,
		},
	}

func _build_drive_thru_preview_state() -> Dictionary:
	var road_map: Dictionary = {}
	road_map[Vector2i(7, 0)] = [_make_road_segment(["W"])]
	road_map[Vector2i(6, 0)] = [_make_road_segment(["E", "S"])]
	road_map[Vector2i(6, 1)] = [_make_road_segment(["N", "S", "W"])]
	road_map[Vector2i(6, 2)] = [_make_road_segment(["N", "S"])]
	road_map[Vector2i(6, 3)] = [_make_road_segment(["N", "W"])]
	road_map[Vector2i(5, 1)] = [_make_road_segment(["E", "W"])]
	road_map[Vector2i(4, 1)] = [_make_road_segment(["E", "S"])]

	var state := {
		"road_segments": road_map,
		"houses": [
			{"piece_id": "house", "anchor": Vector2i(8, 0), "house_id": "2", "house_number": 2},
		],
		"restaurants": [],
	}
	state["restaurants"] = [
		{
			"restaurant_id": "rest_drive_thru",
			"owner": 0,
			"anchor": Vector2i(4, 2),
			"drive_thru": true,
		},
	]
	return state

func _build_drive_thru_preview_options() -> Dictionary:
	return {
		"overlays": [
			{
				"id": "before_drive_thru_route",
				"cells": [Vector2i(7, 0), Vector2i(6, 0), Vector2i(6, 1), Vector2i(5, 1), Vector2i(4, 1)],
				"style": {
					"fill": Color(0.97, 0.54, 0.15, 0.25),
					"border": Color(0.75, 0.32, 0.05, 0.85),
					"border_width": 2,
				},
			},
			{
				"id": "after_drive_thru_route",
				"cells": [Vector2i(7, 0), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3)],
				"style": {
					"fill": Color(0.20, 0.75, 0.36, 0.22),
					"border": Color(0.12, 0.52, 0.22, 0.90),
					"border_width": 2,
				},
			},
			{
				"id": "drive_thru_house",
				"cells": _restaurant_cells_for_anchor(Vector2i(8, 0), 0),
				"style": {
					"fill": MAP_VALID_FILL,
					"border": MAP_VALID_BORDER,
					"border_width": 2,
				},
			},
		],
	}

func _build_inventory_preview_state() -> Dictionary:
	var road_map: Dictionary = {}
	road_map[Vector2i(2, 2)] = [_make_road_segment(["E", "S"])]
	road_map[Vector2i(3, 2)] = [_make_road_segment(["E", "W"])]
	road_map[Vector2i(4, 2)] = [_make_road_segment(["E", "W"])]
	road_map[Vector2i(5, 2)] = [_make_road_segment(["E", "W"])]
	road_map[Vector2i(6, 2)] = [_make_road_segment(["E", "W"])]
	road_map[Vector2i(7, 2)] = [_make_road_segment(["W"])]
	return {
		"road_segments": road_map,
		"houses": [],
		"restaurants": [
			{"restaurant_id": "rest_inventory", "owner": 0, "anchor": Vector2i(2, 3)},
		],
		"drink_sources": [
			{"world_pos": Vector2i(5, 2), "type": "soda"},
			{"world_pos": Vector2i(7, 2), "type": "lemonade"},
		],
	}

func _build_inventory_preview_options() -> Dictionary:
	return {
		"overlays": [
			{
				"id": "drink_route",
				"cells": [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2)],
				"style": {
					"fill": MAP_DISTANCE_FILL,
					"border": MAP_DISTANCE_BORDER,
					"border_width": 2,
				},
			},
		],
	}

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

func _on_marketing_case_selected(case_id: String) -> void:
	_marketing_case = case_id
	_render_lesson()

func _on_prev_pressed() -> void:
	_select_lesson(_selected_lesson - 1)

func _on_next_pressed() -> void:
	_select_lesson(_selected_lesson + 1)

func _on_back_pressed() -> void:
	if SceneManager != null and SceneManager.has_method("goto_main_menu"):
		SceneManager.goto_main_menu()
