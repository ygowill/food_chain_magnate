# 公司结构面板组件
# 金字塔式布局显示公司层级结构
class_name CompanyStructure
extends Control

signal structure_changed(new_structure: Dictionary)
signal slot_overflow_warning()

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var ceo_slot: Control = $MarginContainer/VBoxContainer/CEORow/CEOSlot
@onready var manager_container: HBoxContainer = $MarginContainer/VBoxContainer/ManagerRow/ManagerContainer
@onready var slot_count_label: Label = $MarginContainer/VBoxContainer/InfoRow/SlotCountLabel
@onready var warning_label: Label = $MarginContainer/VBoxContainer/InfoRow/WarningLabel

var _employee_registry = null
var _player_data: Dictionary = {}
var _ceo_slots: int = 3  # 默认 CEO 卡槽数
var _current_structure: Dictionary = {}  # 当前结构

var _slot_nodes: Array = []  # CardSlot 节点列表
var _report_boxes: Array = []  # slot_index -> ReportsDropTarget（下属列表 + drop 区）
var _ceo_card: EmployeeCard = null
var _is_rebuilding: bool = false

func _ready() -> void:
	_build_initial_slots()

func _build_initial_slots() -> void:
	# 初始构建时创建基础卡槽
	pass

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_player_data(player: Dictionary) -> void:
	_player_data = player

	# 提取 CEO 卡槽数
	var company_struct: Dictionary = player.get("company_structure", {})
	_ceo_slots = int(company_struct.get("ceo_slots", 3))

	# 重建结构
	_rebuild_structure()

func get_current_structure() -> Dictionary:
	return _current_structure.duplicate(true)

func reset() -> void:
	_current_structure.clear()
	_rebuild_structure()

func validate() -> Result:
	# 验证当前结构是否合法
	var total_slots := _count_total_slots()
	var used_slots := _count_used_slots()

	if used_slots > total_slots:
		return Result.failure("员工数量超出公司结构容量限制 (%d/%d)" % [used_slots, total_slots])

	return Result.success()

func _count_total_slots() -> int:
	# CEO 卡槽 + 经理提供的卡槽
	var total := _ceo_slots

	# 检查在岗员工中有多少经理
	var employees: Array = Array(_player_data.get("employees", []))
	for emp_id in employees:
		var emp_def := _get_employee_def(str(emp_id))
		var manager_slots: int = int(emp_def.get("manager_slots", 0))
		if manager_slots > 0:
			total += manager_slots

	return total

func _count_used_slots() -> int:
	# 在岗员工数（不含 CEO）
	var employees: Array = Array(_player_data.get("employees", []))
	var count := 0
	for emp_id in employees:
		if str(emp_id) != "ceo":
			count += 1
	return count

func _rebuild_structure() -> void:
	_is_rebuilding = true

	# 清除旧的卡槽
	if manager_container != null:
		for child in manager_container.get_children():
			if is_instance_valid(child):
				child.queue_free()
	_slot_nodes.clear()
	_report_boxes.clear()

	if _ceo_card != null and is_instance_valid(_ceo_card):
		_ceo_card.queue_free()
		_ceo_card = null

	# 创建 CEO 卡（始终显示）
	if ceo_slot != null:
		_ceo_card = EmployeeCardClass.new()
		_ceo_card.employee_id = "ceo"
		_ceo_card.draggable = false

		var ceo_def := _get_employee_def("ceo")
		if not ceo_def.is_empty():
			_ceo_card.setup(ceo_def)
		else:
			_ceo_card.setup({"id": "ceo", "name": "CEO", "role": "manager"})

		ceo_slot.add_child(_ceo_card)

	var structure := _get_display_structure()
	_current_structure.clear()
	_current_structure["structure"] = structure.duplicate(true)

	# 创建 CEO 直属卡槽（并显示经理下属列表）
	if manager_container != null:
		for i in range(_ceo_slots):
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 4)
			manager_container.add_child(col)

			var slot := CardSlot.new()
			slot.slot_index = i
			slot.add_to_group("employee_card_drop_target")
			slot.add_to_group("company_structure_direct_slot")
			slot.card_placed.connect(_on_card_placed)
			slot.card_removed.connect(_on_card_removed)
			col.add_child(slot)
			_slot_nodes.append(slot)

			var reports_target := ReportsDropTarget.new()
			reports_target.add_to_group("employee_card_drop_target")
			reports_target.add_to_group("company_structure_reports_drop_target")
			reports_target.set_manager_slot_index(i)
			reports_target.visible = false
			col.add_child(reports_target)
			_report_boxes.append(reports_target)

	# 填充已有员工到卡槽
	_fill_existing_structure(structure)

	# 更新显示
	_update_display()
	_is_rebuilding = false

