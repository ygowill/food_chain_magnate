# MapCanvasDrawer：结构（房屋/餐厅/道路 piece 等）绘制下沉
extends RefCounted

const TextureUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_texture_utils.gd")
const OverlayUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_overlay_utils.gd")
const RoadsPassClass = preload("res://ui/scenes/game/map_canvas_drawer_roads_pass.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

static var _drink_source_textures: Dictionary = {} # product_id -> Texture2D
static var _drink_source_textures_base_dir: String = ""

static func _read_color_hint(hints: Dictionary, key: String, fallback: Color) -> Color:
	if hints == null or hints.is_empty():
		return fallback
	var val = hints.get(key, null)
	if val is Color:
		return val
	if val is String:
		var s := str(val).strip_edges()
		if not s.is_empty():
			return Color(s)
	return fallback

static func draw_drink_sources(canvas, cell_size: int) -> void:
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
			var override_tex: Texture2D = _get_drink_source_texture(product_id)
			var tex: Texture2D = override_tex if (override_tex is Texture2D) else canvas._skin.get_product_icon_texture(product_id)

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			TextureUtilsClass.draw_texture_aspect_fill(canvas, tex, rect, Color(1, 1, 1, 0.95))

static func _get_drink_source_texture(product_id: String) -> Texture2D:
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"
	if pid.is_empty():
		return null

	var base_dir := str(ModulesBaseDirClass.get_base_dir()).strip_edges()
	if base_dir != _drink_source_textures_base_dir:
		_drink_source_textures_base_dir = base_dir
		_drink_source_textures.clear()

	var cached_val = _drink_source_textures.get(pid, null)
	if cached_val is Texture2D:
		return cached_val
	if _drink_source_textures.has(pid):
		return null

	var path := base_dir.path_join("base_products").path_join("assets").path_join("map").path_join("drink_sources").path_join("%s.png" % pid)
	var tex := _load_texture_from_path(path)
	_drink_source_textures[pid] = tex
	return tex

static func _load_texture_from_path(path: String) -> Texture2D:
	var p := str(path).strip_edges()
	if p.is_empty():
		return null

	# Enforce packaged resources only.
	if not p.begins_with("res://"):
		return null
	var res = load(p)
	if res is Texture2D:
		return res
	return null

static func draw_structures(canvas, cell_size: int, restaurant_logo_piece_ids: Array) -> void:
	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		var info: Dictionary = canvas._structures_by_anchor[anchor]
		var piece_id: String = str(info.get("piece_id", "")).strip_edges()
		if piece_id.is_empty():
			continue

		if piece_id == "house" or piece_id == "house_with_garden":
			draw_house_and_garden(canvas, cell_size, anchor, info)
			continue

		var road_overlay := PieceUiHintsRegistryClass.get_road_overlay(piece_id)
		if not road_overlay.is_empty():
			draw_road_overlay_piece(canvas, cell_size, anchor, info, road_overlay)
			continue

		var ui_kind := PieceUiHintsRegistryClass.get_kind(piece_id)
		if piece_id == "park" or ui_kind == "park":
			draw_park_piece(canvas, cell_size, info)
			continue

		var min_pos: Vector2i = info.get("min", anchor)
		var max_pos: Vector2i = info.get("max", anchor)
		var size_cells := (max_pos - min_pos) + Vector2i.ONE
		var footprint_rect := Rect2(Vector2(min_pos.x * cell_size, min_pos.y * cell_size), Vector2(size_cells.x * cell_size, size_cells.y * cell_size))

		var hints := PieceUiHintsRegistryClass.get_hints(piece_id)
		var style := str(hints.get("structure_style", "")).strip_edges()
		if style == "house_id":
			var bg_col := _read_color_hint(hints, "bg_color", Color("#814e60"))
			draw_house_id_structure(canvas, cell_size, info, footprint_rect, bg_col, 1.0)
			continue
		if style == "player_logo":
			var owner_logo := int(info.get("owner", -1))
			if owner_logo >= 0:
				var suffix2 := str(hints.get("logo_variant_suffix", "")).strip_edges()
				draw_player_logo_piece(canvas, cell_size, footprint_rect, 1.0, restaurant_logo_piece_ids, owner_logo, suffix2)
				continue
		if style == "player_logo_bg":
			var owner := int(info.get("owner", -1))
			if owner >= 0:
				var bg_col2 := _read_color_hint(hints, "bg_color", Color("#f4edd1"))
				var suffix := str(hints.get("logo_variant_suffix", "")).strip_edges()
				draw_player_logo_structure(canvas, cell_size, anchor, info, footprint_rect, 1.0, restaurant_logo_piece_ids, bg_col2, suffix)
				continue
		if style == "opaque_rotated_piece":
			var tex2: Texture2D = canvas._skin.get_piece_texture(piece_id)
			if tex2 != null:
				var rot_offset := int(hints.get("rotation_offset_deg", 0))
				var bg_col3 := _read_color_hint(hints, "bg_color", Color("#4c8078"))
				draw_opaque_rotated_piece(canvas, footprint_rect, tex2, int(info.get("rotation", 0)), rot_offset, bg_col3, 1.0)
				continue
		if piece_id == "restaurant":
			var tex: Texture2D = canvas._skin.get_piece_texture(piece_id)
			var offset_px: Vector2i = canvas._skin.get_piece_offset_px(piece_id)
			var scale: Vector2 = canvas._skin.get_piece_scale(piece_id)
			var pos_px := Vector2(min_pos.x * cell_size, min_pos.y * cell_size) + Vector2(offset_px.x, offset_px.y)
			var size_px := Vector2(size_cells.x * cell_size, size_cells.y * cell_size) * scale
			var rect := Rect2(pos_px, size_px)
			draw_restaurant(canvas, cell_size, anchor, info, rect, 1.0, restaurant_logo_piece_ids)
			continue
		draw_generic_piece(canvas, cell_size, info, 1.0)

static func draw_player_logo_piece(
	canvas,
	cell_size: int,
	structure_rect: Rect2,
	alpha: float,
	restaurant_logo_piece_ids: Array,
	owner_id: int,
	logo_variant_suffix: String = ""
) -> void:
	if owner_id < 0:
		return
	if canvas == null or canvas._skin == null:
		return
	if restaurant_logo_piece_ids.is_empty():
		return

	var logo_map: Dictionary = canvas._player_restaurant_logo_ids
	var logo_id := int(logo_map.get(owner_id, -1))
	if logo_id < 0 or logo_id >= restaurant_logo_piece_ids.size():
		return

	var base_key: String = str(restaurant_logo_piece_ids[logo_id])
	var logo_key := base_key
	var suffix := str(logo_variant_suffix).strip_edges()
	if not suffix.is_empty():
		var var_key := "%s%s" % [base_key, suffix]
		if canvas._skin.piece_textures.has(var_key):
			logo_key = var_key

	var tex: Texture2D = canvas._skin.get_piece_texture(logo_key)
	var mod := Color(1, 1, 1, 0.92 * clampf(alpha, 0.0, 1.0))
	canvas.draw_texture_rect(tex, structure_rect, false, mod)

static func draw_house_id_structure(canvas, cell_size: int, info: Dictionary, structure_rect: Rect2, bg_color: Color, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	if structure_rect.size == Vector2.ZERO:
		return

	var a := clampf(alpha, 0.0, 1.0)
	var bg := bg_color
	bg.a = a
	canvas.draw_rect(structure_rect, bg, true)

	var pid: String = str(info.get("piece_id", "")).strip_edges()
	if pid.is_empty():
		return
	var tex: Texture2D = canvas._skin.get_piece_texture(pid)

	var pad := maxf(1.0, float(cell_size) * 0.08)
	var bottom_gap := maxf(2.0, float(cell_size) * 0.10)
	var tex_rect := structure_rect.grow(-pad)
	tex_rect.size.y = maxf(0.0, tex_rect.size.y - bottom_gap)
	TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, tex_rect, Color(1, 1, 1, 0.9 * a), "bottom")

	var house_id: String = str(info.get("house_id", ""))
	draw_house_id(canvas, cell_size, structure_rect, house_id)

static func draw_player_logo_structure(
	canvas,
	cell_size: int,
	_anchor: Vector2i,
	info: Dictionary,
	structure_rect: Rect2,
	alpha: float,
	restaurant_logo_piece_ids: Array,
	bg_color: Color,
	logo_variant_suffix: String = ""
) -> void:
	var owner := int(info.get("owner", -1))
	if owner < 0:
		return
	if canvas == null or canvas._skin == null:
		return
	if restaurant_logo_piece_ids.is_empty():
		return

	var logo_map: Dictionary = canvas._player_restaurant_logo_ids
	var logo_id := int(logo_map.get(owner, -1))
	if logo_id < 0 or logo_id >= restaurant_logo_piece_ids.size():
		return

	var base_key: String = str(restaurant_logo_piece_ids[logo_id])
	var logo_key := base_key
	var suffix := str(logo_variant_suffix).strip_edges()
	if not suffix.is_empty():
		var var_key := "%s%s" % [base_key, suffix]
		if canvas._skin.piece_textures.has(var_key):
			logo_key = var_key

	var tex: Texture2D = canvas._skin.get_piece_texture(logo_key)
	var bg := bg_color
	bg.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(structure_rect, bg, true)

	var pad := maxf(2.0, float(cell_size) * 0.10)
	var logo_rect := structure_rect.grow(-pad)
	TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, logo_rect, Color(1, 1, 1, 0.98 * alpha))

