# Lobbyists extra tile：板块选择按钮（渲染真实 tile 贴图，非缩略图）
extends Button

const TilePreviewClass = preload("res://ui/components/lobbyists_extra_tile/tile_preview.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270

var _preview: Control = null

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	toggle_mode = true

	custom_minimum_size = Vector2(110, 110)

	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(queue_redraw):
		mouse_entered.connect(queue_redraw)
	if not mouse_exited.is_connected(queue_redraw):
		mouse_exited.connect(queue_redraw)

	_ensure_preview()
	_sync_preview()
	queue_redraw()

func _on_toggled(_pressed: bool) -> void:
	queue_redraw()

func set_tile_rotation(rot: int) -> void:
	tile_rotation = _normalize_rotation(rot)
	_sync_preview()

func _normalize_rotation(rot: int) -> int:
	var r := int(rot) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _ensure_preview() -> void:
	if is_instance_valid(_preview):
		return
	var p: Control = TilePreviewClass.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 4
	p.offset_top = 4
	p.offset_right = -4
	p.offset_bottom = -4
	add_child(p)
	_preview = p

func _sync_preview() -> void:
	_ensure_preview()
	if not is_instance_valid(_preview):
		return
	if _preview.has_method("set_tile"):
		_preview.call("set_tile", tile_id, tile_rotation)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return

	var border_col := Color(0, 0, 0, 0.35)
	var border_w := 2.0
	if button_pressed:
		border_col = Color(0.2, 0.65, 1.0, 0.95)
		border_w = 3.0
	elif is_hovered():
		border_col = Color(1, 1, 1, 0.35)
		border_w = 2.0

	draw_rect(r.grow(-0.5), border_col, false, border_w)
