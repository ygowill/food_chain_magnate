# MapCanvas：_draw 分层渲染逻辑下沉
class_name MapCanvasDrawer
extends RefCounted

static func _get_restaurant_logo_piece_ids(canvas) -> Array:
	if canvas == null or canvas._skin == null:
		return []
	if canvas._skin.has_method("get_restaurant_logo_piece_ids"):
		var ids_val = canvas._skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			return ids_val
	return []

const TextureUtilsClass = preload("res://ui/scenes/game/map/drawer/texture_utils.gd")
const OverlayUtilsClass = preload("res://ui/scenes/game/map/drawer/overlay_utils.gd")
const MarketingPassClass = preload("res://ui/scenes/game/map/drawer/passes/marketing_pass.gd")
const GroundPassClass = preload("res://ui/scenes/game/map/drawer/passes/ground_pass.gd")
const RoadsPassClass = preload("res://ui/scenes/game/map/drawer/passes/roads_pass.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map/drawer/passes/structures_pass.gd")
const TilesPassClass = preload("res://ui/scenes/game/map/drawer/passes/tiles_pass.gd")
const PieceUiHintsRegistryClass = preload("res://core/rules/piece_ui_hints_registry.gd")

static func _draw_texture_aspect_fit(canvas, texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1), v_align: String = "center") -> void:
	TextureUtilsClass.draw_texture_aspect_fit(canvas, texture, rect, modulate, v_align)

static func _get_texture_aspect_fit_rect(texture: Texture2D, rect: Rect2, v_align: String = "center") -> Rect2:
	return TextureUtilsClass.get_texture_aspect_fit_rect(texture, rect, v_align)

static func _get_texture_aspect_fill_rect(texture: Texture2D, rect: Rect2) -> Rect2:
	return TextureUtilsClass.get_texture_aspect_fill_rect(texture, rect)

static func _draw_texture_rect_clipped_by_view_cells(canvas, texture: Texture2D, dst_rect: Rect2, view_cells: Array, cell_size: int, modulate: Color) -> void:
	TextureUtilsClass.draw_texture_rect_clipped_by_view_cells(canvas, texture, dst_rect, view_cells, cell_size, modulate)

static func _draw_texture_aspect_fill(canvas, texture: Texture2D, rect: Rect2, modulate: Color = Color(1, 1, 1, 1)) -> void:
	TextureUtilsClass.draw_texture_aspect_fill(canvas, texture, rect, modulate)

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

static func draw(canvas) -> void:
	if canvas._grid_size == Vector2i.ZERO:
		return
	if canvas._skin == null:
		return

	var cell_size: int = int(canvas.get_cell_size())
	var intro_active := false
	if canvas != null and canvas.has_method("is_intro_reveal_active"):
		intro_active = bool(canvas.call("is_intro_reveal_active"))

	_draw_ground_and_blocked(canvas, cell_size)
	_draw_roads(canvas, cell_size)
	_draw_roadworks_markers(canvas, cell_size)
	# 先画板块边框（底层），避免盖住上层 piece（房屋/餐厅/营销等）。
	_draw_tile_borders(canvas, cell_size)
	_draw_drink_sources(canvas, cell_size)
	_draw_structures(canvas, cell_size)
	_draw_house_demands(canvas, cell_size)
	_draw_marketing(canvas, cell_size)
	# tile_id 文本属于调试信息，允许覆盖上层内容。
	_draw_tile_id_labels(canvas, cell_size)
	if not intro_active:
		_draw_cell_highlights(canvas, cell_size)
		_draw_piece_overlays(canvas, cell_size)
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

static func _is_scatter_rect_free(candidate: Rect2, taken: Array[Rect2], min_spacing: float) -> bool:
	var grow := maxf(min_spacing, 0.0)
	var cand := candidate.grow(grow)
	for r in taken:
		if cand.intersects(r.grow(grow)):
			return false
	return true