static func draw_opaque_rotated_piece(canvas, rect: Rect2, tex: Texture2D, rotation_deg: int, rotation_offset_deg: int, bg_color: Color, alpha: float = 1.0) -> void:
	if canvas == null:
		return
	if tex == null:
		return

	# Paint an opaque background first (useful for pieces that should hide roads underneath).
	var bg := bg_color
	bg.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(rect, bg, true)

	# Shrink inside the footprint; fill remaining space with background color.
	var pad := maxf(2.0, minf(rect.size.x, rect.size.y) * 0.10)
	var inner := rect.grow(-pad)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		inner = rect

	var rot := int(rotation_deg) % 360
	if rot < 0:
		rot += 360
	if not rot in [0, 90, 180, 270]:
		rot = 0
	var tex_rot := (rot + int(rotation_offset_deg)) % 360

	var center := inner.position + inner.size * 0.5
	var local_size := inner.size
	if tex_rot == 90 or tex_rot == 270:
		local_size = Vector2(inner.size.y, inner.size.x)

	var mod := Color(1, 1, 1, 1)
	mod.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_set_transform(center, deg_to_rad(float(tex_rot)), Vector2.ONE)
	TextureUtilsClass.draw_texture_aspect_fill(canvas, tex, Rect2(-local_size * 0.5, local_size), mod)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_restaurant(
	canvas,
	cell_size: int,
	anchor: Vector2i,
	info: Dictionary,
	structure_rect: Rect2,
	alpha: float,
	restaurant_logo_piece_ids: Array
) -> void:
	var owner := int(info.get("owner", -1))
	if owner < 0:
		return
	if canvas._skin == null:
		return
	if restaurant_logo_piece_ids.is_empty():
		return

	var logo_map: Dictionary = canvas._player_restaurant_logo_ids
	var logo_id := int(logo_map.get(owner, -1))
	if logo_id < 0 or logo_id >= restaurant_logo_piece_ids.size():
		return

	var logo_key: String = restaurant_logo_piece_ids[logo_id]
	var tex: Texture2D = canvas._skin.get_piece_texture(logo_key)
	var bg := Color("#f4edd1")
	bg.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(structure_rect, bg, true)

	var logo_rect := structure_rect.grow(-maxf(2.0, float(cell_size) * 0.10))
	TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, logo_rect, Color(1, 1, 1, 0.98 * alpha))

	draw_restaurant_entrance_marker(canvas, cell_size, anchor, info, alpha)

	if bool(info.get("opening_soon", false)):
		draw_restaurant_opening_soon_badge(canvas, cell_size, structure_rect, alpha)

	# move_restaurant：高亮当前选中的餐厅（入口 anchor 匹配）。
	var selected_anchor_val = canvas.get("_move_restaurant_selected_anchor") if canvas != null else null
	if selected_anchor_val is Vector2i and Vector2i(selected_anchor_val) == anchor:
		var outline_w := maxf(2.0, float(cell_size) * 0.08)
		outline_w = minf(outline_w, float(cell_size))
		var outline_col := Color(0.2, 0.8, 1.0, 0.9 * clampf(alpha, 0.0, 1.0))
		canvas.draw_rect(structure_rect, outline_col, false, outline_w)

	# procure_drinks：高亮当前选择的起点餐厅 + 在多餐厅时显示序号。
	var procure_anchor_val = canvas.get("_procure_drinks_selected_restaurant_anchor") if canvas != null else null
	var is_procure_selected := procure_anchor_val is Vector2i and Vector2i(procure_anchor_val) == anchor
	if is_procure_selected:
		var outline_w2 := maxf(2.0, float(cell_size) * 0.08)
		outline_w2 = minf(outline_w2, float(cell_size))
		var outline_col2 := Color(1.0, 0.85, 0.2, 0.95 * clampf(alpha, 0.0, 1.0))
		canvas.draw_rect(structure_rect, outline_col2, false, outline_w2)

	# procure_drinks：hover 预览高亮（非选中态）。
	var hover_anchor_val = canvas.get("_procure_drinks_hovered_restaurant_anchor") if canvas != null else null
	var is_procure_hovered := hover_anchor_val is Vector2i and Vector2i(hover_anchor_val) == anchor
	if is_procure_hovered and not is_procure_selected:
		var outline_w3 := maxf(2.0, float(cell_size) * 0.07)
		outline_w3 = minf(outline_w3, float(cell_size))
		var outline_col3 := Color(0.35, 0.8, 1.0, 0.90 * clampf(alpha, 0.0, 1.0))
		canvas.draw_rect(structure_rect, outline_col3, false, outline_w3)

	var idx_map_val = canvas.get("_procure_drinks_restaurant_index_by_anchor") if canvas != null else null
	if idx_map_val is Dictionary:
		var idx_val = (idx_map_val as Dictionary).get(anchor, 0)
		var idx := 0
		if idx_val is int:
			idx = int(idx_val)
		elif idx_val is float:
			var f: float = float(idx_val)
			if f == floor(f):
				idx = int(f)
		if idx > 0:
			draw_restaurant_index(canvas, cell_size, structure_rect, idx, alpha)

