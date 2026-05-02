# MapCanvasDrawer：可放置板件通用底座绘制
extends RefCounted

const EDGE_COLOR := Color("#2f261f")
const SHADOW_COLOR := Color(0, 0, 0, 0.22)

static func edge_px(cell_size: int) -> float:
	return maxf(1.0, minf(5.0, float(cell_size) * 0.07))

static func draw_shadow(canvas, rect: Rect2, cell_size: int, alpha: float) -> void:
	if canvas == null:
		return
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var a := clampf(alpha, 0.0, 1.0)
	if a <= 0.001:
		return
	var offset := maxf(1.0, minf(6.0, float(cell_size) * 0.08))
	var shadow := SHADOW_COLOR
	shadow.a *= a
	canvas.draw_rect(Rect2(rect.position + Vector2(offset, offset), rect.size), shadow, true)

static func draw_fill(canvas, rect: Rect2, fill_color: Color, alpha: float) -> void:
	if canvas == null:
		return
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var face := fill_color
	face.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_rect(rect, face, true)

static func draw_bevel(canvas, rect: Rect2, cell_size: int, fill_color: Color, alpha: float) -> void:
	if canvas == null:
		return
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var a := clampf(alpha, 0.0, 1.0)
	if a <= 0.001:
		return
	var edge := edge_px(cell_size)
	if rect.size.x <= edge * 2.0 or rect.size.y <= edge * 2.0:
		return

	var highlight := fill_color.lightened(0.26)
	highlight.a = 0.48 * a
	var shade := Color("#4b3828")
	shade.a = 0.50 * a

	canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, edge)), highlight, true)
	canvas.draw_rect(Rect2(rect.position, Vector2(edge, rect.size.y)), highlight, true)
	canvas.draw_rect(Rect2(rect.position + Vector2(rect.size.x - edge, 0.0), Vector2(edge, rect.size.y)), shade, true)
	canvas.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - edge), Vector2(rect.size.x, edge)), shade, true)

static func draw_outline(canvas, rect: Rect2, cell_size: int, alpha: float) -> void:
	if canvas == null:
		return
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var a := clampf(alpha, 0.0, 1.0)
	if a <= 0.001:
		return

	var border := EDGE_COLOR
	border.a = 0.82 * a
	canvas.draw_rect(rect, border, false, maxf(1.0, minf(3.0, float(cell_size) * 0.045)))

static func draw_background(canvas, rect: Rect2, cell_size: int, fill_color: Color, alpha: float = 1.0, with_shadow: bool = true) -> void:
	if with_shadow:
		draw_shadow(canvas, rect, cell_size, alpha)
	draw_fill(canvas, rect, fill_color, alpha)
	draw_bevel(canvas, rect, cell_size, fill_color, alpha)
