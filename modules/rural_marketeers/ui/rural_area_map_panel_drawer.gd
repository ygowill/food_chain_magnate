extends RefCounted

const TextureUtilsClass = preload("res://ui/scenes/game/map_canvas_drawer_texture_utils.gd")

const PANEL_ID := "rural_marketeers:rural_area_panel"
const RURAL_HOUSE_ID := "rural_area"

const PANEL_PADDING_CELLS := 1
const TILE_SIZE_CELLS := 4
const BILLBOARD_THICKNESS_CELLS := 1

const PANEL_WIDTH_CELLS := TILE_SIZE_CELLS + BILLBOARD_THICKNESS_CELLS * 2 + PANEL_PADDING_CELLS * 2
const PANEL_HEIGHT_CELLS := PANEL_WIDTH_CELLS

func draw(canvas, cell_size: int, panel: Dictionary) -> void:
	if canvas == null:
		return
	if canvas._skin == null:
		return
	if not (canvas._map_data is Dictionary):
		return

	var world_min_val = panel.get("world_min", null)
	if not (world_min_val is Vector2i):
		return
	var world_min: Vector2i = world_min_val

	var w_cells := int(panel.get("width_cells", 0))
	var h_cells := int(panel.get("height_cells", 0))
	if w_cells <= 0 or h_cells <= 0:
		return

	var vmin: Vector2i = canvas._world_to_view(world_min)
	var panel_rect := Rect2(
		Vector2(float(vmin.x * cell_size), float(vmin.y * cell_size)),
		Vector2(float(w_cells * cell_size), float(h_cells * cell_size))
	)

	_draw_panel_background(canvas, panel_rect, cell_size)

	var inner_pad := float(cell_size * PANEL_PADDING_CELLS)
	var inner := panel_rect.grow(-inner_pad)
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		return

	var content_side := float(cell_size * (TILE_SIZE_CELLS + BILLBOARD_THICKNESS_CELLS * 2))
	var content_rect := Rect2(inner.position + (inner.size - Vector2(content_side, content_side)) * 0.5, Vector2(content_side, content_side))
	if content_rect.size.x <= 2.0 or content_rect.size.y <= 2.0:
		return

	var b := float(cell_size * BILLBOARD_THICKNESS_CELLS)
	var tile_side := float(cell_size * TILE_SIZE_CELLS)
	var tile_rect := Rect2(content_rect.position + Vector2(b, b), Vector2(tile_side, tile_side))

	var rural := _get_rural_house(canvas._map_data)
	_draw_rural_area_tile(canvas, tile_rect, rural)
	_draw_giant_billboards(canvas, tile_rect, b, rural)
	_draw_rural_demands(canvas, tile_rect, rural)

func _draw_panel_background(canvas, rect: Rect2, cell_size: int) -> void:
	var bg := Color("#f4edd1")
	bg.a = 0.90
	canvas.draw_rect(rect, bg, true)

	var border := Color(0, 0, 0, 0.20)
	var w := maxf(1.0, float(cell_size) * 0.05)
	canvas.draw_rect(rect, border, false, w)

func _draw_rural_area_tile(canvas, tile_rect: Rect2, _rural: Dictionary) -> void:
	var tex: Texture2D = canvas._skin.get_piece_texture("rural_area")
	var pad := maxf(1.0, tile_rect.size.x * 0.02)
	var rect := tile_rect.grow(-pad)
	TextureUtilsClass.draw_texture_aspect_fill(canvas, tex, rect, Color(1, 1, 1, 0.92))

	var border := Color(0, 0, 0, 0.22)
	canvas.draw_rect(tile_rect, border, false, 1.0)

