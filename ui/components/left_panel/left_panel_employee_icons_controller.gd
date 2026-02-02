# LeftPanel：员工图标/列表渲染（手牌/公司结构）
extends RefCounted

var _panel = null

func setup(panel) -> void:
	_panel = panel

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_refresh_employee_icons()

func _refresh_employee_icons() -> void:
	_clear_employee_icon_containers()

	if _panel._game_state == null or not (_panel._game_state.players is Array) or _panel._game_state.players.is_empty():
		_update_employee_row_visibility()
		return

	var view_id: int = _panel._resolve_view_player_id()
	if view_id < 0 or view_id >= _panel._game_state.players.size():
		_update_employee_row_visibility()
		return

	var player_val = _panel._game_state.players[view_id]
	var player: Dictionary = player_val if player_val is Dictionary else {}

	_build_hand_employee_icons(player)
	_build_company_employee_icons(player)
	_update_employee_row_visibility()

func _clear_employee_icon_containers() -> void:
	for c in [
		_panel.hand_management_icons,
		_panel.hand_kitchen_icons,
		_panel.hand_marketing_icons,
		_panel.hand_other_icons,
		_panel.company_management_icons,
		_panel.company_kitchen_icons,
		_panel.company_marketing_icons,
		_panel.company_other_icons,
	]:
		_clear_container_children(c)

func _clear_container_children(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	for ch in container.get_children():
		if is_instance_valid(ch):
			ch.queue_free()

func _build_hand_employee_icons(player: Dictionary) -> void:
	if player == null:
		return

	var reserve: Array[String] = []
	var busy: Array[String] = []

	for e in Array(player.get("reserve_employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			reserve.append(s)
	for e2 in Array(player.get("busy_marketers", [])):
		var s2 := str(e2).strip_edges()
		if not s2.is_empty():
			busy.append(s2)

	reserve.sort()
	busy.sort()

	for emp_id in reserve:
		_add_employee_entry_to_category(_get_hand_icons_for_category(_get_employee_category(emp_id)), emp_id, false)
	for emp_id2 in busy:
		_add_employee_entry_to_category(_get_hand_icons_for_category(_get_employee_category(emp_id2)), emp_id2, true)

func _build_company_employee_icons(player: Dictionary) -> void:
	if player == null:
		return

	var employees: Array[String] = []
	for e in Array(player.get("employees", [])):
		var s := str(e).strip_edges()
		if not s.is_empty():
			employees.append(s)
	employees.sort()

	for emp_id in employees:
		_add_employee_entry_to_category(_get_company_icons_for_category(_get_employee_category(emp_id)), emp_id, false)

func _add_employee_entry_to_category(container: VBoxContainer, employee_id: String, busy: bool) -> void:
	if container == null or not is_instance_valid(container):
		return

	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return

	var name := _get_employee_display_name(emp_id)
	var label_text := "• %s" % name
	if name != emp_id:
		label_text = "• %s (%s)" % [name, emp_id]
	if busy:
		label_text += "（忙）"

	var line := Label.new()
	line.text = label_text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD
	var fs := 16
	if Globals != null:
		fs = int(Globals.get_scaled_font_size(16))
	line.add_theme_font_size_override("font_size", fs)
	if busy:
		line.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 1))
	else:
		line.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	container.add_child(line)

func _get_employee_display_name(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return ""
	if EmployeeRegistry.is_loaded():
		var def_val = EmployeeRegistry.get_def(emp_id)
		if def_val is EmployeeDef:
			var def: EmployeeDef = def_val
			var name := def.name.strip_edges()
			if not name.is_empty():
				return name
	return emp_id

func _get_employee_category(employee_id: String) -> String:
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty():
		return "其他"

	if EmployeeRegistry.is_loaded():
		var def_val = EmployeeRegistry.get_def(emp_id)
		if def_val is EmployeeDef:
			var def: EmployeeDef = def_val
			return _panel._role_to_category(def.get_role())

	return "其他"

func _get_hand_icons_for_category(category: String) -> VBoxContainer:
	match category:
		"管理":
			return _panel.hand_management_icons
		"厨房":
			return _panel.hand_kitchen_icons
		"营销":
			return _panel.hand_marketing_icons
		_:
			return _panel.hand_other_icons

func _get_company_icons_for_category(category: String) -> VBoxContainer:
	match category:
		"管理":
			return _panel.company_management_icons
		"厨房":
			return _panel.company_kitchen_icons
		"营销":
			return _panel.company_marketing_icons
		_:
			return _panel.company_other_icons

func _update_employee_row_visibility() -> void:
	if is_instance_valid(_panel.hand_management_row) and is_instance_valid(_panel.hand_management_icons):
		_panel.hand_management_row.visible = _panel.hand_management_icons.get_child_count() > 0
	if is_instance_valid(_panel.hand_kitchen_row) and is_instance_valid(_panel.hand_kitchen_icons):
		_panel.hand_kitchen_row.visible = _panel.hand_kitchen_icons.get_child_count() > 0
	if is_instance_valid(_panel.hand_marketing_row) and is_instance_valid(_panel.hand_marketing_icons):
		_panel.hand_marketing_row.visible = _panel.hand_marketing_icons.get_child_count() > 0
	if is_instance_valid(_panel.hand_other_row) and is_instance_valid(_panel.hand_other_icons):
		_panel.hand_other_row.visible = _panel.hand_other_icons.get_child_count() > 0

	if is_instance_valid(_panel.company_management_row) and is_instance_valid(_panel.company_management_icons):
		_panel.company_management_row.visible = _panel.company_management_icons.get_child_count() > 0
	if is_instance_valid(_panel.company_kitchen_row) and is_instance_valid(_panel.company_kitchen_icons):
		_panel.company_kitchen_row.visible = _panel.company_kitchen_icons.get_child_count() > 0
	if is_instance_valid(_panel.company_marketing_row) and is_instance_valid(_panel.company_marketing_icons):
		_panel.company_marketing_row.visible = _panel.company_marketing_icons.get_child_count() > 0
	if is_instance_valid(_panel.company_other_row) and is_instance_valid(_panel.company_other_icons):
		_panel.company_other_row.visible = _panel.company_other_icons.get_child_count() > 0
