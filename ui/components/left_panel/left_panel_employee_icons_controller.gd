# LeftPanel：员工标签渲染（色彩标签样式）
# 将员工显示为带角色颜色边框的紧凑标签
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

var _panel = null
var _company_employee_count: int = 0
var _hand_employee_count: int = 0
var _busy_employee_count: int = 0

func setup(panel) -> void:
	_panel = panel

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_refresh_employee_tags()

func _refresh_employee_tags() -> void:
	_company_employee_count = 0
	_hand_employee_count = 0
	_busy_employee_count = 0
	_clear_tag_containers()

	if _panel._game_state == null or not (_panel._game_state.players is Array) or _panel._game_state.players.is_empty():
		_update_section_visibility()
		return

	var view_id: int = _panel._resolve_view_player_id()
	if view_id < 0 or view_id >= _panel._game_state.players.size():
		_update_section_visibility()
		return

	var player_val = _panel._game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	_build_company_employee_tags(player)
	_build_hand_employee_tags(player)
	_build_busy_marketer_tags(player)
	_update_section_visibility()
	_update_section_headers(player)

func _clear_tag_containers() -> void:
	_clear_container_children(_panel.company_tags_flow)
	_clear_container_children(_panel.hand_tags_flow)
	_clear_container_children(_panel.busy_tags_flow)