static func draw_restaurant_entrance_marker(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, alpha: float = 1.0) -> void:
	var min_pos_val = info.get("min", null)
	var max_pos_val = info.get("max", null)
	if not (min_pos_val is Vector2i) or not (max_pos_val is Vector2i):
		return
	var min_pos: Vector2i = min_pos_val
	var max_pos: Vector2i = max_pos_val

	var drive_thru_active := false
	var owner := int(info.get("owner", -1))
	if owner >= 0 and canvas != null:
		var dt_map_val = canvas.get("_drive_thru_active_by_owner") if canvas != null else null
		if dt_map_val is Dictionary:
			var dt_map: Dictionary = dt_map_val
			var v = dt_map.get(owner, false)
			if v is bool:
				drive_thru_active = bool(v)

	if drive_thru_active:
		_draw_restaurant_entrance_l_marker(canvas, cell_size, Vector2i(min_pos.x, min_pos.y), min_pos, max_pos, alpha)
		_draw_restaurant_entrance_l_marker(canvas, cell_size, Vector2i(max_pos.x, min_pos.y), min_pos, max_pos, alpha)
		_draw_restaurant_entrance_l_marker(canvas, cell_size, Vector2i(min_pos.x, max_pos.y), min_pos, max_pos, alpha)
		_draw_restaurant_entrance_l_marker(canvas, cell_size, Vector2i(max_pos.x, max_pos.y), min_pos, max_pos, alpha)
		return

	var entrance_view: Vector2i = canvas._world_to_view(anchor)
	if entrance_view.x < min_pos.x or entrance_view.x > max_pos.x or entrance_view.y < min_pos.y or entrance_view.y > max_pos.y:
		return
	_draw_restaurant_entrance_l_marker(canvas, cell_size, entrance_view, min_pos, max_pos, alpha)