func _fill_existing_structure(structure: Array) -> void:
	for i in range(_slot_nodes.size()):
		var slot_val = _slot_nodes[i]
		if not (slot_val is CardSlot):
			continue
		var slot: CardSlot = slot_val

		var reports_target_val = _report_boxes[i] if i < _report_boxes.size() else null
		var reports_target: ReportsDropTarget = reports_target_val if reports_target_val is ReportsDropTarget else null
		var reports_box: VBoxContainer = null
		if reports_target != null:
			reports_box = reports_target.get_content()
			if reports_box != null:
				for c in reports_box.get_children():
					if is_instance_valid(c):
						c.queue_free()
			reports_target.visible = false

		var entry: Dictionary = {}
		if i < structure.size():
			var e_val = structure[i]
			if e_val is Dictionary:
				entry = e_val

		var direct_id: String = str(entry.get("employee_id", ""))
		if not direct_id.is_empty():
			var emp_def := _get_employee_def(direct_id)
			var card := EmployeeCardClass.new()
			card.employee_id = direct_id
			if not emp_def.is_empty():
				card.setup(emp_def)
			else:
				card.setup({"id": direct_id, "name": direct_id})
			slot.place_card(card)

		if reports_target == null or reports_box == null:
			continue

		var cap := 0
		if not direct_id.is_empty():
			var direct_def := _get_employee_def(direct_id)
			cap = maxi(0, int(direct_def.get("manager_slots", 0)))

		if cap <= 0:
			continue

		var reports_val = entry.get("reports", [])
		var reports: Array = reports_val if reports_val is Array else []

		var header := Label.new()
		header.text = "下属: %d/%d" % [reports.size(), cap]
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		reports_box.add_child(header)

		if reports.is_empty():
			var empty := Label.new()
			empty.text = "（无）"
			empty.add_theme_font_size_override("font_size", 10)
			empty.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 0.9))
			reports_box.add_child(empty)
			reports_target.visible = true
			continue

		for r_i in range(reports.size()):
			var rep_val = reports[r_i]
			if not (rep_val is String):
				continue
			var rep_id: String = str(rep_val)
			if rep_id.is_empty():
				continue
			var rep_def := _get_employee_def(rep_id)
			var rep_name: String = str(rep_def.get("name", rep_id))

			var line := Label.new()
			line.text = "• %s" % rep_name
			line.add_theme_font_size_override("font_size", 10)
			line.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1))
			reports_box.add_child(line)
		reports_target.visible = true

func _get_display_structure() -> Array:
	var cs: Dictionary = _player_data.get("company_structure", {})
	var employees: Array = Array(_player_data.get("employees", []))

	var structure_val = cs.get("structure", null)
	if structure_val is Array:
		var pref_arr: Array = structure_val
		var preferred_direct: Array[String] = []
		var preferred_reports_by_manager := {}
		for i in range(_ceo_slots):
			var pick := ""
			if i < pref_arr.size():
				var e_val = pref_arr[i]
				if e_val is Dictionary:
					var e: Dictionary = e_val
					var id_val = e.get("employee_id", null)
					if id_val is String:
						pick = str(id_val)
						var reps_val = e.get("reports", null)
						if reps_val is Array:
							preferred_reports_by_manager[pick] = Array(reps_val).duplicate()
			preferred_direct.append(pick)
		return _generate_strict_structure_from_employees_with_preferred_direct(employees, preferred_direct, preferred_reports_by_manager)

	# 未写入 structure：用当前在岗员工生成“严格金字塔结构”作为展示预览
	return _generate_strict_structure_from_employees(employees)

func _generate_strict_structure_from_employees(employees: Array) -> Array:
	var empty_direct: Array[String] = []
	for _i in range(_ceo_slots):
		empty_direct.append("")
	return _generate_strict_structure_from_employees_with_preferred_direct(employees, empty_direct, {})

