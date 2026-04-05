# MarketingPanel：板件选择按钮（带占地预览）
extends Button

const PREVIEW_AREA_FILL_MIN := 0.42
const PREVIEW_AREA_FILL_MAX := 0.88

var board_number: int = 0
var base_size: Vector2i = Vector2i.ONE # unrotated footprint (w,h)
var board_rotation: int = 0 # 0/90/180/270

var marketing_texture: Texture2D = null
var product_texture: Texture2D = null
var show_product: bool = false

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true

	# Keep redraw in sync with UI state changes.
	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(queue_redraw):
		mouse_entered.connect(queue_redraw)
	if not mouse_exited.is_connected(queue_redraw):
		mouse_exited.connect(queue_redraw)

func _on_toggled(_pressed: bool) -> void:
	queue_redraw()

func set_board_rotation(rot: int) -> void:
	board_rotation = rot
	_update_tooltip()
	queue_redraw()

func get_rotated_size() -> Vector2i:
	var s := base_size
	if s.x <= 0 or s.y <= 0:
		s = Vector2i.ONE
	var rot := board_rotation
	if not rot in [0, 90, 180, 270]:
		rot = 0
	if rot == 90 or rot == 270:
		return Vector2i(s.y, s.x)
	return s

func set_preview(rot: int, product_tex: Texture2D, is_selected: bool) -> void:
	board_rotation = rot
	product_texture = product_tex
	show_product = is_selected
	_update_tooltip()
	queue_redraw()

