# 员工小图标（用于 LeftPanel 密集展示）
class_name EmployeeIcon
extends PanelContainer

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")

@export var employee_id: String = ""
@export var is_busy: bool = false

@onready var icon_texture: TextureRect = $IconTexture
@onready var fallback_label: Label = $FallbackLabel

var _employee_def: EmployeeDef = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

	_load_employee_def()
	_update_display()

func setup(emp_id: String, busy: bool = false) -> void:
	employee_id = str(emp_id).strip_edges()
	is_busy = bool(busy)
	_load_employee_def()
	_update_display()

func _load_employee_def() -> void:
	_employee_def = null
	if employee_id.is_empty():
		return
	if not EmployeeRegistryClass.is_loaded():
		return
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		_employee_def = def_val

func _update_display() -> void:
	_update_style()

	if is_instance_valid(icon_texture):
		icon_texture.visible = icon_texture.texture != null

	var name := employee_id
	var role := "special"
	if _employee_def != null:
		if not str(_employee_def.name).strip_edges().is_empty():
			name = str(_employee_def.name).strip_edges()
		if not str(_employee_def.get_role()).strip_edges().is_empty():
			role = str(_employee_def.get_role()).strip_edges()

	if is_instance_valid(fallback_label):
		var ch := "?"
		if not name.is_empty():
			ch = name.substr(0, 1)
		fallback_label.text = ch
		fallback_label.visible = not is_instance_valid(icon_texture) or (icon_texture.texture == null)
		fallback_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))

	tooltip_text = "%s%s" % [name, "（忙碌）" if is_busy else ""]

func _update_style() -> void:
	var role := "special"
	if _employee_def != null:
		var r := str(_employee_def.get_role()).strip_edges()
		if not r.is_empty():
			role = r
	var base_color: Color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)

	if is_busy:
		style.bg_color = Color(0.95, 0.91, 0.82, 0.8)
		style.border_color = Color(0.55, 0.55, 0.6, 0.9)
	else:
		style.bg_color = Color(base_color.r, base_color.g, base_color.b, 0.35)
		style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.9)

	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)

func _get_tooltip_manager():
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group("help_tooltip_manager"):
		if n != null and is_instance_valid(n) and n.has_method("request_tooltip"):
			return n
	return null

func _build_employee_tooltip_content() -> String:
	var lines: Array[String] = []

	if _employee_def != null:
		var desc := str(_employee_def.description).strip_edges()
		if not desc.is_empty():
			lines.append(desc)

		var role := str(_employee_def.get_role()).strip_edges()
		if not role.is_empty():
			lines.append("职责: %s" % role)

		lines.append("需要薪水: %s" % ("是" if bool(_employee_def.salary) else "否"))

		var slots := int(_employee_def.manager_slots)
		if slots > 0:
			lines.append("管理槽位: %d" % slots)

		var recruit_cap := int(_employee_def.recruit_capacity)
		if recruit_cap > 0:
			lines.append("招聘能力: %d" % recruit_cap)

		var train_cap := int(_employee_def.train_capacity)
		if train_cap > 0:
			lines.append("培训能力: %d" % train_cap)

		var produces_amount := int(_employee_def.produces_amount)
		var produces_food_type := str(_employee_def.produces_food_type).strip_edges()
		if produces_amount > 0 and not produces_food_type.is_empty():
			lines.append("生产: %s x%d" % [produces_food_type, produces_amount])

	if is_busy:
		lines.append("状态: 忙碌（营销中）")

	if lines.is_empty():
		lines.append(employee_id)

	return "\n".join(lines)

func _on_mouse_entered() -> void:
	if employee_id.is_empty():
		return
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return

	var key := "employee_%s" % employee_id
	if mgr.has_method("add_help_entry"):
		if not (mgr.HELP_DATABASE is Dictionary and mgr.HELP_DATABASE.has(key)):
			var title := employee_id
			if _employee_def != null and not str(_employee_def.name).strip_edges().is_empty():
				title = str(_employee_def.name).strip_edges()
			mgr.add_help_entry(key, title, _build_employee_tooltip_content())

	var pos: Vector2 = get_global_rect().position + (size / 2.0)
	mgr.request_tooltip(key, pos)

func _on_mouse_exited() -> void:
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_tooltip"):
		mgr.hide_tooltip()
