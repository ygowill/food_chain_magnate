# 员工卡牌组件
# 显示单张员工卡的信息
class_name EmployeeCard
extends PanelContainer

const EmployeeDefClass = preload("res://core/data/employee_def.gd")

signal card_clicked(employee_id: String)
signal card_drag_started(employee_id: String)
signal card_drag_ended(employee_id: String, drop_position: Vector2)

enum CardVariant {
	COMPACT,
	FULL,
}

@export var employee_id: String = ""
@export var show_salary_indicator: bool = true
@export var draggable: bool = true
@export var variant: CardVariant = CardVariant.COMPACT

var _employee_def: Dictionary = {}
var _selected: bool = false
var _busy: bool = false
var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO

# UI 子节点
var _role_color_rect: ColorRect
var _name_label: Label
var _salary_indicator: Label
var _description_label: Label
var _level_label: Label
var _range_label: Label
var _salary_label: Label

var _portrait_texture: TextureRect
var _portrait_placeholder_rect: ColorRect

var _entry_icon_rect: ColorRect
var _range_icon_rect: ColorRect
var _salary_icon_rect: ColorRect

const COMPACT_SIZE := Vector2(130, 90)
const FULL_SIZE := Vector2(180, 252)

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _build_ui() -> void:
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()

	_role_color_rect = null
	_name_label = null
	_salary_indicator = null
	_description_label = null
	_level_label = null
	_range_label = null
	_salary_label = null
	_portrait_texture = null
	_portrait_placeholder_rect = null
	_entry_icon_rect = null
	_range_icon_rect = null
	_salary_icon_rect = null

	custom_minimum_size = FULL_SIZE if variant == CardVariant.FULL else COMPACT_SIZE

	var margin := MarginContainer.new()
	var pad := 12 if variant == CardVariant.FULL else 6
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6 if variant == CardVariant.FULL else 2)
	margin.add_child(vbox)

	if variant == CardVariant.FULL:
		_build_full_layout(vbox)
	else:
		_build_compact_layout(vbox)

	_update_style()
	queue_redraw()

func _build_compact_layout(vbox: VBoxContainer) -> void:
	# 顶部：类别色整行底色 + 名称
	_role_color_rect = ColorRect.new()
	_role_color_rect.custom_minimum_size = Vector2(0, 20)
	_role_color_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_role_color_rect)

	var top_margin := MarginContainer.new()
	top_margin.anchors_preset = Control.PRESET_FULL_RECT
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_theme_constant_override("margin_left", 6)
	top_margin.add_theme_constant_override("margin_right", 6)
	_role_color_rect.add_child(top_margin)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(_name_label)

	# 底部：简短描述
	_description_label = Label.new()
	_description_label.add_theme_font_size_override("font_size", 11)
	_description_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_description_label)

	# 底部图标行（暂用色块占位：Entry / 路程 / 工资）
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	vbox.add_child(bottom)

	_entry_icon_rect = ColorRect.new()
	_entry_icon_rect.custom_minimum_size = Vector2(16, 16)
	bottom.add_child(_entry_icon_rect)

	var range_box := HBoxContainer.new()
	range_box.add_theme_constant_override("separation", 4)
	range_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(range_box)

	_range_icon_rect = ColorRect.new()
	_range_icon_rect.custom_minimum_size = Vector2(16, 16)
	range_box.add_child(_range_icon_rect)

	_range_label = Label.new()
	_range_label.add_theme_font_size_override("font_size", 11)
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_box.add_child(_range_label)

	var salary_box := HBoxContainer.new()
	salary_box.add_theme_constant_override("separation", 4)
	salary_box.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(salary_box)

	_salary_icon_rect = ColorRect.new()
	_salary_icon_rect.custom_minimum_size = Vector2(16, 16)
	salary_box.add_child(_salary_icon_rect)

	_salary_label = Label.new()
	_salary_label.add_theme_font_size_override("font_size", 11)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	salary_box.add_child(_salary_label)