func get_preview_layout(draw_size: Vector2 = size) -> Dictionary:
	var r := Rect2(Vector2.ZERO, draw_size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return {}

	var pad := maxf(6.0, minf(r.size.x, r.size.y) * 0.08)
	var label_h := maxf(18.0, minf(r.size.x, r.size.y) * 0.26)
	var preview_rect := Rect2(Vector2(pad, pad), Vector2(r.size.x - pad * 2.0, r.size.y - pad * 2.0 - label_h))
	if preview_rect.size.x <= 1.0 or preview_rect.size.y <= 1.0:
		return {}

	var s := get_rotated_size()
	var w := maxi(1, int(s.x))
	var h := maxi(1, int(s.y))
	var cell_count := maxi(1, w * h)

	var fit_cell_px := minf(preview_rect.size.x / float(w), preview_rect.size.y / float(h))
	var preview_area := preview_rect.size.x * preview_rect.size.y
	var target_area := preview_area * _get_preview_area_fill(cell_count)
	var target_cell_px := sqrt(maxf(0.0, target_area / float(cell_count)))
	var cell_px := maxf(2.0, floor(minf(fit_cell_px, target_cell_px)))

	var board_px := Vector2(float(w) * cell_px, float(h) * cell_px)
	var board_pos := preview_rect.position + (preview_rect.size - board_px) * 0.5
	var board_rect := Rect2(board_pos, board_px)
	var badge_layout := _compute_badge_layout(board_rect, cell_px, str(board_number))

	return {
		"outer_rect": r,
		"preview_rect": preview_rect,
		"board_rect": board_rect,
		"label_height": label_h,
		"padding": pad,
		"cell_px": cell_px,
		"width_cells": w,
		"height_cells": h,
		"badge_layout": badge_layout,
	}

func _draw() -> void:
	var layout := get_preview_layout(size)
	if layout.is_empty():
		return

	var r: Rect2 = layout.get("outer_rect", Rect2())
	var preview_rect: Rect2 = layout.get("preview_rect", Rect2())
	var board_rect: Rect2 = layout.get("board_rect", Rect2())
	var label_h := float(layout.get("label_height", 0.0))
	var pad := float(layout.get("padding", 0.0))
	var cell_px := float(layout.get("cell_px", 0.0))
	var w := int(layout.get("width_cells", 1))
	var h := int(layout.get("height_cells", 1))
	var board_pos := board_rect.position
	var board_px := board_rect.size

	var base := Color("#98a295")
	var fill := base
	fill.a = 0.55
	var border := base.darkened(0.25)
	border.a = 0.70
	if button_pressed:
		fill = base.darkened(0.15)
		fill.a = 0.75
		border = base.darkened(0.45)
		border.a = 0.95
	elif is_hovered():
		fill = base
		fill.a = 0.62

	draw_rect(board_rect, fill, true)
	draw_rect(board_rect, border, false, 1.0)

	# Grid lines (visualize footprint cells).
	for ix in range(w + 1):
		var x := board_pos.x + float(ix) * cell_px
		draw_line(Vector2(x, board_pos.y), Vector2(x, board_pos.y + board_px.y), border, 1.0)
	for iy in range(h + 1):
		var y := board_pos.y + float(iy) * cell_px
		draw_line(Vector2(board_pos.x, y), Vector2(board_pos.x + board_px.x, y), border, 1.0)

	# Marketing type texture as faint background.
	_draw_texture_aspect_fit(marketing_texture, board_rect.grow(-cell_px * 0.15), Color(1, 1, 1, 0.30))

	# Product icon centered (only for selected board) to show the “product slot”.
	if show_product:
		var icon_s := minf(board_rect.size.x, board_rect.size.y) * 0.55
		var icon_rect := Rect2(board_rect.position + (board_rect.size - Vector2(icon_s, icon_s)) * 0.5, Vector2(icon_s, icon_s))
		_draw_texture_aspect_fit(product_texture, icon_rect, Color(1, 1, 1, 0.95))

	# Board number badge (top-right): white circle + black number (issue_tracker #37).
	if board_number > 0:
		_draw_board_number_badge(layout.get("badge_layout", {}), board_number)

	# Label line: "#11  3x2"
	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(11, int(round(minf(r.size.x, r.size.y) * 0.17)))
	var label_rect := Rect2(Vector2(0, r.size.y - label_h), Vector2(r.size.x, label_h))
	var text_y := label_rect.position.y + label_rect.size.y - pad * 0.6
	var text_line := "#%d  %dx%d" % [board_number, w, h]
	draw_string(font, Vector2(label_rect.position.x + 1.0, text_y + 1.0), text_line, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(label_rect.position.x, text_y), text_line, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(0.85, 0.85, 0.85, 1))

func _get_preview_area_fill(cell_count: int) -> float:
	var t := clampf(float(maxi(1, cell_count) - 1) / 5.0, 0.0, 1.0)
	return lerpf(PREVIEW_AREA_FILL_MIN, PREVIEW_AREA_FILL_MAX, t)

func _draw_texture_aspect_fit(tex: Texture2D, rect: Rect2, color: Color) -> void:
	if tex == null:
		return
	var ts: Vector2i = tex.get_size()
	if ts.x <= 0 or ts.y <= 0:
		return
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return

	var scale := minf(rect.size.x / float(ts.x), rect.size.y / float(ts.y))
	if scale <= 0.0:
		return
	var dst_size := Vector2(float(ts.x) * scale, float(ts.y) * scale)
	var dst_pos := rect.position + (rect.size - dst_size) * 0.5
	draw_texture_rect(tex, Rect2(dst_pos, dst_size), false, color)

func _compute_badge_layout(board_rect: Rect2, cell_px: float, text: String) -> Dictionary:
	if text.is_empty():
		return {}

	var board_min := minf(board_rect.size.x, board_rect.size.y)
	var max_diameter := maxf(14.0, board_min * 0.42)
	var diameter := minf(maxf(14.0, cell_px * 0.84), max_diameter)
	var radius := diameter * 0.5
	var pad := clampf(cell_px * 0.18, 2.0, maxf(2.0, board_min * 0.12))
	var center := board_rect.position + Vector2(board_rect.size.x - pad - radius, pad + radius)
	var box := Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
	var font_scale := 0.44 if text.length() >= 2 else 0.56
	var font_size := maxi(8, int(round(diameter * font_scale)))

	return {
		"text": text,
		"center": center,
		"radius": radius,
		"box": box,
		"font_size": font_size,
	}

func _draw_board_number_badge(layout: Dictionary, number: int) -> void:
	if layout.is_empty():
		return
	var text := str(number).strip_edges()
	if text.is_empty():
		return
	var center: Vector2 = layout.get("center", Vector2.ZERO)
	var radius := float(layout.get("radius", 0.0))
	var box: Rect2 = layout.get("box", Rect2())
	var font_size := int(layout.get("font_size", 10))
	if radius <= 0.0:
		return

	draw_circle(center, radius, Color(1, 1, 1, 1))

	var font: Font = ThemeDB.fallback_font
	var baseline := Vector2(box.position.x, box.position.y + box.size.y * 0.5 + float(font_size) * 0.32)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, Color(0, 0, 0, 1))

func _update_tooltip() -> void:
	if board_number <= 0:
		tooltip_text = ""
		return
	var s := get_rotated_size()
	tooltip_text = "#%d  %dx%d" % [board_number, s.x, s.y]
