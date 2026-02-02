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

const TextureUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_texture_utils.gd")
const MarketingPassClass = preload("res://ui/scenes/game/map_canvas_drawer_marketing_pass.gd")
const GroundPassClass = preload("res://ui/scenes/game/map_canvas_drawer_ground_pass.gd")
const TilesPassClass = preload("res://ui/scenes/game/map_canvas_drawer_tiles_pass.gd")

const LobbyistsRoadOverlaysClass = preload("res://modules/lobbyists/road_overlays.gd")
const LOBBYISTS_ROADWORK_MARKERS_KEY := LobbyistsRoadOverlaysClass.ROADWORK_MARKERS_KEY

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

static func draw(canvas) -> void:
	if canvas._grid_size == Vector2i.ZERO:
		return
	if canvas._skin == null:
		return

	var cell_size: int = int(canvas.get_cell_size())

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
	if world_cells.is_empty():
		return
	if fill.a <= 0.0 and border.a <= 0.0:
		return

	var bw := clampf(border_width, 0.0, float(cell_size))

	# Convert to view cells and dedupe.
	var view_set := {}
	var view_cells: Array[Vector2i] = []
	for cell_val in world_cells:
		if not (cell_val is Vector2i):
			continue
		var wpos: Vector2i = cell_val
		if not canvas._is_valid_world_pos(wpos):
			continue
		var vpos_val = canvas._world_to_view(wpos)
		if not (vpos_val is Vector2i):
			continue
		var vpos: Vector2i = vpos_val
		if view_set.has(vpos):
			continue
		view_set[vpos] = true
		view_cells.append(vpos)

		if fill.a > 0.0:
			var rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size))
			canvas.draw_rect(rect, fill, true)

	# Draw border only on the outer perimeter (no internal grid lines).
	if border.a <= 0.0 or bw <= 0.0:
		return

	for vpos in view_cells:
		var base := Vector2(float(vpos.x * cell_size), float(vpos.y * cell_size))

		if not view_set.has(vpos + Vector2i(-1, 0)):
			canvas.draw_rect(Rect2(base, Vector2(bw, float(cell_size))), border, true)
		if not view_set.has(vpos + Vector2i(1, 0)):
			canvas.draw_rect(Rect2(base + Vector2(float(cell_size) - bw, 0.0), Vector2(bw, float(cell_size))), border, true)
		if not view_set.has(vpos + Vector2i(0, -1)):
			canvas.draw_rect(Rect2(base, Vector2(float(cell_size), bw)), border, true)
		if not view_set.has(vpos + Vector2i(0, 1)):
			canvas.draw_rect(Rect2(base + Vector2(0.0, float(cell_size) - bw), Vector2(float(cell_size), bw)), border, true)