static func _shuffle_rect2_array(rng: RandomNumberGenerator, arr: Array[Rect2]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func _build_demand_token_slots(
	area: Rect2,
	icon_size: float,
	min_spacing: float,
	reserved: Array[Rect2]
) -> Array[Rect2]:
	var margin := maxf(1.0, min_spacing)
	var min_x := area.position.x + margin
	var min_y := area.position.y + margin
	var max_x := area.position.x + area.size.x - icon_size - margin
	var max_y := area.position.y + area.size.y - icon_size - margin
	if max_x < min_x:
		max_x = min_x
	if max_y < min_y:
		max_y = min_y

	var step := maxf(icon_size + min_spacing, 1.0)
	var cols := maxi(1, int(floor(maxf(0.0, max_x - min_x) / step)) + 1)
	var rows := maxi(1, int(floor(maxf(0.0, max_y - min_y) / step)) + 1)

	var slots: Array[Rect2] = []
	for row in range(rows):
		for col in range(cols):
			var x := min_x + float(col) * step
			var y := min_y + float(row) * step
			x = clampf(x, min_x, max_x)
			y = clampf(y, min_y, max_y)
			var rect := Rect2(Vector2(x, y), Vector2(icon_size, icon_size))
			if _is_scatter_rect_free(rect, reserved, min_spacing):
				slots.append(rect)
	return slots

static func _draw_cells_overlay(canvas, cell_size: int, world_cells: Array, fill: Color, border: Color, border_width: float) -> void:
	OverlayUtilsClass.draw_cells_overlay(canvas, cell_size, world_cells, fill, border, border_width)

static func _draw_view_cells_overlay(canvas, cell_size: int, view_cells_any: Array, fill: Color, border: Color, border_width: float) -> void:
	OverlayUtilsClass.draw_view_cells_overlay(canvas, cell_size, view_cells_any, fill, border, border_width)

static func _draw_cell_highlights(canvas, cell_size: int) -> void:
	if canvas._highlighted_cells.is_empty():
		return

	var base := Color("#f5b9a6")
	var fill := base
	fill.a = 0.66
	var border := base
	border.a = 0.35

	var cells: Array[Vector2i] = []
	for pos_val in canvas._highlighted_cells.keys():
		if pos_val is Vector2i:
			cells.append(pos_val)
	_draw_cells_overlay(canvas, cell_size, cells, fill, border, 1.0)

static func _draw_piece_overlays(canvas, cell_size: int) -> void:
	var overlays_val = canvas.get("_piece_overlays") if canvas != null else null
	if not (overlays_val is Dictionary):
		return
	var overlays: Dictionary = overlays_val
	if overlays.is_empty():
		return

	var keys: Array[String] = []
	for k in overlays.keys():
		keys.append(str(k))
	keys.sort()

	for key in keys:
		var ov_val = overlays.get(key, null)
		if not (ov_val is Dictionary):
			continue
		var ov: Dictionary = ov_val
		var cells_val = ov.get("cells", null)
		if not (cells_val is Array):
			continue
		var fill_val = ov.get("fill", null)
		var border_val = ov.get("border", null)
		var bw_val = ov.get("border_width", null)

		var fill = fill_val if fill_val is Color else Color(1, 1, 1, 0)
		var border = border_val if border_val is Color else Color(1, 1, 1, 0)
		var bw := 2.0
		if bw_val is float:
			bw = float(bw_val)
		elif bw_val is int:
			bw = float(int(bw_val))

		_draw_cells_overlay(canvas, cell_size, cells_val, fill, border, bw)

static func _draw_structure_preview(canvas, cell_size: int) -> void:
	if canvas._structure_preview_cells.is_empty():
		return

	var preview_info_val = canvas._structure_preview_info
	if preview_info_val is Dictionary and not preview_info_val.is_empty():
		_draw_structure_preview_piece(canvas, cell_size, preview_info_val)

	var fill := Color(0.2, 0.9, 0.35, 0.28) if canvas._structure_preview_valid else Color(0.95, 0.25, 0.25, 0.25)
	var border := Color(0.2, 0.9, 0.35, 0.75) if canvas._structure_preview_valid else Color(0.95, 0.25, 0.25, 0.75)
	var border_w := 2.0

	# Allow preview_info to override highlight style (used by generic overlays).
	if preview_info_val is Dictionary:
		var d: Dictionary = preview_info_val
		var fill_val = d.get("highlight_fill", null)
		if fill_val is Color:
			fill = fill_val
		var border_val = d.get("highlight_border", null)
		if border_val is Color:
			border = border_val
		var bw_val = d.get("highlight_border_width", null)
		if bw_val is float:
			border_w = float(bw_val)
		elif bw_val is int:
			border_w = float(int(bw_val))

	_draw_cells_overlay(canvas, cell_size, canvas._structure_preview_cells, fill, border, border_w)

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
	var view_cells: Array[Vector2i] = []
	for world_pos in canvas._structure_preview_cells:
		if not (world_pos is Vector2i):
			continue
		var vpos: Vector2i = canvas._world_to_view(world_pos)
		view_cells.append(vpos)
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
		"cells": view_cells,
	}

	var logo_piece_ids: Array = _get_restaurant_logo_piece_ids(canvas)

	if piece_id == "restaurant":
		StructuresPassClass.draw_restaurant(canvas, cell_size, anchor, info, structure_rect, alpha, logo_piece_ids)
	elif piece_id == "house" or piece_id == "house_with_garden":
		StructuresPassClass.draw_house_and_garden(canvas, cell_size, anchor, info, alpha)
	elif piece_id == "marketing":
		# Marketing preview is drawn as a semi-transparent piece (issue_tracker #36).
		var p := {
			"type": str(preview_info.get("type", preview_info.get("marketing_type", "default"))),
			"product": str(preview_info.get("product", "")),
		}
		_draw_marketing_placement(canvas, cell_size, p, 0.55, structure_rect)
	else:
			var road_overlay := PieceUiHintsRegistryClass.get_road_overlay(piece_id)
			if not road_overlay.is_empty():
				StructuresPassClass.draw_road_overlay_piece(canvas, cell_size, anchor, info, road_overlay, alpha)
			else:
				var hints := PieceUiHintsRegistryClass.get_hints(piece_id)
				var style := str(hints.get("structure_style", "")).strip_edges()
				var drew := false
				if style == "house_id":
					StructuresPassClass.draw_house_id_structure(canvas, cell_size, info, structure_rect, StructuresPassClass.HOUSE_BG_COLOR, alpha)
					drew = true
				elif style == "player_logo_bg":
					var owner2 := int(info.get("owner", -1))
					if owner2 >= 0:
						var bg_col2 := _read_color_hint(hints, "bg_color", Color("#f4edd1"))
						var suffix := str(hints.get("logo_variant_suffix", "")).strip_edges()
						StructuresPassClass.draw_player_logo_structure(canvas, cell_size, anchor, info, structure_rect, alpha, logo_piece_ids, bg_col2, suffix)
						drew = true
				elif style == "opaque_rotated_piece":
					var tex2: Texture2D = canvas._skin.get_piece_texture(piece_id)
					if tex2 != null:
						var rot_offset := int(hints.get("rotation_offset_deg", 0))
						var bg_col3 := _read_color_hint(hints, "bg_color", Color("#4c8078"))
						StructuresPassClass.draw_opaque_rotated_piece(canvas, cell_size, structure_rect, tex2, rotation, rot_offset, bg_col3, alpha)
						drew = true

				if not drew:
					var ui_kind := PieceUiHintsRegistryClass.get_kind(piece_id)
					if piece_id == "park" or ui_kind == "park":
						StructuresPassClass.draw_park_piece(canvas, cell_size, info, alpha)
					else:
						StructuresPassClass.draw_generic_piece(canvas, cell_size, info, alpha)

