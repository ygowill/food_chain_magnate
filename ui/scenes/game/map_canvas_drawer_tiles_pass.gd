# MapCanvasDrawer：tile 边框与 tile_id 绘制下沉
extends RefCounted

static func draw_tile_borders(canvas, cell_size: int) -> void:
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

	# tile 内部细分网格线（细线）：黑色 alpha≈0.25，线宽随 zoom 缩放为 max(1, cell_size*0.02)
	var inner_thickness := maxf(1.0, float(cell_size) * 0.02)
	inner_thickness = minf(inner_thickness, float(cell_size))
	var inner_col := Color(0, 0, 0, 0.25)

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

		# 内部细线先画，外边缘粗线后画（避免细线盖住外边缘）
		for i in range(1, tile_size):
			var x := rect.position.x + float(i * cell_size) - inner_thickness * 0.5
			canvas.draw_rect(Rect2(Vector2(x, rect.position.y), Vector2(inner_thickness, rect.size.y)), inner_col, true)
			var y := rect.position.y + float(i * cell_size) - inner_thickness * 0.5
			canvas.draw_rect(Rect2(Vector2(rect.position.x, y), Vector2(rect.size.x, inner_thickness)), inner_col, true)

		# 向内黑边框（不应盖住上层 piece）
		canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, thickness)), col, true)
		canvas.draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - thickness), Vector2(rect.size.x, thickness)), col, true)
		canvas.draw_rect(Rect2(rect.position, Vector2(thickness, rect.size.y)), col, true)
		canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - thickness, 0), Vector2(thickness, rect.size.y)), col, true)

static func draw_tile_id_labels(canvas, cell_size: int) -> void:
	if canvas._map_data.is_empty():
		return
	var tps_val = canvas._map_data.get("tile_placements", null)
	if not (tps_val is Array):
		return
	var tps: Array = tps_val
	if tps.is_empty():
		return

	var show_tile_ids := false
	if Globals != null:
		show_tile_ids = bool(Globals.show_tile_ids)
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