static func _draw_view_cells_overlay(canvas, cell_size: int, view_cells_any: Array, fill: Color, border: Color, border_width: float) -> void:
	if view_cells_any.is_empty():
		return
	if fill.a <= 0.0 and border.a <= 0.0:
		return

	var bw := clampf(border_width, 0.0, float(cell_size))

	var view_set := {}
	var view_cells: Array[Vector2i] = []
	for v in view_cells_any:
		if not (v is Vector2i):
			continue
		var p: Vector2i = v
		if view_set.has(p):
			continue
		view_set[p] = true
		view_cells.append(p)

	for p2 in view_cells:
		if fill.a <= 0.0:
			continue
		var rect := Rect2(Vector2(p2.x * cell_size, p2.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, fill, true)

	if border.a <= 0.0 or bw <= 0.0:
		return

	for p3 in view_cells:
		var base := Vector2(float(p3.x * cell_size), float(p3.y * cell_size))
		if not view_set.has(p3 + Vector2i(-1, 0)):
			canvas.draw_rect(Rect2(base, Vector2(bw, float(cell_size))), border, true)
		if not view_set.has(p3 + Vector2i(1, 0)):
			canvas.draw_rect(Rect2(base + Vector2(float(cell_size) - bw, 0.0), Vector2(bw, float(cell_size))), border, true)
		if not view_set.has(p3 + Vector2i(0, -1)):
			canvas.draw_rect(Rect2(base, Vector2(float(cell_size), bw)), border, true)
		if not view_set.has(p3 + Vector2i(0, 1)):
			canvas.draw_rect(Rect2(base + Vector2(0.0, float(cell_size) - bw), Vector2(float(cell_size), bw)), border, true)

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

	if piece_id == "restaurant":
		_draw_restaurant(canvas, cell_size, anchor, info, structure_rect, alpha)
	elif piece_id == "house" or piece_id == "house_with_garden":
		_draw_house_and_garden(canvas, cell_size, anchor, info, alpha)
	elif piece_id == "marketing":
		# Marketing preview is drawn as a semi-transparent piece (issue_tracker #36).
		var p := {
			"type": str(preview_info.get("type", preview_info.get("marketing_type", "default"))),
			"product": str(preview_info.get("product", "")),
		}
		_draw_marketing_placement(canvas, cell_size, p, 0.55, structure_rect)
	elif piece_id.begins_with("lobbyists_road_"):
		_draw_lobbyists_road_piece(canvas, cell_size, anchor, info, alpha)
	elif piece_id == "park" or piece_id.begins_with("lobbyists_park_"):
		_draw_park_piece(canvas, cell_size, info, alpha)
	else:
		_draw_generic_piece(canvas, cell_size, info, alpha)

static func _draw_lobbyists_roadworks_markers(canvas, cell_size: int) -> void:
	if canvas == null or canvas._skin == null:
		return
	if not (canvas._map_data is Dictionary):
		return
	var markers_val = canvas._map_data.get(LOBBYISTS_ROADWORK_MARKERS_KEY, null)
	if not (markers_val is Dictionary):
		return
	var markers: Dictionary = markers_val
	if markers.is_empty():
		return

	var tex: Texture2D = canvas._skin.get_piece_texture("lobbyists_roadworks_marker")
	var pad := maxf(2.0, float(cell_size) * 0.08)
	var mod := Color(1, 1, 1, 0.95)

	for k in markers.keys():
		if not (k is String):
			continue
		var parts := str(k).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var world_pos := Vector2i(int(parts[0]), int(parts[1]))
		if not canvas._is_valid_world_pos(world_pos):
			continue
		var vpos: Vector2i = canvas._world_to_view(world_pos)
		var rect := Rect2(Vector2(vpos.x * cell_size, vpos.y * cell_size), Vector2(cell_size, cell_size)).grow(-pad)
		_draw_texture_aspect_fit(canvas, tex, rect, mod)

static func _draw_roadworks_markers(canvas, cell_size: int) -> void:
	# Backward-compat alias (older code paths may call this name).
	_draw_lobbyists_roadworks_markers(canvas, cell_size)

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

static func _draw_lobbyists_road_piece(canvas, cell_size: int, anchor: Vector2i, info: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", ""))
	if piece_id.is_empty():
		return
	var cells_val = info.get("cells", null)
	if not (cells_val is Array):
		return

	var rot := int(info.get("rotation", 0))

	var overlay_val = LobbyistsRoadOverlaysClass.ROAD_OVERLAYS.get(piece_id, null)
	if not (overlay_val is Dictionary):
		return
	var overlay: Dictionary = overlay_val

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
			var shape_info := _compute_road_shape_info(dirs)
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
	_draw_view_cells_overlay(canvas, cell_size, cells_val, fill, border, 1.0)

	var min_pos: Vector2i = info.get("min", Vector2i.ZERO)
	var max_pos: Vector2i = info.get("max", Vector2i.ZERO)
	var size_cells := (max_pos - min_pos) + Vector2i.ONE
	var structure_rect := Rect2(
		Vector2(min_pos.x * cell_size, min_pos.y * cell_size),
		Vector2(size_cells.x * cell_size, size_cells.y * cell_size)
	)

	var sign_tex: Texture2D = canvas._skin.get_piece_texture("lobbyists_roadworks_marker")
	var pad := maxf(2.0, float(cell_size) * 0.12)
	var sign_rect := structure_rect.grow(-pad)
	var sign_dst := _get_texture_aspect_fit_rect(sign_tex, sign_rect)
	_draw_texture_rect_clipped_by_view_cells(
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

static func _draw_park_piece(canvas, cell_size: int, info: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", ""))
	if piece_id.is_empty():
		return
	var cells_val = info.get("cells", null)
	if not (cells_val is Array):
		return

	var fill := Color("#22C55E")
	fill.a = clampf(alpha, 0.0, 1.0)
	var border := Color("#22C55E")
	border.a = clampf(alpha, 0.0, 1.0)
	_draw_view_cells_overlay(canvas, cell_size, cells_val, fill, border, 1.0)

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
	var dst := _get_texture_aspect_fill_rect(tex, rect)
	_draw_texture_rect_clipped_by_view_cells(
		canvas,
		tex,
		dst,
		cells_val,
		cell_size,
		Color(1, 1, 1, 0.85 * clampf(alpha, 0.0, 1.0))
	)

static func _draw_generic_piece(canvas, cell_size: int, info: Dictionary, alpha: float = 1.0) -> void:
	if canvas == null or canvas._skin == null:
		return
	var piece_id: String = str(info.get("piece_id", ""))
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

static func _draw_ground_and_blocked(canvas, cell_size: int) -> void:
	GroundPassClass.draw_ground_and_blocked(canvas, cell_size)

static func _draw_roads(canvas, cell_size: int) -> void:
	var pending_extra_dirs := _build_lobbyists_pending_road_connection_dirs(canvas)
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

			# Bridge crossing tiles may store multiple independent segments in one cell.
			# For visuals, if a bridge segment exists, only render bridge=True segments to avoid overlapping artifacts.
			var has_bridge := false
			for s_val in segments:
				if s_val is Dictionary and bool(Dictionary(s_val).get("bridge", false)):
					has_bridge = true
					break
			var segments_to_draw: Array = segments
			if has_bridge:
				segments_to_draw = []
				for s_val in segments:
					if s_val is Dictionary and bool(Dictionary(s_val).get("bridge", false)):
						segments_to_draw.append(s_val)

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			var center := rect.position + rect.size * 0.5

			for seg_index in range(segments_to_draw.size()):
				var seg_val = segments_to_draw[seg_index]
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				var dirs: Array = dirs_val
				var extra_val = pending_extra_dirs.get(world_pos, null)
				if extra_val is Dictionary and not (extra_val as Dictionary).is_empty():
					var eff: Array = []
					var seen := {}
					for d in dirs:
						var s := str(d).strip_edges()
						if s.is_empty():
							continue
						if seen.has(s):
							continue
						seen[s] = true
						eff.append(s)
					for d2 in (extra_val as Dictionary).keys():
						var s2 := str(d2).strip_edges()
						if s2.is_empty():
							continue
						if seen.has(s2):
							continue
						seen[s2] = true
						eff.append(s2)
					dirs = eff
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

static func _build_lobbyists_pending_road_connection_dirs(canvas) -> Dictionary:
	if canvas == null:
		return {}
	if not (canvas._map_data is Dictionary):
		return {}
	var map_data: Dictionary = canvas._map_data
	var pending_val = map_data.get(LobbyistsRoadOverlaysClass.PENDING_ROADS_KEY, null)
	if not (pending_val is Array):
		return {}
	var pending: Array = pending_val
	if pending.is_empty():
		return {}

	var out := {} # Vector2i -> {dir -> true}

	for e_val in pending:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var sbp_val = e.get("segments_by_pos", null)
		if not (sbp_val is Dictionary):
			continue
		var segments_by_pos: Dictionary = sbp_val
		for k in segments_by_pos.keys():
			if not (k is String):
				continue
			var parts := str(k).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				continue
			var world_pos := Vector2i(int(parts[0]), int(parts[1]))
			var seg_list_val = segments_by_pos.get(k, null)
			if not (seg_list_val is Array):
				continue
			for seg_val in Array(seg_list_val):
				if not (seg_val is Dictionary):
					continue
				var seg: Dictionary = seg_val
				var dirs_val = seg.get("dirs", null)
				if not (dirs_val is Array):
					continue
				for d_val in Array(dirs_val):
					var d := str(d_val).strip_edges()
					if d.is_empty() or not MapUtils.DIR_OFFSETS.has(d):
						continue
					var npos = world_pos + MapUtils.DIR_OFFSETS[d]
					var opp := MapUtils.get_opposite_dir(d)
					if opp.is_empty():
						continue
					var set_val = out.get(npos, null)
					var set: Dictionary = set_val if (set_val is Dictionary) else {}
					set[opp] = true
					out[npos] = set

	return out

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

		if piece_id.begins_with("lobbyists_road_"):
			_draw_lobbyists_road_piece(canvas, cell_size, anchor, info)
			continue

		if piece_id == "park" or piece_id.begins_with("lobbyists_park_"):
			_draw_park_piece(canvas, cell_size, info)
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

	# move_restaurant：高亮当前选中的餐厅（入口 anchor 匹配）。
	var selected_anchor_val = canvas.get("_move_restaurant_selected_anchor") if canvas != null else null
	if selected_anchor_val is Vector2i and Vector2i(selected_anchor_val) == anchor:
		var outline_w := maxf(2.0, float(cell_size) * 0.08)
		outline_w = minf(outline_w, float(cell_size))
		var outline_col := Color(0.2, 0.8, 1.0, 0.9 * clampf(alpha, 0.0, 1.0))
		canvas.draw_rect(structure_rect, outline_col, false, outline_w)

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
			garden_bg.a = clampf(alpha, 0.0, 1.0)
			canvas.draw_rect(garden_rect, garden_bg, true)

	# 贴图：房屋主体
	var bottom_gap := maxf(2.0, float(cell_size) * 0.10)
	var house_tex_rect := Rect2(house_rect.position, house_rect.size)
	house_tex_rect.size.y = maxf(0.0, house_tex_rect.size.y - bottom_gap)
	_draw_texture_aspect_fit(canvas, house_tex, house_tex_rect, Color(1, 1, 1, 0.9 * alpha), "bottom")

	# 贴图：花园围栏
	if has_garden and garden_rect.size != Vector2.ZERO:
		var mod := Color(1, 1, 1, 0.9 * alpha)
		# garden_large.png is authored as a horizontal strip; rotate for vertical gardens (E/W).
		if garden_rect.size.y > garden_rect.size.x:
			var center := garden_rect.position + garden_rect.size * 0.5
			var draw_size := Vector2(garden_rect.size.y, garden_rect.size.x)
			canvas.draw_set_transform(center, deg_to_rad(90.0), Vector2.ONE)
			_draw_texture_aspect_fit(canvas, garden_tex, Rect2(-draw_size * 0.5, draw_size), mod)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_draw_texture_aspect_fit(canvas, garden_tex, garden_rect, mod)

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

	# Demand tokens: fixed size (no per-house shrinking); when demands change, we re-layout all tokens.
	var icon_size := float(cell_size) * 0.90
	var min_spacing := maxf(1.0, float(cell_size) * 0.04)

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
		var draw_count: int = min(product_ids.size(), 6)
		var draw_product_ids: Array[String] = product_ids.slice(0, draw_count)

		# Seed depends on demand content so adding/removing demands repositions all tokens.
		var demand_key := ",".join(product_ids)
		var seed := _compute_demand_scatter_seed(canvas, house_id)
		seed = int((seed ^ _hash_string_32(demand_key)) & 0x7FFFFFFF)

		var reserved: Array[Rect2] = []
		reserved.append(_compute_house_id_rect(cell_size, demand_area_rect))

		var scatter_area_rect := demand_area_rect.grow(-float(cell_size) * 0.05)
		var slots := _build_demand_token_slots(scatter_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			slots = _build_demand_token_slots(demand_area_rect, icon_size, min_spacing, reserved)
		if slots.size() < draw_count:
			continue

		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		rng.state = int(seed)
		_shuffle_rect2_array(rng, slots)

		for i in range(draw_count):
			var product_id: String = draw_product_ids[i]
			if product_id.is_empty():
				continue
			var tex: Texture2D = canvas._skin.get_product_icon_texture(product_id)
			_draw_texture_aspect_fit(canvas, tex, slots[i], Color(1, 1, 1, 0.95))

static func _draw_selection(canvas, cell_size: int) -> void:
	# 关闭“点击格子选中框”视觉（issue_tracker #31）：保留 cell_selected 信号用于交互逻辑。
	if canvas._is_valid_world_pos(canvas._hover_pos):
		var show_hover := false
		if Globals != null:
			show_hover = bool(Globals.show_cell_hover_tooltip)
		if not show_hover:
			return
		var v2 = canvas._world_to_view(canvas._hover_pos)
		var rect2 := Rect2(Vector2(v2.x * cell_size, v2.y * cell_size), Vector2(cell_size, cell_size))
		canvas.draw_rect(rect2, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

static func _draw_tile_borders(canvas, cell_size: int) -> void:
	TilesPassClass.draw_tile_borders(canvas, cell_size)

static func _draw_tile_id_labels(canvas, cell_size: int) -> void:
	TilesPassClass.draw_tile_id_labels(canvas, cell_size)