func _draw_giant_billboards(canvas, tile_rect: Rect2, thickness_px: float, rural: Dictionary) -> void:
	var boards_val = rural.get("giant_billboards", null)
	var boards: Dictionary = boards_val if boards_val is Dictionary else {}

	var side_rects := {
		"N": Rect2(tile_rect.position + Vector2(0.0, -thickness_px), Vector2(tile_rect.size.x, thickness_px)),
		"S": Rect2(tile_rect.position + Vector2(0.0, tile_rect.size.y), Vector2(tile_rect.size.x, thickness_px)),
		"W": Rect2(tile_rect.position + Vector2(-thickness_px, 0.0), Vector2(thickness_px, tile_rect.size.y)),
		"E": Rect2(tile_rect.position + Vector2(tile_rect.size.x, 0.0), Vector2(thickness_px, tile_rect.size.y)),
	}

	for side in ["N", "E", "S", "W"]:
		if not side_rects.has(side):
			continue
		var r: Rect2 = side_rects[side]
		var placed := boards.has(side)
		if not placed:
			continue

		var fill := Color(0, 0, 0, 0.06)
		var border := Color(0, 0, 0, 0.18)
		if placed:
			fill = Color(0.1, 0.1, 0.1, 0.10)
			border = Color(0, 0, 0, 0.28)
		canvas.draw_rect(r, fill, true)
		canvas.draw_rect(r, border, false, 1.0)

		var bb_tex: Texture2D = canvas._skin.get_piece_texture("rural_billboard")
		var pad := maxf(1.0, minf(r.size.x, r.size.y) * 0.08)
		var dst := r.grow(-pad)
		var mod := Color(1, 1, 1, 0.55)
		if side == "E" or side == "W":
			# East/West billboard is vertical; rotate placeholder so the texture is not squashed.
			var center := dst.position + dst.size * 0.5
			var swapped := Vector2(dst.size.y, dst.size.x)
			canvas.draw_set_transform(center, deg_to_rad(90.0), Vector2.ONE)
			TextureUtilsClass.draw_texture_aspect_fit(canvas, bb_tex, Rect2(-swapped * 0.5, swapped), mod)
			canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			TextureUtilsClass.draw_texture_aspect_fit(canvas, bb_tex, dst, mod)
		var entry_val = boards.get(side, null)
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var product_id := str(entry.get("product", "")).strip_edges()
		if product_id.is_empty():
			continue
		_draw_product_token(canvas, r, product_id, "")

func _draw_rural_demands(canvas, tile_rect: Rect2, rural: Dictionary) -> void:
	var counts := _count_demands_by_product(rural)
	if counts.is_empty():
		return

	var products: Array[String] = []
	for k in counts.keys():
		products.append(str(k))
	products.sort()

	var pad := maxf(2.0, minf(tile_rect.size.x, tile_rect.size.y) * 0.06)
	var area := tile_rect.grow(-pad)
	if area.size.x <= 2.0 or area.size.y <= 2.0:
		return

	var n := products.size()
	var cols := maxi(1, int(ceil(sqrt(float(n)))))
	var rows := maxi(1, int(ceil(float(n) / float(cols))))

	var cell_w := area.size.x / float(cols)
	var cell_h := area.size.y / float(rows)
	var icon_side := minf(cell_w, cell_h) * 0.92
	if icon_side < 6.0:
		return

	for i in range(n):
		var pid: String = products[i]
		var count_val = counts.get(pid, 0)
		var count := int(count_val) if (count_val is int) else int(float(count_val))
		if count <= 0:
			continue

		var row := int(floor(float(i) / float(cols)))
		var col := int(i % cols)
		var cell_pos := area.position + Vector2(float(col) * cell_w, float(row) * cell_h)
		var center := cell_pos + Vector2(cell_w, cell_h) * 0.5
		var rect := Rect2(center - Vector2(icon_side, icon_side) * 0.5, Vector2(icon_side, icon_side))
		_draw_product_token(canvas, rect, pid, str(count))

func _draw_product_token(canvas, rect: Rect2, product_id: String, count_text: String) -> void:
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"

	var tex: Texture2D = canvas._skin.get_product_icon_texture(pid)
	TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, rect, Color(1, 1, 1, 0.95))

	var text := str(count_text).strip_edges()
	if text.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	var base := minf(rect.size.x, rect.size.y)
	var font_size := maxi(10, int(round(base * 0.52)))
	if text.length() >= 2:
		font_size = int(round(float(font_size) * 0.86))
	if text.length() >= 3:
		font_size = int(round(float(font_size) * 0.78))
	if text.length() >= 4:
		font_size = int(round(float(font_size) * 0.70))
	font_size = maxi(10, font_size)

	var baseline := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + float(font_size) * 0.35)
	canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color(0, 0, 0, 0.85))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color(1, 1, 1, 0.98))

func _get_rural_house(map_data: Dictionary) -> Dictionary:
	if not (map_data is Dictionary):
		return {}
	var houses_val = map_data.get("houses", null)
	if not (houses_val is Dictionary):
		return {}
	var houses: Dictionary = houses_val
	var rural_val = houses.get(RURAL_HOUSE_ID, null)
	if not (rural_val is Dictionary):
		return {}
	return rural_val

func _count_demands_by_product(rural: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var demands_val = rural.get("demands", null)
	if not (demands_val is Array):
		return out
	var demands: Array = demands_val
	for d_val in demands:
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		var pid := str(d.get("product", "")).strip_edges()
		if pid.is_empty():
			continue
		out[pid] = int(out.get(pid, 0)) + 1
	return out