func _build_full_layout(vbox: VBoxContainer) -> void:
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_name_label)

	var portrait_box := PanelContainer.new()
	portrait_box.custom_minimum_size = Vector2(120, 120)
	portrait_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(portrait_box)

	var portrait_root := Control.new()
	portrait_root.custom_minimum_size = Vector2(120, 120)
	portrait_box.add_child(portrait_root)

	_portrait_placeholder_rect = ColorRect.new()
	_portrait_placeholder_rect.anchors_preset = Control.PRESET_FULL_RECT
	_portrait_placeholder_rect.color = Color(0.2, 0.2, 0.22, 1)
	portrait_root.add_child(_portrait_placeholder_rect)

	_portrait_texture = TextureRect.new()
	_portrait_texture.anchors_preset = Control.PRESET_FULL_RECT
	_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_root.add_child(_portrait_texture)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8, 1))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_level_label)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	_description_label = Label.new()
	_description_label.add_theme_font_size_override("font_size", 12)
	_description_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_description_label)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	_entry_icon_rect = ColorRect.new()
	_entry_icon_rect.custom_minimum_size = Vector2(18, 18)
	bottom.add_child(_entry_icon_rect)

	var range_box := HBoxContainer.new()
	range_box.add_theme_constant_override("separation", 6)
	range_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(range_box)

	_range_icon_rect = ColorRect.new()
	_range_icon_rect.custom_minimum_size = Vector2(18, 18)
	range_box.add_child(_range_icon_rect)

	_range_label = Label.new()
	_range_label.add_theme_font_size_override("font_size", 12)
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_box.add_child(_range_label)

	var salary_box := HBoxContainer.new()
	salary_box.add_theme_constant_override("separation", 6)
	salary_box.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(salary_box)

	_salary_icon_rect = ColorRect.new()
	_salary_icon_rect.custom_minimum_size = Vector2(18, 18)
	salary_box.add_child(_salary_icon_rect)

	_salary_label = Label.new()
	_salary_label.add_theme_font_size_override("font_size", 12)
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	salary_box.add_child(_salary_label)

func setup(employee_def: Dictionary) -> void:
	_employee_def = employee_def
	employee_id = str(employee_def.get("id", ""))
	_update_display()

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func set_busy(busy: bool) -> void:
	_busy = busy
	_update_style()

func _update_display() -> void:
	if _name_label == null:
		return

	var name: String = str(_employee_def.get("name", employee_id))
	_name_label.text = name

	var role: String = str(_employee_def.get("role", "special"))
	var color: Color = Color(EmployeeDefClass.role_to_color_hex(role))
	if _role_color_rect != null:
		_role_color_rect.color = color

	var salary: bool = bool(_employee_def.get("salary", true))
	if _salary_indicator != null:
		_salary_indicator.text = "$" if (salary and show_salary_indicator) else ""
		_salary_indicator.visible = salary and show_salary_indicator
	if _salary_label != null:
		_salary_label.text = "$" if (salary and show_salary_indicator) else ""

	# 等级：根据是否可培训推断
	var train_to: Array = Array(_employee_def.get("train_to", []))
	var is_entry = _employee_def.get("tags", []).has("entry_level") if _employee_def.has("tags") else false
	if _entry_icon_rect != null:
		_entry_icon_rect.visible = is_entry
	if _level_label != null:
		if is_entry:
			_level_label.text = "Lv.1 (入门级)"
		elif train_to.is_empty():
			_level_label.text = "Lv.3 (高级)"
		else:
			_level_label.text = "Lv.2 (中级)"

	var desc: String = str(_employee_def.get("description", ""))
	var max_len := 120 if variant == CardVariant.FULL else 40
	if desc.length() > max_len:
		desc = desc.substr(0, max_len) + "..."
	_description_label.text = desc

	# 距离/范围（暂用 range.value；未来可用图标替代）
	if _range_label != null:
		var range_val = _employee_def.get("range", null)
		var range_type := ""
		var range_value := 0
		if range_val is Dictionary:
			range_type = str(Dictionary(range_val).get("type", "")).strip_edges()
			range_value = int(Dictionary(range_val).get("value", 0))
		if range_type.is_empty() or range_value <= 0:
			_range_label.text = ""
		else:
			if range_type == "global":
				_range_label.text = "∞"
			else:
				_range_label.text = "%s%d" % ["R" if range_type == "road" else "", range_value]

	# 头像占位（资源待补齐：使用空白色块）
	if _portrait_placeholder_rect != null:
		var ph := Color(color.r, color.g, color.b, 0.22)
		ph.a = 1.0
		_portrait_placeholder_rect.color = ph

	if _portrait_texture != null:
		_portrait_texture.visible = _portrait_texture.texture != null
	if _portrait_placeholder_rect != null:
		_portrait_placeholder_rect.visible = (_portrait_texture == null) or (_portrait_texture.texture == null)

	# 图标占位色块（后续替换为 png）
	var icon_placeholder := Color(0.82, 0.82, 0.86, 0.35)
	if _entry_icon_rect != null:
		_entry_icon_rect.color = Color(color.r, color.g, color.b, 0.75)
	if _range_icon_rect != null:
		_range_icon_rect.color = icon_placeholder
	if _salary_icon_rect != null:
		_salary_icon_rect.color = icon_placeholder

	_update_style()
	queue_redraw()

