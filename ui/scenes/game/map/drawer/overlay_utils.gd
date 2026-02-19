# MapCanvasDrawer：覆盖层绘制工具下沉
extends RefCounted

static func draw_cells_overlay(canvas, cell_size: int, world_cells: Array, fill: Color, border: Color, border_width: float) -> void:
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

static func draw_view_cells_overlay(canvas, cell_size: int, view_cells_any: Array, fill: Color, border: Color, border_width: float) -> void:
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
