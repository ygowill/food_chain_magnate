# ProductionPanel：食物/饮料类型选择 token（拆分自 production_panel.gd）
extends PanelContainer

signal pressed(product_id: String)

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiPointerInputClass = preload("res://ui/utils/pointer_input.gd")

var product_id: String = ""
var display_name: String = ""
var icon_texture: Texture2D = null

var _icon: TextureRect = null
var _label: Label = null
var _selected: bool = false
var _style: StyleBoxFlat = null

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _build_ui() -> void:
	# 与其它面板的产品 token 保持一致，避免图标纹理尺寸变化导致 token 被撑大。
	custom_minimum_size = Vector2(60, 60)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(32, 32)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_icon)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var fs := 12
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(12))
	_label.add_theme_font_size_override("font_size", fs)
	UiStylesClass.apply_label_dark(_label)
	vbox.add_child(_label)

	_update_display()
	_update_style()

func _update_display() -> void:
	if _icon != null:
		_icon.texture = icon_texture
	if _label != null:
		var name := display_name if not display_name.is_empty() else product_id
		_label.text = name
		tooltip_text = name

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func _update_style() -> void:
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0, 0, 0, 0.22)
		_style.set_corner_radius_all(8)
		_style.set_border_width_all(2)
		add_theme_stylebox_override("panel", _style)
	_style.border_color = Color(0.35, 0.55, 0.95, 0.95) if _selected else Color(1, 1, 1, 0.15)

func _on_gui_input(event: InputEvent) -> void:
	if UiPointerInputClass.is_primary_press(event):
		pressed.emit(product_id)
