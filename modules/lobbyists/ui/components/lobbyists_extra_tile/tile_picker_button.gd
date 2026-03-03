# Lobbyists extra tile：板块选择按钮（显示完整 tile 预览缩略图）
extends Button

const TilePreviewClass = preload("res://modules/lobbyists/ui/components/lobbyists_extra_tile/tile_preview.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270

var _display_name: String = ""
var _preview: Control = null
var _name_label: Label = null
var _selected_overlay: ColorRect = null
var _badge_bg: ColorRect = null
var _is_ready: bool = false

func _ready() -> void:
	text = ""
	icon = null
	expand_icon = true
	clip_text = true
	toggle_mode = true
	flat = true
	clip_contents = true
	if has_method("set_clip_children_mode"):
		set_clip_children_mode(CanvasItem.CLIP_CHILDREN_AND_DRAW)

	custom_minimum_size = Vector2(160, 190)
	minimum_size_changed.emit()

	_refresh_display_name()
	tooltip_text = tile_id

	if not resized.is_connected(queue_redraw):
		resized.connect(queue_redraw)
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	if not mouse_entered.is_connected(_on_mouse_state_changed):
		mouse_entered.connect(_on_mouse_state_changed)
	if not mouse_exited.is_connected(_on_mouse_state_changed):
		mouse_exited.connect(_on_mouse_state_changed)

	_ensure_children()
	_is_ready = true
	_sync_preview()
	# Some registries/skins may finalize after UI enters the tree; refresh once more next frame.
	call_deferred("_sync_preview")
	_update_selection_visual()

	queue_redraw()

func set_tile_rotation(rot: int) -> void:
	tile_rotation = _normalize_rotation(rot)
	if _is_ready:
		_sync_preview()

func _ensure_children() -> void:
	if is_instance_valid(_preview):
		return

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_top = 6
	content.offset_right = -6
	content.offset_bottom = -6
	content.add_theme_constant_override("separation", 4)
	add_child(content)

	var p: Control = TilePreviewClass.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 128)
	content.add_child(p)
	_preview = p

	var name_bg := ColorRect.new()
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.custom_minimum_size = Vector2(0, 26)
	name_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_bg.color = Color(0.92, 0.88, 0.78, 0.92)
	content.add_child(name_bg)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	name_bg.add_child(label)
	_name_label = label

	var ov := ColorRect.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.offset_left = 4
	ov.offset_top = 4
	ov.offset_right = -4
	ov.offset_bottom = -4
	ov.color = Color(0.73, 0.23, 0.18, 0.16)
	ov.visible = false
	add_child(ov)
	_selected_overlay = ov

	var badge_bg := ColorRect.new()
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge_bg.offset_left = -30
	badge_bg.offset_top = 6
	badge_bg.offset_right = -6
	badge_bg.offset_bottom = 30
	badge_bg.color = Color(0.73, 0.23, 0.18, 0.22)
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
	badge.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	badge_bg.add_child(badge)

func _sync_preview() -> void:
	if not _is_ready:
		return
	_refresh_display_name()
	if is_instance_valid(_name_label):
		_name_label.text = _display_name
	if is_instance_valid(_preview) and _preview.has_method("set_tile"):
		_preview.call("set_tile", tile_id, tile_rotation)

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
	_update_selection_visual()
	queue_redraw()

func _on_mouse_state_changed() -> void:
	_update_selection_visual()
	queue_redraw()

func _update_selection_visual() -> void:
	var pressed := bool(button_pressed)
	var hovered := is_hovered()

	if is_instance_valid(_selected_overlay):
		if pressed:
			_selected_overlay.visible = true
			_selected_overlay.color = Color(0.73, 0.23, 0.18, 0.16)
		elif hovered:
			_selected_overlay.visible = true
			_selected_overlay.color = Color(0.17, 0.13, 0.09, 0.06)
		else:
			_selected_overlay.visible = false

	if is_instance_valid(_badge_bg):
		_badge_bg.visible = pressed

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 2.0 or r.size.y <= 2.0:
		return

	var bg := Color(0.95, 0.91, 0.82, 0.96)
	var border_col := Color(0.17, 0.13, 0.09, 0.20)
	var border_w := 2.0
	if button_pressed:
		bg = Color(0.92, 0.88, 0.78, 0.98)
		border_col = Color(0.73, 0.23, 0.18, 0.85)
		border_w = 3.0
	elif is_hovered():
		bg = Color(0.97, 0.94, 0.86, 0.98)
		border_col = Color(0.17, 0.13, 0.09, 0.35)
	draw_rect(r, bg, true)
	draw_rect(r.grow(-0.5), border_col, false, border_w)