func _generate_strict_structure_from_employees_with_preferred_direct(employees: Array, preferred_direct: Array[String], preferred_reports_by_manager: Dictionary) -> Array:
	if employees.is_empty():
		return []

	var non_ceo: Array[String] = []
	var managers: Array[String] = []
	var non_managers: Array[String] = []

	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if emp_id == "ceo":
			continue
		non_ceo.append(emp_id)
		var def := _get_employee_def(emp_id)
		var ms := maxi(0, int(def.get("manager_slots", 0)))
		if ms > 0:
			managers.append(emp_id)
		else:
			non_managers.append(emp_id)

	var structure: Array = []
	for _i in range(_ceo_slots):
		structure.append({"employee_id": "", "reports": []})

	var used := {}
	for i_slot in range(_ceo_slots):
		var pick := ""
		if i_slot < preferred_direct.size():
			var v = preferred_direct[i_slot]
			if v is String:
				pick = str(v)
		if pick.is_empty() or pick == "ceo":
			continue
		if not non_ceo.has(pick):
			continue
		if used.has(pick):
			continue
		structure[i_slot] = {"employee_id": pick, "reports": []}
		used[pick] = true

	# 确保尽量放入经理（必要时替换非经理直属槽）
	for m in managers:
		if used.has(m):
			continue

		var placed := false
		for i_empty in range(structure.size()):
			var slot_val = structure[i_empty]
			if not (slot_val is Dictionary):
				continue
			var slot: Dictionary = slot_val
			if str(slot.get("employee_id", "")).is_empty():
				structure[i_empty] = {"employee_id": m, "reports": []}
				used[m] = true
				placed = true
				break

		if placed:
			continue

		var replace_index := -1
		for i_rep in range(structure.size() - 1, -1, -1):
			var slot_val2 = structure[i_rep]
			if not (slot_val2 is Dictionary):
				continue
			var slot2: Dictionary = slot_val2
			var direct2: String = str(slot2.get("employee_id", ""))
			if direct2.is_empty():
				continue
			var direct_def2 := _get_employee_def(direct2)
			var cap2 := maxi(0, int(direct_def2.get("manager_slots", 0)))
			if cap2 <= 0:
				replace_index = i_rep
				break

		if replace_index < 0:
			break

		structure[replace_index] = {"employee_id": m, "reports": []}
		used[m] = true

	# 补齐剩余空槽：放入普通员工
	for emp_nm in non_managers:
		if used.has(emp_nm):
			continue
		var empty_index := -1
		for i_empty2 in range(structure.size()):
			var slot_val3 = structure[i_empty2]
			if not (slot_val3 is Dictionary):
				continue
			var slot3: Dictionary = slot_val3
			if str(slot3.get("employee_id", "")).is_empty():
				empty_index = i_empty2
				break
		if empty_index < 0:
			break
		structure[empty_index] = {"employee_id": emp_nm, "reports": []}
		used[emp_nm] = true

	# 分配剩余普通员工到经理卡槽
	var remaining_non_managers: Array[String] = []
	# 1) 优先放入“手动分配”的下属（按 manager_id 匹配）
	for s_i in range(structure.size()):
		var slot_val = structure[s_i]
		if not (slot_val is Dictionary):
			continue
		var slot: Dictionary = slot_val
		var direct: String = str(slot.get("employee_id", ""))
		if direct.is_empty():
			continue
		var direct_def := _get_employee_def(direct)
		var cap := maxi(0, int(direct_def.get("manager_slots", 0)))
		if cap <= 0:
			continue

		var reps: Array[String] = []
		var pref_val = preferred_reports_by_manager.get(direct, null)
		if pref_val is Array:
			var pref: Array = pref_val
			for p_i in range(pref.size()):
				var rep_val = pref[p_i]
				if not (rep_val is String):
					continue
				var rep_id: String = str(rep_val)
				if rep_id.is_empty() or rep_id == "ceo":
					continue
				if used.has(rep_id):
					continue
				if not non_managers.has(rep_id):
					continue
				reps.append(rep_id)
				used[rep_id] = true
				if reps.size() >= cap:
					break
		slot["reports"] = reps
		structure[s_i] = slot

	# 2) 自动补齐剩余普通员工到经理卡槽
	for emp_nm2 in non_managers:
		if not used.has(emp_nm2):
			remaining_non_managers.append(emp_nm2)

	var nm_index := 0
	for s_i in range(structure.size()):
		var slot_val = structure[s_i]
		if not (slot_val is Dictionary):
			continue
		var slot: Dictionary = slot_val
		var direct: String = str(slot.get("employee_id", ""))
		if direct.is_empty():
			continue
		var direct_def := _get_employee_def(direct)
		var cap := maxi(0, int(direct_def.get("manager_slots", 0)))
		if cap <= 0:
			continue
		var reps_val = slot.get("reports", [])
		var reps: Array[String] = reps_val if reps_val is Array else []
		while reps.size() < cap and nm_index < remaining_non_managers.size():
			reps.append(remaining_non_managers[nm_index])
			nm_index += 1
		slot["reports"] = reps
		structure[s_i] = slot

	return structure

