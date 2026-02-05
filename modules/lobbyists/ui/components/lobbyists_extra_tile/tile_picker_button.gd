# Lobbyists extra tile：板块选择按钮（文本型，避免大图占位/遮挡）
extends Button

const TileRegistryClass = preload("res://core/map/tile_registry.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270（保留：兼容 set_tile_rotation）

var _display_name: String = ""

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	toggle_mode = true
	flat = true

	custom_minimum_size = Vector2(180, 44)
	minimum_size_changed.emit()

	_refresh_display_name()
	text = _display_name
	tooltip_text = tile_id

	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(queue_redraw):
		mouse_entered.connect(queue_redraw)
	if not mouse_exited.is_connected(queue_redraw):
		mouse_exited.connect(queue_redraw)

	queue_redraw()

func set_tile_rotation(rot: int) -> void:
	tile_rotation = _normalize_rotation(rot)

func _refresh_display_name() -> void:
	_display_name = tile_id
	if _display_name.is_empty():
		_display_name = "（未知板块）"
		return
	if not TileRegistryClass.is_loaded():
		return
	var def_val = TileRegistryClass.get_def(tile_id)
	if def_val != null and (def_val is TileDef):
		var def: TileDef = def_val
		var dn := str(def.display_name).strip_edges()
		if not dn.is_empty():
			_display_name = dn

func _normalize_rotation(rot: int) -> int:
	var r := int(rot) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _on_toggled(_pressed: bool) -> void:
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return

	var bg := Color(0.10, 0.11, 0.14, 0.55)
	var border_col := Color(1, 1, 1, 0.14)
	var border_w := 2.0
	var text_col := Color(0.92, 0.92, 0.95, 0.95)

	if button_pressed:
		bg = Color(0.12, 0.20, 0.28, 0.75)
		border_col = Color(0.2, 0.65, 1.0, 0.95)
		border_w = 3.0
		text_col = Color(1, 1, 1, 1)
	elif is_hovered():
		bg = Color(0.13, 0.14, 0.18, 0.70)
		border_col = Color(1, 1, 1, 0.24)
		text_col = Color(0.98, 0.98, 1, 1)

	draw_rect(r, bg, true)
	draw_rect(r.grow(-0.5), border_col, false, border_w)

	var font: Font = ThemeDB.fallback_font
	var font_size := 14
	if Globals != null and Globals.has_method("get_scaled_font_size"):
		font_size = int(Globals.get_scaled_font_size(14))

	var pad_x := 12.0
	var right_pad := 30.0
	var max_w := maxf(0.0, r.size.x - pad_x - right_pad)
	var baseline_y := r.size.y * 0.5 + float(font_size) * 0.35
	draw_string(font, Vector2(pad_x, baseline_y), _display_name, HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, text_col)

	if button_pressed:
		var check_x := r.size.x - right_pad + 6.0
		draw_string(font, Vector2(check_x, baseline_y), "✓", HORIZONTAL_ALIGNMENT_LEFT, right_pad - 6.0, font_size, Color(0.2, 0.65, 1.0, 1))