static func _draw_roadworks_markers(canvas, cell_size: int) -> void:
	RoadsPassClass.draw_roadworks_markers(canvas, cell_size)

static func _draw_ground_and_blocked(canvas, cell_size: int) -> void:
	GroundPassClass.draw_ground_and_blocked(canvas, cell_size)

static func _draw_roads(canvas, cell_size: int) -> void:
	RoadsPassClass.draw_roads(canvas, cell_size)

static func _draw_drink_sources(canvas, cell_size: int) -> void:
	StructuresPassClass.draw_drink_sources(canvas, cell_size)

static func _draw_structures(canvas, cell_size: int) -> void:
	StructuresPassClass.draw_structures(canvas, cell_size, _get_restaurant_logo_piece_ids(canvas))

static func _draw_marketing(canvas, cell_size: int) -> void:
	MarketingPassClass.draw_marketing(canvas, cell_size)

static func _draw_marketing_placement(canvas, cell_size: int, placement: Dictionary, alpha: float, rect_override: Rect2 = Rect2()) -> void:
	MarketingPassClass.draw_marketing_placement(canvas, cell_size, placement, alpha, rect_override)

static func _draw_marketing_board_number_badge(canvas, rect: Rect2, board_number: int, cell_size: int, alpha: float) -> void:
	MarketingPassClass.draw_marketing_board_number_badge(canvas, rect, board_number, cell_size, alpha)

