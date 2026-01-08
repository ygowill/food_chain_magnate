# MarketingPanel：营销类型按钮
extends PanelContainer

signal type_selected(type_id: String)

var type_id: String = ""
var type_def: Dictionary = {}
var is_available: bool = false
var marketer_count: int = 0
var board_count: int = 0

var _selected: bool = false
var _icon_label: Label
var _name_label: Label
var _count_label: Label

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(110, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	# 图标
	_icon_label = Label.new()
	_icon_label.add_theme_font_size_override("font_size", 28)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_icon_label)

	# 名称
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_name_label)

	# 数量
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_count_label)

	update_display()
	_update_style()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_available:
				type_selected.emit(type_id)

func update_display() -> void:
	if _icon_label != null:
		_icon_label.text = str(type_def.get("icon", "?"))
		var color: Color = type_def.get("color", Color.WHITE)
		_icon_label.add_theme_color_override("font_color", color)

	if _name_label != null:
		_name_label.text = str(type_def.get("name", type_id))

	if _count_label != null:
		if is_available:
			_count_label.text = "员工:%d  板件:%d" % [marketer_count, board_count]
			_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		else:
			if marketer_count <= 0:
				_count_label.text = "无可用员工"
			elif board_count <= 0:
				_count_label.text = "无可用板件"
			else:
				_count_label.text = "不可用"
			_count_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.5, 1))

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func _update_style() -> void:
	var style := StyleBoxFlat.new()
	if _selected:
		style.bg_color = Color(0.25, 0.35, 0.45, 0.95)
		style.border_color = Color(0.4, 0.7, 0.9, 1)
		style.set_border_width_all(2)
	elif is_available:
		style.bg_color = Color(0.18, 0.2, 0.24, 0.9)
	else:
		style.bg_color = Color(0.12, 0.12, 0.14, 0.7)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)

	modulate = Color(1, 1, 1, 1) if is_available else Color(0.6, 0.6, 0.6, 0.8)

