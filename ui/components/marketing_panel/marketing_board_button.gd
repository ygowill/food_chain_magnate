# MarketingPanel：板件选择按钮（带占地预览）
extends Button

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
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return

	var pad := maxf(6.0, minf(r.size.x, r.size.y) * 0.08)
	var label_h := maxf(18.0, minf(r.size.x, r.size.y) * 0.26)
	var preview_rect := Rect2(Vector2(pad, pad), Vector2(r.size.x - pad * 2.0, r.size.y - pad * 2.0 - label_h))
	if preview_rect.size.x <= 1.0 or preview_rect.size.y <= 1.0:
		return

	var s := get_rotated_size()
	var w := maxi(1, int(s.x))
	var h := maxi(1, int(s.y))

	var cell_px := minf(preview_rect.size.x / float(w), preview_rect.size.y / float(h))
	# Prefer whole pixels so grid lines stay crisp.
	cell_px = maxf(2.0, floor(cell_px))

	var board_px := Vector2(float(w) * cell_px, float(h) * cell_px)
	var board_pos := preview_rect.position + (preview_rect.size - board_px) * 0.5
	var board_rect := Rect2(board_pos, board_px)

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
		_draw_board_number_badge(board_rect, board_number, cell_px)

	# Label line: "#11  3x2"
	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(11, int(round(minf(r.size.x, r.size.y) * 0.17)))
	var label_rect := Rect2(Vector2(0, r.size.y - label_h), Vector2(r.size.x, label_h))
	var text_y := label_rect.position.y + label_rect.size.y - pad * 0.6
	var text_line := "#%d  %dx%d" % [board_number, w, h]
	draw_string(font, Vector2(label_rect.position.x + 1.0, text_y + 1.0), text_line, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(label_rect.position.x, text_y), text_line, HORIZONTAL_ALIGNMENT_CENTER, label_rect.size.x, font_size, Color(0.85, 0.85, 0.85, 1))

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

func _draw_board_number_badge(board_rect: Rect2, number: int, cell_px: float) -> void:
	var text := str(number).strip_edges()
	if text.is_empty():
		return

	var r := maxf(8.0, float(cell_px) * 0.55)
	var pad := maxf(2.0, float(cell_px) * 0.20)
	var center := board_rect.position + Vector2(board_rect.size.x - pad - r, pad + r)

	draw_circle(center, r, Color(1, 1, 1, 1))

	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(10, int(round(r * 0.95)))
	var box := Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var baseline := Vector2(box.position.x, box.position.y + box.size.y * 0.5 + float(font_size) * 0.35)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, Color(0, 0, 0, 1))