static func _draw_house_demands(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	if not canvas._map_data.has("houses") or not (canvas._map_data["houses"] is Dictionary):
		return

	# Demand tokens: prefer large icons, but shrink per-house as needed to fit the rule cap
	# (3 for normal houses, 5 for garden houses) across zoom levels.
	var base_icon_size := float(cell_size) * 0.90
	var base_min_spacing := maxf(1.0, float(cell_size) * 0.04)

	for anchor_val in canvas._structures_by_anchor.keys():
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		if canvas != null and canvas.has_method("is_intro_world_pos_revealed"):
			if not bool(canvas.call("is_intro_world_pos_revealed", anchor)):
				continue
		var info: Dictionary = canvas._structures_by_anchor[anchor]

		var piece_id: String = str(info.get("piece_id", "")).strip_edges()
		if piece_id.is_empty():
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

		var rotation: int = int(info.get("rotation", 0))
		var house_mask := [[1, 1], [1, 1]]
		var house_cells_world: Array[Vector2i] = MapUtils.get_footprint_cells(house_mask, Vector2i.ZERO, anchor, rotation)
		if house_cells_world.is_empty():
			continue
		var hmin := Vector2i(2147483647, 2147483647)
		var hmax := Vector2i(-2147483648, -2147483648)
		for wpos in house_cells_world:
			var vpos: Vector2i = canvas._world_to_view(wpos)
			hmin.x = min(hmin.x, vpos.x)
			hmin.y = min(hmin.y, vpos.y)
			hmax.x = max(hmax.x, vpos.x)
			hmax.y = max(hmax.y, vpos.y)
		var hsize_cells := (hmax - hmin) + Vector2i.ONE
		var house_rect := Rect2(Vector2(hmin.x * cell_size, hmin.y * cell_size), Vector2(hsize_cells.x * cell_size, hsize_cells.y * cell_size))

		var demand_area_rect := house_rect
		if piece_id == "house_with_garden":
			# Garden houses can have more demands; allow spilling tokens into the garden area for visibility.
			demand_area_rect = structure_rect

		var hidden_counts := {}
		if canvas != null and canvas.has_method("get_hidden_demand_counts_for_house"):
			var hidden_val = canvas.call("get_hidden_demand_counts_for_house", house_id)
			if hidden_val is Dictionary:
				hidden_counts = hidden_val

		var product_ids: Array[String] = []
		for d_val in demands:
			if not (d_val is Dictionary):
				continue
			var d: Dictionary = d_val
			var product_id: String = str(d.get("product", ""))
			if product_id.is_empty():
				continue
			var hidden_left := int(hidden_counts.get(product_id, 0))
			if hidden_left > 0:
				hidden_counts[product_id] = hidden_left - 1
				continue
			product_ids.append(product_id)
		if product_ids.is_empty():
			continue
		product_ids.sort()
		var draw_count: int = min(product_ids.size(), 6)
		var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

		# Seed depends on demand content so adding/removing demands repositions all tokens.
		var demand_key := ",".join(product_ids)
		var seed := _compute_demand_scatter_seed(canvas, house_id)
		seed = int((seed ^ _hash_string_32(demand_key)) & 0x7FFFFFFF)

		var reserved: Array[Rect2] = []
		reserved.append(StructuresPassClass.compute_house_id_rect(cell_size, house_rect))

		var slots: Array[Rect2] = []
		var icon_size := base_icon_size
		var min_spacing := base_min_spacing
		var scales := [1.0, 0.86, 0.74, 0.62, 0.50]
		for scale in scales:
			icon_size = base_icon_size * float(scale)
			min_spacing = base_min_spacing * float(scale)
			var scatter_area_rect := demand_area_rect.grow(-float(cell_size) * 0.05)
			slots = _build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
			if slots.size() < draw_count:
				slots = _build_demand_token_slots(demand_area_rect, icon_size, min_spacing, reserved)
			if slots.size() >= draw_count:
				break
		if slots.is_empty():
			continue
		var actual_draw_count: int = min(draw_count, slots.size())

		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		rng.state = int(seed)
		_shuffle_rect2_array(rng, slots)

		for i in range(actual_draw_count):
			var product_id: String = draw_product_ids[i]
			if product_id.is_empty():
				continue
			var tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)
			_draw_texture_aspect_fit(canvas, tex, slots[i], Color(1, 1, 1, 0.95))

static func _draw_selection(canvas, cell_size: int) -> void:
	# 关闭“点击格子选中框”视觉（issue_tracker #31）：保留 cell_selected 信号用于交互逻辑。
	var hover_ok := false
	if canvas != null:
		if canvas.has_method("is_interactive_world_pos"):
			hover_ok = bool(canvas.call("is_interactive_world_pos", canvas._hover_pos))
		else:
			hover_ok = bool(canvas._is_valid_world_pos(canvas._hover_pos))
	if hover_ok:
		var show_hover := _read_globals_bool("show_cell_hover_tooltip", false)
		if not show_hover:
			return
		var v2 = canvas._world_to_view(canvas._hover_pos)
		var rect2 := Rect2(Vector2(v2.x * cell_size, v2.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect2, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

static func _read_globals_bool(key: String, fallback: bool) -> bool:
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		var globals = (tree as SceneTree).root.get_node_or_null("Globals")
		if globals != null:
			var val = globals.get(key)
			if val is bool:
				return bool(val)
	return fallback

static func _draw_tile_borders(canvas, cell_size: int) -> void:
	TilesPassClass.draw_tile_borders(canvas, cell_size)

static func _draw_tile_id_labels(canvas, cell_size: int) -> void:
	TilesPassClass.draw_tile_id_labels(canvas, cell_size)