static func _draw_restaurant_entrance_l_marker(canvas, cell_size: int, entrance_view: Vector2i, min_pos: Vector2i, max_pos: Vector2i, alpha: float) -> void:
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

static func draw_restaurant_opening_soon_badge(canvas, cell_size: int, structure_rect: Rect2, alpha: float = 1.0) -> void:
	if canvas == null:
		return
	var text := "即将开业"
	var a := clampf(alpha, 0.0, 1.0)
	if a <= 0.001:
		return

	var pad := maxf(2.0, float(cell_size) * 0.08)
	var badge_h := maxf(14.0, float(cell_size) * 0.44)
	var badge_w := minf(structure_rect.size.x - pad * 2.0, structure_rect.size.x * 0.78)
	badge_w = maxf(badge_w, float(cell_size) * 1.20)
	badge_w = minf(badge_w, structure_rect.size.x - pad * 2.0)
	if badge_w <= 1.0:
		return

	var pos := structure_rect.position
	var x := pos.x + (structure_rect.size.x - badge_w) * 0.5
	var y := pos.y + structure_rect.size.y - badge_h - maxf(1.0, float(cell_size) * 0.06)
	var badge_rect := Rect2(Vector2(x, y), Vector2(badge_w, badge_h))

	var bg := Color(0, 0, 0, 0.45 * a)
	canvas.draw_rect(badge_rect, bg, true)

	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(10, int(round(float(cell_size) * 0.30)))
	var inner_pad := maxf(3.0, float(cell_size) * 0.12)
	var baseline := badge_rect.position + Vector2(0.0, badge_rect.size.y - inner_pad)
	canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x, font_size, Color(0, 0, 0, 0.85 * a))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x, font_size, Color(1, 1, 1, 1.0 * a))

