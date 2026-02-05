# Lobbyists extra tile：板块选择按钮（渲染真实 tile 贴图，非缩略图）
extends Button

const TilePreviewClass = preload("res://modules/lobbyists/ui/components/lobbyists_extra_tile/tile_preview.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270

var _preview: Control = null
var _selected_overlay: ColorRect = null
var _badge_bg: ColorRect = null

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	clip_contents = true
	if has_method("set_clip_children_mode"):
		set_clip_children_mode(CanvasItem.CLIP_CHILDREN_AND_DRAW)
	toggle_mode = true

	custom_minimum_size = Vector2(150, 150)
	minimum_size_changed()

	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(_on_mouse_state_changed):
		mouse_entered.connect(_on_mouse_state_changed)
	if not mouse_exited.is_connected(_on_mouse_state_changed):
		mouse_exited.connect(_on_mouse_state_changed)

	_ensure_preview()
	_sync_preview()
	_update_selection_visual()
	queue_redraw()

func _on_toggled(_pressed: bool) -> void:
	_update_selection_visual()
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

	var ov := ColorRect.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.offset_left = 4
	ov.offset_top = 4
	ov.offset_right = -4
	ov.offset_bottom = -4
	ov.color = Color(0.2, 0.65, 1.0, 0.16)
	ov.visible = false
	add_child(ov)
	_selected_overlay = ov

	var badge_bg := ColorRect.new()
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge_bg.offset_left = -30
	badge_bg.offset_top = 4
	badge_bg.offset_right = -4
	badge_bg.offset_bottom = 30
	badge_bg.color = Color(0.08, 0.10, 0.14, 0.75)
	badge_bg.visible = false
	add_child(badge_bg)
	_badge_bg = badge_bg

	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.text = "✓"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	badge_bg.add_child(badge)

func _sync_preview() -> void:
	_ensure_preview()
	if not is_instance_valid(_preview):
		return
	if _preview.has_method("set_tile"):
		_preview.call("set_tile", tile_id, tile_rotation)

func _on_mouse_state_changed() -> void:
	_update_selection_visual()
	queue_redraw()

func _update_selection_visual() -> void:
	var pressed := bool(button_pressed)
	var hovered := is_hovered()

	if is_instance_valid(_selected_overlay):
		if pressed:
			_selected_overlay.visible = true
			_selected_overlay.color = Color(0.2, 0.65, 1.0, 0.16)
		elif hovered:
			_selected_overlay.visible = true
			_selected_overlay.color = Color(1, 1, 1, 0.06)
		else:
			_selected_overlay.visible = false

	if is_instance_valid(_badge_bg):
		_badge_bg.visible = pressed

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return

	var border_col := Color(0, 0, 0, 0.35)
	var border_w := 2.0
	if button_pressed:
		border_col = Color(0.2, 0.65, 1.0, 0.95)
		border_w = 4.0
	elif is_hovered():
		border_col = Color(1, 1, 1, 0.35)
		border_w = 2.0

	draw_rect(r.grow(-0.5), border_col, false, border_w)