func _update_style() -> void:
	var style := StyleBoxFlat.new()

	var role: String = str(_employee_def.get("role", "special"))
	var base_color: Color = Color(EmployeeDefClass.role_to_color_hex(role))

	if _busy:
		style.bg_color = Color(0.3, 0.3, 0.35, 0.55)
		style.border_color = Color(0.7, 0.7, 0.75, 0.9)
		style.set_border_width_all(1)
		style.shadow_color = Color(0, 0, 0, 0.25)
		style.shadow_size = 6
		modulate = Color(0.6, 0.6, 0.6, 0.8)
	elif _selected:
		style.bg_color = Color(0.3, 0.5, 0.7, 0.65)
		style.border_color = Color(0.5, 0.8, 1.0, 0.95)
		style.set_border_width_all(2)
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 8
		modulate = Color(1, 1, 1, 1)
	else:
		style.bg_color = Color(0.17, 0.18, 0.2, 0.95)
		style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.65)
		style.set_border_width_all(1 if variant == CardVariant.COMPACT else 2)
		style.shadow_color = Color(0, 0, 0, 0.25)
		style.shadow_size = 6 if variant == CardVariant.COMPACT else 10
		modulate = Color(1, 1, 1, 1)

	style.set_corner_radius_all(8 if variant == CardVariant.FULL else 4)
	add_theme_stylebox_override("panel", style)

func _draw() -> void:
	if _employee_def.is_empty():
		return
	var tags_val = _employee_def.get("tags", null)
	if not (tags_val is Array) or not Array(tags_val).has("entry_level"):
		return

	var role: String = str(_employee_def.get("role", "special"))
	var base_color: Color = Color(EmployeeDefClass.role_to_color_hex(role))

	var tri := 24.0 if variant == CardVariant.FULL else 18.0
	var points := PackedVector2Array([Vector2(0, 0), Vector2(tri, 0), Vector2(0, tri)])
	draw_colored_polygon(points, base_color)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_start_pos = e.position
				_dragging = false
				card_clicked.emit(employee_id)
			else:
				if _dragging and draggable:
					_dragging = false
					card_drag_ended.emit(employee_id, get_global_mouse_position())

	if event is InputEventMouseMotion and draggable:
		var e2: InputEventMouseMotion = event
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var distance := e2.position.distance_to(_drag_start_pos)
			if distance > 5.0 and not _dragging:
				_dragging = true
				card_drag_started.emit(employee_id)

func _get_tooltip_manager():
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group("help_tooltip_manager"):
		if n != null and is_instance_valid(n) and n.has_method("request_tooltip"):
			return n
	return null

func _build_employee_tooltip_content() -> String:
	var lines: Array[String] = []
	var desc := str(_employee_def.get("description", "")).strip_edges()
	if not desc.is_empty():
		lines.append(desc)

	var role := str(_employee_def.get("role", "")).strip_edges()
	if not role.is_empty():
		lines.append("职责: %s" % role)

	var salary := bool(_employee_def.get("salary", true))
	lines.append("需要薪水: %s" % ("是" if salary else "否"))

	var manager_slots := int(_employee_def.get("manager_slots", 0))
	if manager_slots > 0:
		lines.append("管理槽位: %d" % manager_slots)

	var recruit_cap := int(_employee_def.get("recruit_capacity", 0))
	if recruit_cap > 0:
		lines.append("招聘能力: %d" % recruit_cap)

	var train_cap := int(_employee_def.get("train_capacity", 0))
	if train_cap > 0:
		lines.append("培训能力: %d" % train_cap)

	var produces_amount := int(_employee_def.get("produces_amount", 0))
	var produces_food_type := str(_employee_def.get("produces_food_type", "")).strip_edges()
	if produces_amount > 0 and not produces_food_type.is_empty():
		lines.append("生产: %s x%d" % [produces_food_type, produces_amount])

	return "\n".join(lines)

func _on_mouse_entered() -> void:
	if employee_id.is_empty():
		return
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return

	var key := "employee_%s" % employee_id
	if mgr.has_method("add_help_entry"):
		# 若已存在条目（例如内置 employee_* 文案），则不覆盖
		if not (mgr.HELP_DATABASE is Dictionary and mgr.HELP_DATABASE.has(key)):
			var title := str(_employee_def.get("name", employee_id)).strip_edges()
			if title.is_empty():
				title = employee_id
			mgr.add_help_entry(key, title, _build_employee_tooltip_content())

	var pos: Vector2 = get_global_rect().position + (size / 2.0)
	mgr.request_tooltip(key, pos)

func _on_mouse_exited() -> void:
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_tooltip"):
		mgr.hide_tooltip()