static func compute_restaurant_index_rect(cell_size: int, structure_rect: Rect2) -> Rect2:
	var pad := maxf(3.0, float(cell_size) * 0.10)
	var bg_size := Vector2(float(cell_size) * 0.80, float(cell_size) * 0.58)
	var pos := structure_rect.position + Vector2(pad, pad)
	return Rect2(pos, bg_size)

static func draw_restaurant_index(canvas, cell_size: int, structure_rect: Rect2, idx: int, alpha: float = 1.0) -> void:
	if idx <= 0:
		return
	var text := str(idx).strip_edges()
	if text.is_empty():
		return
	var label_rect := compute_restaurant_index_rect(cell_size, structure_rect)
	var bg := Color(0, 0, 0, 0.55 * clampf(alpha, 0.0, 1.0))
	canvas.draw_rect(label_rect, bg, true)

	var pad := maxf(3.0, float(cell_size) * 0.12)
	var font_size := maxi(11, int(round(float(cell_size) * 0.34)))
	var font: Font = ThemeDB.fallback_font
	var baseline := label_rect.position + Vector2(0.0, label_rect.size.y - pad)
	canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(0, 0, 0, 0.85))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(1, 1, 1, 1))

static func draw_house_and_garden(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, alpha: float = 1.0) -> void:
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
			var garden_bg := Color("#699055")
			canvas.draw_rect(garden_rect, garden_bg, true)

	# 贴图：房屋主体
	var bottom_gap := maxf(2.0, float(cell_size) * 0.10)
	var house_tex_rect := Rect2(house_rect.position, house_rect.size)
	house_tex_rect.size.y = maxf(0.0, house_tex_rect.size.y - bottom_gap)
	TextureUtilsClass.draw_texture_aspect_fit(canvas, house_tex, house_tex_rect, Color(1, 1, 1, 0.9 * alpha), "bottom")

	# 贴图：花园围栏
	if has_garden and garden_rect.size != Vector2.ZERO:
		var mod := Color(1, 1, 1, 0.9 * alpha)
		# garden_large.png is authored as a horizontal strip; rotate for vertical gardens (E/W).
		if garden_rect.size.y > garden_rect.size.x:
			var center := garden_rect.position + garden_rect.size * 0.5
			var draw_size := Vector2(garden_rect.size.y, garden_rect.size.x)
			canvas.draw_set_transform(center, deg_to_rad(90.0), Vector2.ONE)
			TextureUtilsClass.draw_texture_aspect_fit(canvas, garden_tex, Rect2(-draw_size * 0.5, draw_size), mod)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			TextureUtilsClass.draw_texture_aspect_fit(canvas, garden_tex, garden_rect, mod)

	# 房屋 ID：右上角（仅房屋 2x2 区域）
	var house_id: String = str(info.get("house_id", ""))
	draw_house_id(canvas, cell_size, house_rect, house_id)

static func compute_house_id_rect(cell_size: int, structure_rect: Rect2) -> Rect2:
	var pad := maxf(3.0, float(cell_size) * 0.10)
	var bg_size := Vector2(float(cell_size) * 0.90, float(cell_size) * 0.58)
	var pos := structure_rect.position + Vector2(structure_rect.size.x - bg_size.x - pad, pad)
	return Rect2(pos, bg_size)