func _clear_container_children(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	for ch in container.get_children():
		if is_instance_valid(ch):
			ch.queue_free()

func _build_company_employee_tags(player: Dictionary) -> void:
	if player == null:
		return
	if not is_instance_valid(_panel.company_tags_flow):
		return

	var employees: Array[String] = []
	for e in Array(player.get("employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			employees.append(s)
	employees.sort()
	_company_employee_count = employees.size()

	if employees.is_empty():
		_panel.company_tags_flow.add_child(_create_empty_hint("暂无在岗员工"))
		return

	for emp_id in employees:
		var tag := _create_employee_tag(emp_id, false, player)
		_panel.company_tags_flow.add_child(tag)

func _build_hand_employee_tags(player: Dictionary) -> void:
	if player == null:
		return
	if not is_instance_valid(_panel.hand_tags_flow):
		return

	var reserve: Array[String] = []

	for e in Array(player.get("reserve_employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			reserve.append(s)

	reserve.sort()
	_hand_employee_count = reserve.size()

	if _hand_employee_count <= 0:
		_panel.hand_tags_flow.add_child(_create_empty_hint("暂无手牌员工"))
		return

	for emp_id in reserve:
		var tag := _create_employee_tag(emp_id, false, player)
		_panel.hand_tags_flow.add_child(tag)

func _build_busy_marketer_tags(player: Dictionary) -> void:
	if player == null:
		return
	if not is_instance_valid(_panel.busy_tags_flow):
		return

	var busy: Array[String] = []
	for e in Array(player.get("busy_marketers", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			busy.append(s)
	busy.sort()
	_busy_employee_count = busy.size()

	if _busy_employee_count <= 0:
		_panel.busy_tags_flow.add_child(_create_empty_hint("暂无忙碌中的营销人员"))
		return

	for emp_id in busy:
		var tag := _create_employee_tag(emp_id, true, player)
		_panel.busy_tags_flow.add_child(tag)

func _create_employee_tag(emp_id: String, is_busy: bool, player: Dictionary) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.custom_minimum_size = Vector2(0, 36)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 获取员工定义
	var def: EmployeeDef = null
	var role := "special"
	var display_name := emp_id
	if EmployeeRegistry.is_loaded():
		var def_val = EmployeeRegistry.get_def(emp_id)
		if def_val is EmployeeDef:
			def = def_val
			role = def.get_role()
			if not def.name.is_empty():
				display_name = def.name

	# 获取角色颜色
	var role_color := EmployeeRoleColorsClass.role_to_color(role)

	# 创建 StyleBoxFlat
	var style := StyleBoxFlat.new()
	style.bg_color = Color(role_color.r, role_color.g, role_color.b, 0.15)
	style.border_color = role_color
	style.border_width_left = 3
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 7
	style.content_margin_right = 5
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", style)

	# 创建标签
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var level_suffix := _get_level_suffix(def)
	label.text = display_name + level_suffix
	var fs := 18
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(18))
	label.add_theme_font_size_override("font_size", fs)
	UiStylesClass.apply_label_dark(label)
	tag.add_child(label)

	# 忙碌状态：50%透明度
	if is_busy:
		tag.modulate.a = 0.5

	# 交互：鼠标悬浮和点击显示员工卡片
	tag.mouse_filter = Control.MOUSE_FILTER_STOP
	tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tag.mouse_entered.connect(Callable(self, "_on_tag_mouse_entered").bind(emp_id, tag))
	tag.mouse_exited.connect(Callable(self, "_on_tag_mouse_exited"))
	tag.gui_input.connect(Callable(self, "_on_tag_gui_input").bind(emp_id, tag))

	# Tooltip
	var tooltip_lines: Array[String] = []
	tooltip_lines.append(display_name)
	if def != null:
		if not def.description.is_empty():
			tooltip_lines.append(def.description)
		var requires_salary := false
		if EmployeeRegistry.is_loaded():
			requires_salary = EmployeeRulesClass.requires_salary(emp_id, player)
		if requires_salary:
			var salary_cost := _resolve_salary_cost(player)
			tooltip_lines.append("薪资: 需支付 ($%d/回合)" % salary_cost)
		else:
			tooltip_lines.append("薪资: 无需支付")
	if is_busy:
		tooltip_lines.append("（忙碌中）")
	tag.tooltip_text = "\n".join(tooltip_lines)

	return tag

func _create_empty_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	var fs := 16
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(16))
	label.add_theme_font_size_override("font_size", fs)
	UiStylesClass.apply_label_hint_dark(label)
	return label

func _get_level_suffix(_def: EmployeeDef) -> String:
	return ""

func _resolve_salary_cost(player: Dictionary) -> int:
	if _panel == null or not is_instance_valid(_panel):
		return 0
	if _panel.has_method("_get_player_salary_cost"):
		return int(_panel.call("_get_player_salary_cost", player))
	return 0

func _update_section_visibility() -> void:
	if is_instance_valid(_panel.company_section):
		_panel.company_section.visible = true
	if is_instance_valid(_panel.hand_section):
		_panel.hand_section.visible = true
	if is_instance_valid(_panel.busy_section):
		_panel.busy_section.visible = true

func _update_section_headers(_player: Dictionary) -> void:
	# 更新公司结构标题显示员工数量
	if is_instance_valid(_panel.company_section_header) and is_instance_valid(_panel.company_tags_flow):
		var count: int = _company_employee_count
		_panel.company_section_header.text = "公司结构 (%d)" % count if count > 0 else "公司结构"

	# 更新手牌标题显示数量
	if is_instance_valid(_panel.hand_section_header) and is_instance_valid(_panel.hand_tags_flow):
		var count: int = _hand_employee_count
		_panel.hand_section_header.text = "手牌 (%d)" % count if count > 0 else "手牌"

	# 更新忙碌营销员标题显示数量
	if is_instance_valid(_panel.busy_section_header) and is_instance_valid(_panel.busy_tags_flow):
		var busy_count: int = _busy_employee_count
		_panel.busy_section_header.text = "忙碌中的营销人员 (%d)" % busy_count if busy_count > 0 else "忙碌中的营销人员"

# === 交互：员工卡片预览 ===
func _get_preview_manager():
	if _panel == null or not is_instance_valid(_panel):
		return null
	var tree = _panel.get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("employee_card_preview_manager"):
		if n != null and is_instance_valid(n) and n.has_method("request_preview"):
			return n
	return null

func _on_tag_mouse_entered(employee_id: String, control: Control) -> void:
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if control == null or not is_instance_valid(control):
		return
	var pos: Vector2 = control.get_global_rect().position + (control.size / 2.0)
	mgr.request_preview(str(employee_id), pos)

func _on_tag_mouse_exited() -> void:
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_preview"):
		mgr.hide_preview()

func _on_tag_gui_input(event: InputEvent, employee_id: String, control: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var e: InputEventMouseButton = event
	if e.button_index != MOUSE_BUTTON_LEFT or not e.pressed:
		return
	var mgr = _get_preview_manager()
	if mgr == null:
		return
	if control == null or not is_instance_valid(control):
		return
	var pos: Vector2 = control.get_global_rect().position + (control.size / 2.0)
	if mgr.has_method("show_immediate"):
		mgr.show_immediate(str(employee_id), pos)
