# MapCanvasDrawer：tile 边框与 tile_id 绘制下沉
extends RefCounted

static func draw_tile_borders(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	var tps: Array = []
	var base_val = canvas._map_data.get("tile_placements", null)
	if base_val is Array:
		tps.append_array(base_val)
	var ext_val = canvas._map_data.get("external_tile_placements", null)
	if ext_val is Array:
		tps.append_array(ext_val)
	if tps.is_empty():
		return

	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return

	# 外边缘：使用整数屏幕像素，避免缩放后半像素采样导致忽粗忽细。
	var thickness := _tile_border_thickness(cell_size)
	var col := Color(0, 0, 0, 0.9)

	# tile 内部细分网格线（细线）：黑色 alpha≈0.25，整数屏幕像素宽度。
	var inner_thickness := _tile_inner_grid_thickness(cell_size)
	var inner_col := Color(0, 0, 0, 0.25)

	for tp_val in tps:
		if not (tp_val is Dictionary):
			continue
		var tp: Dictionary = tp_val
		var board_pos_val = tp.get("board_pos", null)
		if not (board_pos_val is Vector2i):
			continue
		var board_pos: Vector2i = board_pos_val
		if canvas != null and canvas.has_method("is_intro_tile_revealed"):
			if not bool(canvas.call("is_intro_tile_revealed", board_pos)):
				continue
		var world_min := board_pos * tile_size
		var vmin = canvas._world_to_view(world_min)
		var rect := Rect2(
			Vector2(vmin.x * cell_size, vmin.y * cell_size),
			Vector2(tile_size * cell_size, tile_size * cell_size)
		)

		# 内部细线先画，外边缘粗线后画（避免细线盖住外边缘）
		for i in range(1, tile_size):
			var x := _snap_centered_line_start(rect.position.x + float(i * cell_size), inner_thickness)
			canvas.draw_rect(Rect2(Vector2(x, _snap_px(rect.position.y)), Vector2(inner_thickness, _snap_px(rect.size.y))), inner_col, true)
			var y := _snap_centered_line_start(rect.position.y + float(i * cell_size), inner_thickness)
			canvas.draw_rect(Rect2(Vector2(_snap_px(rect.position.x), y), Vector2(_snap_px(rect.size.x), inner_thickness)), inner_col, true)

		# 向内黑边框（不应盖住上层 piece）
		var left := _snap_px(rect.position.x)
		var top := _snap_px(rect.position.y)
		var right := _snap_px(rect.position.x + rect.size.x)
		var bottom := _snap_px(rect.position.y + rect.size.y)
		var w := maxf(0.0, right - left)
		var h := maxf(0.0, bottom - top)
		canvas.draw_rect(Rect2(Vector2(left, top), Vector2(w, thickness)), col, true)
		canvas.draw_rect(Rect2(Vector2(left, bottom - thickness), Vector2(w, thickness)), col, true)
		canvas.draw_rect(Rect2(Vector2(left, top), Vector2(thickness, h)), col, true)
		canvas.draw_rect(Rect2(Vector2(right - thickness, top), Vector2(thickness, h)), col, true)

static func _tile_inner_grid_thickness(cell_size: int) -> float:
	return float(clampi(int(round(float(cell_size) * 0.02)), 1, 2))

static func _tile_border_thickness(cell_size: int) -> float:
	return float(clampi(int(round(float(cell_size) * 0.05)), 1, 3))

static func _snap_px(value: float) -> float:
	return float(round(value))

static func _snap_centered_line_start(center: float, thickness: float) -> float:
	return float(round(center) - floor(thickness * 0.5))

static func draw_tile_id_labels(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	var tps: Array = []
	var base_val = canvas._map_data.get("tile_placements", null)
	if base_val is Array:
		tps.append_array(base_val)
	var ext_val = canvas._map_data.get("external_tile_placements", null)
	if ext_val is Array:
		tps.append_array(ext_val)
	if tps.is_empty():
		return

	var show_tile_ids := _read_globals_bool("show_tile_ids", false)
	if not show_tile_ids:
		return

	var tile_size := int(MapUtils.TILE_SIZE)
	if tile_size <= 0:
		return

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
		if canvas != null and canvas.has_method("is_intro_tile_revealed"):
			if not bool(canvas.call("is_intro_tile_revealed", board_pos)):
				continue
		var world_min := board_pos * tile_size
		var vmin = canvas._world_to_view(world_min)
		var rect := Rect2(
			Vector2(vmin.x * cell_size, vmin.y * cell_size),
			Vector2(tile_size * cell_size, tile_size * cell_size)
		)

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

static func _read_globals_bool(key: String, fallback: bool) -> bool:
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		var globals = (tree as SceneTree).root.get_node_or_null("Globals")
		if globals != null:
			var val = globals.get(key)
			if val is bool:
				return bool(val)
	return fallback