static func draw_house_id(canvas, cell_size: int, structure_rect: Rect2, house_id) -> void:
	var text := str(house_id).strip_edges()
	if text.is_empty():
		return
	var pad := maxf(3.0, float(cell_size) * 0.12)
	var font_size := maxi(11, int(round(float(cell_size) * 0.34)))
	var label_rect := compute_house_id_rect(cell_size, structure_rect)

	var font: Font = ThemeDB.fallback_font
	var baseline := label_rect.position + Vector2(0.0, label_rect.size.y - pad)
	canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(0, 0, 0, 0.85))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_RIGHT, label_rect.size.x, font_size, Color(1, 1, 1, 1))

static func _draw_dir_arrow(canvas, rect: Rect2, dir: String, col: Color) -> void:
	var d := str(dir)
	var pad := maxf(2.0, rect.size.x * 0.14)
	var s := minf(rect.size.x, rect.size.y)
	var h := s * 0.26
	var w := s * 0.22
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5

	var points: PackedVector2Array = []
	match d:
		"N":
			points = PackedVector2Array([
				Vector2(cx, rect.position.y + pad),
				Vector2(cx - w, rect.position.y + pad + h),
				Vector2(cx + w, rect.position.y + pad + h),
			])
		"S":
			points = PackedVector2Array([
				Vector2(cx, rect.position.y + rect.size.y - pad),
				Vector2(cx - w, rect.position.y + rect.size.y - pad - h),
				Vector2(cx + w, rect.position.y + rect.size.y - pad - h),
			])
		"E":
			points = PackedVector2Array([
				Vector2(rect.position.x + rect.size.x - pad, cy),
				Vector2(rect.position.x + rect.size.x - pad - h, cy - w),
				Vector2(rect.position.x + rect.size.x - pad - h, cy + w),
			])
		"W":
			points = PackedVector2Array([
				Vector2(rect.position.x + pad, cy),
				Vector2(rect.position.x + pad + h, cy - w),
				Vector2(rect.position.x + pad + h, cy + w),
			])
		_:
			return

	canvas.draw_colored_polygon(points, col)

static func draw_road_overlay_piece(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, overlay: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", "")).strip_edges()
	if piece_id.is_empty():
		return
	var cells_val = info.get("cells", null)
	if not (cells_val is Array):
		return

	var rot := int(info.get("rotation", 0))
	if overlay == null or overlay.is_empty():
		return

	# Base road visuals: reuse the same road textures as normal roads, then overlay arrows + roadworks sign.
	var segments_val = overlay.get("segments", null)
	if segments_val is Array:
		var segments: Array = segments_val
		for seg_val in segments:
			if not (seg_val is Dictionary):
				continue
			var seg: Dictionary = seg_val
			var off_val = seg.get("offset", null)
			var dirs_val = seg.get("dirs", null)
			if not (off_val is Vector2i) or not (dirs_val is Array):
				continue
			var off: Vector2i = off_val
			var world_pos := anchor + MapUtils.rotate_offset(off, rot)
			if not canvas._is_valid_world_pos(world_pos):
				continue
			var vpos: Vector2i = canvas._world_to_view(world_pos)
			var rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size))
			var center := rect.position + rect.size * 0.5

			var dirs: Array = []
			for d in Array(dirs_val):
				var s := str(d).strip_edges()
				if s.is_empty():
					continue
				dirs.append(MapUtils.rotate_dir(s, rot))
			var shape_info := RoadsPassClass.compute_road_shape_info(dirs)
			if shape_info.is_empty():
				continue
			var shape: String = str(shape_info.get("shape", "default"))
			var rot_deg: int = int(shape_info.get("rotation_deg", 0))
			var tex: Texture2D = canvas._skin.get_road_texture(shape)

			var mod := Color(1, 1, 1, 0.92 * clampf(alpha, 0.0, 1.0))
			canvas.draw_set_transform(center, deg_to_rad(float(rot_deg)), Vector2.ONE)
			canvas.draw_texture_rect(tex, Rect2(-rect.size * 0.5, rect.size), false, mod)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Subtle overlay so the footprint is readable on busy maps.
	var fill := Color(0, 0, 0, 0.08 * clampf(alpha, 0.0, 1.0))
	var border := Color(0, 0, 0, 0.22 * clampf(alpha, 0.0, 1.0))
	OverlayUtilsClass.draw_view_cells_overlay(canvas, cell_size, cells_val, fill, border, 1.0)

	var min_pos: Vector2i = info.get("min", Vector2i.ZERO)
	var max_pos: Vector2i = info.get("max", Vector2i.ZERO)
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	var structure_rect := Rect2(
		Vector2(min_pos.x * cell_size, min_pos.y * cell_size),
		Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	)

	var sign_tex: Texture2D = RoadsPassClass.get_roadworks_marker_texture(canvas._skin)
	if sign_tex != null:
		var pad := maxf(2.0, float(cell_size) * 0.12)
		var sign_rect := structure_rect.grow(-pad)
		var sign_dst := TextureUtilsClass.get_texture_aspect_fit_rect(sign_tex, sign_rect)
		TextureUtilsClass.draw_texture_rect_clipped_by_view_cells(
			canvas,
			sign_tex,
			sign_dst,
			cells_val,
			cell_size,
			Color(1, 1, 1, 0.90 * clampf(alpha, 0.0, 1.0))
		)

	var arrows_val = overlay.get("arrows", null)
	if not (arrows_val is Array):
		return
	var arrows: Array = arrows_val
	var arrow_col := Color(0, 0, 0, 0.85 * clampf(alpha, 0.0, 1.0))
	for a_val in arrows:
		if not (a_val is Dictionary):
			continue
		var a: Dictionary = a_val
		var off_val = a.get("offset", null)
		var dir_val = a.get("dir", null)
		if not (off_val is Vector2i) or not (dir_val is String):
			continue
		var off: Vector2i = off_val
		var base_dir: String = str(dir_val)
		var world_from := anchor + MapUtils.rotate_offset(off, rot)
		if not canvas._is_valid_world_pos(world_from):
			continue
		var vpos: Vector2i = canvas._world_to_view(world_from)
		var rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size))
		var d := MapUtils.rotate_dir(base_dir, rot)
		_draw_dir_arrow(canvas, rect, d, arrow_col)