func _update_display() -> void:
	var total := _count_total_slots()
	var used := _count_used_slots()

	if slot_count_label != null:
		slot_count_label.text = "卡槽: %d/%d" % [used, total]

	if warning_label != null:
		if used > total:
			warning_label.text = "超出限制!"
			warning_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))
			warning_label.visible = true
			slot_overflow_warning.emit()
		else:
			warning_label.visible = false

func _get_employee_def(employee_id: String) -> Dictionary:
	if _employee_registry != null and _employee_registry.has_method("get_employee"):
		var emp = _employee_registry.get_employee(employee_id)
		if emp != null and emp.has_method("to_dict"):
			return emp.to_dict()

	# 现行：模块系统 V2 会配置静态 EmployeeRegistry；UI 展示可直接读取
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and def_val.has_method("to_dict"):
			return def_val.to_dict()

	return {"id": employee_id, "name": employee_id}

func _on_card_placed(slot_index: int, employee_id: String) -> void:
	if _is_rebuilding:
		return
	_update_structure()

func _on_card_removed(slot_index: int, employee_id: String) -> void:
	if _is_rebuilding:
		return
	_update_structure()

func _update_structure() -> void:
	_current_structure.clear()

	var employees: Array[String] = []
	for slot in _slot_nodes:
		if is_instance_valid(slot) and slot.has_card():
			employees.append(slot.get_employee_id())

	_current_structure["employees"] = employees
	_update_display()
	structure_changed.emit(_current_structure.duplicate())


# === 内部类：卡槽 ===
class CardSlot extends PanelContainer:
	signal card_placed(slot_index: int, employee_id: String)
	signal card_removed(slot_index: int, employee_id: String)

	var slot_index: int = 0
	var _card: EmployeeCard = null
	var _drop_highlighted: bool = false

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(130, 90)
		_apply_style()

		# 空卡槽提示
		var hint := Label.new()
		hint.text = "空卡槽"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
		hint.name = "Hint"
		add_child(hint)

	func set_drop_highlighted(highlighted: bool) -> void:
		if _drop_highlighted == highlighted:
			return
		_drop_highlighted = highlighted
		_apply_style()

	func get_slot_index() -> int:
		return slot_index

	func _apply_style() -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
		if _drop_highlighted:
			style.border_color = Color(0.8, 0.7, 0.3, 0.9)
			style.set_border_width_all(3)
		else:
			style.border_color = Color(0.3, 0.3, 0.35, 0.6)
			style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

	func place_card(card: EmployeeCard) -> void:
		if _card != null:
			remove_card()

		_card = card
		_card.draggable = true
		add_child(_card)

		var hint := get_node_or_null("Hint")
		if hint != null:
			hint.visible = false

		card_placed.emit(slot_index, _card.employee_id)

	func remove_card() -> void:
		if _card == null:
			return

		var emp_id := _card.employee_id
		_card.queue_free()
		_card = null

		var hint := get_node_or_null("Hint")
		if hint != null:
			hint.visible = true

		card_removed.emit(slot_index, emp_id)

	func has_card() -> bool:
		return _card != null and is_instance_valid(_card)

	func get_employee_id() -> String:
		if _card != null:
			return _card.employee_id
		return ""


# === 内部类：经理下属 drop 区 ===
class ReportsDropTarget extends PanelContainer:
	var _drop_highlighted: bool = false
	var _content: VBoxContainer = null

	func _ready() -> void:
		custom_minimum_size = Vector2(130, 60)
		_apply_style()
		_ensure_content()

	func set_manager_slot_index(slot_index: int) -> void:
		set_meta("manager_slot_index", slot_index)

	func get_content() -> VBoxContainer:
		_ensure_content()
		return _content

	func set_drop_highlighted(highlighted: bool) -> void:
		if _drop_highlighted == highlighted:
			return
		_drop_highlighted = highlighted
		_apply_style()

	func _apply_style() -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.15, 0.65)
		if _drop_highlighted:
			style.border_color = Color(0.35, 0.85, 0.55, 0.9)
			style.set_border_width_all(2)
		else:
			style.border_color = Color(0.25, 0.25, 0.3, 0.5)
			style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

	func _ensure_content() -> void:
		if _content != null and is_instance_valid(_content):
			return
		_content = VBoxContainer.new()
		_content.add_theme_constant_override("separation", 1)
		add_child(_content)
