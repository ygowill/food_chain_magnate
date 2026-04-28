# MarketingPanel：营销类型按钮
extends PanelContainer

const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

signal type_selected(type_id: String)

var type_id: String = ""
var type_def: Dictionary = {}
var is_available: bool = false
var marketer_count: int = 0
var board_count: int = 0
var icon_texture: Texture2D = null

var _selected: bool = false
var _icon_label: Label
var _icon_rect: TextureRect
var _name_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(118, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	# 图标（贴图优先，缺失则回退文字）
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(78, 52)
	vbox.add_child(icon_slot)

	_icon_rect = TextureRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_child(_icon_rect)

	_icon_label = Label.new()
	_icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_label.add_theme_font_size_override("font_size", 30)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_child(_icon_label)

	# 名称
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	vbox.add_child(_name_label)

	update_display()
	_update_style()

func _gui_input(event: InputEvent) -> void:
	if not UiPointerInputClass.is_primary_press(event):
		return
	if is_available:
		type_selected.emit(type_id)

func update_display() -> void:
	if _icon_rect != null:
		_icon_rect.texture = icon_texture

	if _icon_label != null:
		_icon_label.text = str(type_def.get("icon", "?"))
		var color: Color = type_def.get("color", Color.WHITE)
		_icon_label.add_theme_color_override("font_color", color)

		if icon_texture != null:
			_icon_rect.visible = true
			_icon_label.visible = false
		else:
			_icon_rect.visible = false
			_icon_label.visible = true

	if _name_label != null:
		_name_label.text = str(type_def.get("name", type_id))
		if is_available:
			_name_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
		else:
			_name_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.5, 1))

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func _update_style() -> void:
	var style := StyleBoxFlat.new()
	if _selected:
		style.bg_color = Color(0.89, 0.82, 0.66, 0.95)
		style.border_color = Color(0.73, 0.23, 0.18, 0.6)
		style.set_border_width_all(2)
	elif is_available:
		style.bg_color = Color(0.95, 0.91, 0.82, 0.9)
	else:
		style.bg_color = Color(0.92, 0.88, 0.78, 0.6)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)

	modulate = Color(1, 1, 1, 1) if is_available else Color(0.6, 0.6, 0.6, 0.8)