static func draw_park_piece(canvas, cell_size: int, info: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", ""))
	if piece_id.is_empty():
		return
	var cells_val = info.get("cells", null)
	if not (cells_val is Array):
		return

	var base := Color("#587a51")
	var fill := base
	var border := base.darkened(0.25)
	OverlayUtilsClass.draw_view_cells_overlay(canvas, cell_size, cells_val, fill, border, 1.0)

	var min_pos: Vector2i = info.get("min", Vector2i.ZERO)
	var max_pos: Vector2i = info.get("max", Vector2i.ZERO)
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	var structure_rect := Rect2(
		Vector2(min_pos.x * cell_size, min_pos.y * cell_size),
		Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	)

	var tex: Texture2D = canvas._skin.get_piece_texture(piece_id)
	var pad := maxf(1.0, float(cell_size) * 0.06)
	var rect := structure_rect.grow(-pad)
	var dst := TextureUtilsClass.get_texture_aspect_fill_rect(tex, rect)
	TextureUtilsClass.draw_texture_rect_clipped_by_view_cells(
		canvas,
		tex,
		dst,
		cells_val,
		cell_size,
		Color(1, 1, 1, 0.85 * clampf(alpha, 0.0, 1.0))
	)

static func draw_generic_piece(canvas, cell_size: int, info: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", "")).strip_edges()
	if piece_id.is_empty():
		return

	var min_pos: Vector2i = info.get("min", Vector2i.ZERO)
	var max_pos: Vector2i = info.get("max", Vector2i.ZERO)
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	var offset_px: Vector2i = canvas._skin.get_piece_offset_px(piece_id)
	var scale: Vector2 = canvas._skin.get_piece_scale(piece_id)

	var pos_px := Vector2(min_pos.x * cell_size, min_pos.y * cell_size) + Vector2(offset_px.x, offset_px.y)
	var size_px := Vector2(size_cells.x * cell_size, size_cells.y * cell_size) * scale
	var rect := Rect2(pos_px, size_px)

	var tex: Texture2D = canvas._skin.get_piece_texture(piece_id)
	var mod := Color(1, 1, 1, 0.85 * clampf(alpha, 0.0, 1.0))
	canvas.draw_texture_rect(tex, rect, false, mod)
