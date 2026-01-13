# 公司结构面板组件
# 金字塔式布局显示公司层级结构
class_name CompanyStructure
extends Control

signal structure_changed(new_structure: Dictionary)
signal slot_overflow_warning()
signal card_dropped(employee_id: String, target: Control)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var ceo_slot: Control = $MarginContainer/VBoxContainer/CEORow/CEOSlot
@onready var manager_container: HBoxContainer = $MarginContainer/VBoxContainer/ManagerRow/ManagerScroll/ManagerContainer
@onready var slot_count_label: Label = $MarginContainer/VBoxContainer/InfoRow/SlotCountLabel
@onready var warning_label: Label = $MarginContainer/VBoxContainer/InfoRow/WarningLabel

var _employee_registry = null
var _player_data: Dictionary = {}
var _ceo_slots: int = 3  # 默认 CEO 卡槽数
var _current_structure: Dictionary = {}  # 当前结构

var _slot_nodes: Array = []  # CardSlot 节点列表
var _report_containers: Array = []  # slot_index -> VBoxContainer（下属卡槽容器）
var _report_cards: Array = []  # 下属卡槽中的 EmployeeCard
var _ceo_card: EmployeeCard = null
var _is_rebuilding: bool = false

var _drag_enabled: bool = false
var _direct_cards_by_slot: Array = []  # slot_index -> EmployeeCard（直属槽中的卡）
var _drag_layer: CanvasLayer = null
var _drag_preview: EmployeeCard = null
var _dragging_employee_id: String = ""
var _drag_source_card: EmployeeCard = null
var _drag_source_modulate: Color = Color(1, 1, 1, 1)
var _drag_preview_offset: Vector2 = Vector2.ZERO
var _hover_drop_target: Control = null

func _ready() -> void:
	set_process(false)
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

func set_drag_enabled(enabled: bool) -> void:
	if _drag_enabled == enabled:
		return
	_drag_enabled = enabled
	if not _drag_enabled:
		_end_drag_visuals()
	_update_card_drag_enabled()

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
		if str(emp_id) == "ceo":
			continue
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
	_end_drag_visuals()

	# 清除旧的卡槽
	if manager_container != null:
		for child in manager_container.get_children():
			if is_instance_valid(child):
				child.queue_free()
		_slot_nodes.clear()
		_report_containers.clear()
		_report_cards.clear()
		_direct_cards_by_slot.clear()

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
			_direct_cards_by_slot.append(null)

			var reports_box := VBoxContainer.new()
			reports_box.add_theme_constant_override("separation", 4)
			reports_box.visible = false
			col.add_child(reports_box)
			_report_containers.append(reports_box)

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

		var reports_box_val = _report_containers[i] if i < _report_containers.size() else null
		var reports_box: VBoxContainer = reports_box_val if reports_box_val is VBoxContainer else null
		if reports_box != null:
			for c in reports_box.get_children():
				if is_instance_valid(c):
					c.queue_free()
			reports_box.visible = false

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
			card.draggable = _drag_enabled
			if not emp_def.is_empty():
				card.setup(emp_def)
			else:
				card.setup({"id": direct_id, "name": direct_id})
			card.card_drag_started.connect(_on_direct_card_drag_started.bind(card))
			card.card_drag_ended.connect(_on_direct_card_drag_ended.bind(card))
			slot.place_card(card)
			if i < _direct_cards_by_slot.size():
				_direct_cards_by_slot[i] = card

		if reports_box == null:
			continue

		var cap := 0
		if not direct_id.is_empty():
			var direct_def := _get_employee_def(direct_id)
			cap = maxi(0, int(direct_def.get("manager_slots", 0)))

		if cap <= 0:
			continue

		var reports_val = entry.get("reports", [])
		var reports_any: Array = reports_val if reports_val is Array else []
		var reports: Array[String] = []
		for rep_val in reports_any:
			if not (rep_val is String):
				continue
			var rep_id := str(rep_val).strip_edges()
			if rep_id.is_empty() or rep_id == "ceo":
				continue
			reports.append(rep_id)

		var header := Label.new()
		header.text = "下属卡槽: %d/%d" % [min(reports.size(), cap), cap]
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		reports_box.add_child(header)

		for r_i in range(cap):
			var report_slot := CardSlot.new()
			report_slot.add_to_group("employee_card_drop_target")
			report_slot.add_to_group("company_structure_reports_drop_target")
			report_slot.set_meta("manager_slot_index", i)
			report_slot.set_meta("manager_employee_id", direct_id)
			report_slot.set_meta("report_slot_index", r_i)
			reports_box.add_child(report_slot)

			if r_i < reports.size():
				var rep_id2: String = reports[r_i]
				var rep_def := _get_employee_def(rep_id2)
				var rep_card := EmployeeCardClass.new()
				rep_card.employee_id = rep_id2
				rep_card.draggable = _drag_enabled
				if not rep_def.is_empty():
					rep_card.setup(rep_def)
				else:
					rep_card.setup({"id": rep_id2, "name": rep_id2})
				rep_card.card_drag_started.connect(_on_direct_card_drag_started.bind(rep_card))
				rep_card.card_drag_ended.connect(_on_direct_card_drag_ended.bind(rep_card))
				report_slot.place_card(rep_card)
				_report_cards.append(rep_card)

		reports_box.visible = true

	_update_card_drag_enabled()

func _get_display_structure() -> Array:
	var cs: Dictionary = _player_data.get("company_structure", {})
	var employees: Array = Array(_player_data.get("employees", []))

	var structure_val = cs.get("structure", null)
	if structure_val is Array:
		var pref_arr: Array = structure_val
		var preferred_direct: Array[String] = []
		var preferred_reports_by_slot := {}
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
							preferred_reports_by_slot[i] = Array(reps_val).duplicate()
			preferred_direct.append(pick)
		return _generate_strict_structure_from_employees_with_preferred_direct(employees, preferred_direct, preferred_reports_by_slot)

	# 未写入 structure：用当前在岗员工生成“严格金字塔结构”作为展示预览
	return _generate_strict_structure_from_employees(employees)

func _generate_strict_structure_from_employees(employees: Array) -> Array:
	var empty_direct: Array[String] = []
	for _i in range(_ceo_slots):
		empty_direct.append("")
	return _generate_strict_structure_from_employees_with_preferred_direct(employees, empty_direct, {})

func _generate_strict_structure_from_employees_with_preferred_direct(employees: Array, preferred_direct: Array[String], preferred_reports_by_slot: Dictionary) -> Array:
	if employees.is_empty():
		return []

	var managers: Array[String] = []
	var non_managers: Array[String] = []
	var available_counts: Dictionary = {}  # employee_id -> count（在岗）

	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		var prev_val = available_counts.get(emp_id, 0)
		available_counts[emp_id] = int(prev_val) + 1
		var def := _get_employee_def(emp_id)
		var ms := maxi(0, int(def.get("manager_slots", 0)))
		if ms > 0:
			managers.append(emp_id)
		else:
			non_managers.append(emp_id)

	var structure: Array = []
	for _i in range(_ceo_slots):
		structure.append({"employee_id": "", "reports": []})

	var used_counts: Dictionary = {}  # employee_id -> used_count（直属 + 下属）

	# 1) 优先放入“手动分配”的 CEO 直属槽
	for i_slot in range(_ceo_slots):
		var pick := ""
		if i_slot < preferred_direct.size():
			var v = preferred_direct[i_slot]
			if v is String:
				pick = str(v)
		if pick.is_empty() or pick == "ceo":
			continue
		var avail: int = int(available_counts.get(pick, 0))
		if avail <= 0:
			continue
		var used_now: int = int(used_counts.get(pick, 0))
		if used_now >= avail:
			continue
		structure[i_slot] = {"employee_id": pick, "reports": []}
		used_counts[pick] = used_now + 1

	# 2) 尽量放入经理（必要时替换非经理直属槽）
	for m in managers:
		var m_id: String = str(m)
		if m_id.is_empty() or m_id == "ceo":
			continue
		var avail_m: int = int(available_counts.get(m_id, 0))
		if avail_m <= 0:
			continue
		var used_m: int = int(used_counts.get(m_id, 0))
		if used_m >= avail_m:
			continue

		var placed := false
		for i_empty in range(structure.size()):
			var slot_val = structure[i_empty]
			if not (slot_val is Dictionary):
				continue
			var slot: Dictionary = slot_val
			if str(slot.get("employee_id", "")).is_empty():
				structure[i_empty] = {"employee_id": m_id, "reports": []}
				used_counts[m_id] = used_m + 1
				placed = true
				break

		if placed:
			continue

		var replace_index := -1
		var replaced_emp := ""
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
				replaced_emp = direct2
				break

		if replace_index < 0:
			break

		structure[replace_index] = {"employee_id": m_id, "reports": []}
		used_counts[m_id] = used_m + 1
		if not replaced_emp.is_empty():
			var prev_used: int = int(used_counts.get(replaced_emp, 0))
			if prev_used > 0:
				used_counts[replaced_emp] = prev_used - 1

	# 3) 补齐剩余空槽：放入普通员工
	for emp_nm in non_managers:
		var emp_id: String = str(emp_nm)
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		var avail_nm: int = int(available_counts.get(emp_id, 0))
		if avail_nm <= 0:
			continue
		var used_nm: int = int(used_counts.get(emp_id, 0))
		if used_nm >= avail_nm:
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
		structure[empty_index] = {"employee_id": emp_id, "reports": []}
		used_counts[emp_id] = used_nm + 1

	# 4) 分配剩余普通员工到经理卡槽
	var remaining_non_managers: Array[String] = []

	# 4.1) 优先放入“手动分配”的下属（按 slot_index 匹配）
	for s_i in range(structure.size()):
		var slot_val4 = structure[s_i]
		if not (slot_val4 is Dictionary):
			continue
		var slot4: Dictionary = slot_val4
		var direct: String = str(slot4.get("employee_id", ""))
		if direct.is_empty():
			continue
		var direct_def := _get_employee_def(direct)
		var cap := maxi(0, int(direct_def.get("manager_slots", 0)))
		if cap <= 0:
			continue

		var reps: Array[String] = []
		var pref_val = preferred_reports_by_slot.get(s_i, null)
		if pref_val is Array:
			var pref: Array = pref_val
			for p_i in range(pref.size()):
				var rep_val = pref[p_i]
				if not (rep_val is String):
					continue
				var rep_id: String = str(rep_val)
				if rep_id.is_empty() or rep_id == "ceo":
					continue
				var avail_rep: int = int(available_counts.get(rep_id, 0))
				if avail_rep <= 0:
					continue
				var rep_def := _get_employee_def(rep_id)
				if maxi(0, int(rep_def.get("manager_slots", 0))) > 0:
					continue
				var used_rep: int = int(used_counts.get(rep_id, 0))
				if used_rep >= avail_rep:
					continue
				reps.append(rep_id)
				used_counts[rep_id] = used_rep + 1
				if reps.size() >= cap:
					break
		slot4["reports"] = reps
		structure[s_i] = slot4

	# 4.2) 自动补齐剩余普通员工到经理卡槽（保序，允许同类型重复）
	var remaining_count_by_id: Dictionary = {}
	for emp_nm2 in non_managers:
		var emp_id2: String = str(emp_nm2)
		if emp_id2.is_empty() or emp_id2 == "ceo":
			continue
		if remaining_count_by_id.has(emp_id2):
			continue
		var avail2: int = int(available_counts.get(emp_id2, 0))
		var used2: int = int(used_counts.get(emp_id2, 0))
		remaining_count_by_id[emp_id2] = maxi(0, avail2 - used2)

	for emp_nm3 in non_managers:
		var emp_id3: String = str(emp_nm3)
		if emp_id3.is_empty() or emp_id3 == "ceo":
			continue
		var rem_val = remaining_count_by_id.get(emp_id3, 0)
		var rem: int = int(rem_val)
		if rem <= 0:
			continue
		remaining_non_managers.append(emp_id3)
		remaining_count_by_id[emp_id3] = rem - 1

	var nm_index := 0
	for s_i2 in range(structure.size()):
		var slot_val5 = structure[s_i2]
		if not (slot_val5 is Dictionary):
			continue
		var slot5: Dictionary = slot_val5
		var direct2: String = str(slot5.get("employee_id", ""))
		if direct2.is_empty():
			continue
		var direct_def2 := _get_employee_def(direct2)
		var cap2 := maxi(0, int(direct_def2.get("manager_slots", 0)))
		if cap2 <= 0:
			continue
		var reps_val2 = slot5.get("reports", [])
		var reps2: Array[String] = reps_val2 if reps_val2 is Array else []
		while reps2.size() < cap2 and nm_index < remaining_non_managers.size():
			reps2.append(remaining_non_managers[nm_index])
			nm_index += 1
		slot5["reports"] = reps2
		structure[s_i2] = slot5

	return structure

func _update_display() -> void:
	var total := _count_total_slots()
	var used := _count_used_slots()

	if slot_count_label != null:
		slot_count_label.text = "卡槽: %d/%d" % [used + 1, total + 1]

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

func _update_card_drag_enabled() -> void:
	for card_val in _direct_cards_by_slot:
		if not (card_val is EmployeeCard):
			continue
		var card: EmployeeCard = card_val
		if not is_instance_valid(card):
			continue
		var emp_id := str(card.employee_id)
		card.draggable = _drag_enabled and emp_id != "ceo"

	for card_val2 in _report_cards:
		if not (card_val2 is EmployeeCard):
			continue
		var card2: EmployeeCard = card_val2
		if not is_instance_valid(card2):
			continue
		var emp_id2 := str(card2.employee_id)
		card2.draggable = _drag_enabled and emp_id2 != "ceo"

func _on_direct_card_drag_started(employee_id: String, source_card: EmployeeCard) -> void:
	if not _drag_enabled:
		return
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty() or emp_id == "ceo":
		return
	_start_drag_visuals(emp_id, source_card)

func _on_direct_card_drag_ended(employee_id: String, drop_position: Vector2, _source_card: EmployeeCard) -> void:
	if not _drag_enabled:
		_end_drag_visuals()
		return
	var emp_id := str(employee_id).strip_edges()
	if emp_id.is_empty() or emp_id == "ceo":
		_end_drag_visuals()
		return

	var target := _find_drop_target(drop_position)
	_end_drag_visuals()
	if target != null:
		card_dropped.emit(emp_id, target)

func _start_drag_visuals(employee_id: String, source: EmployeeCard) -> void:
	if employee_id.is_empty():
		return
	if not is_instance_valid(source):
		return

	_end_drag_visuals()

	_dragging_employee_id = employee_id
	_drag_source_card = source
	_drag_source_modulate = source.modulate
	source.modulate = Color(1, 1, 1, 0.5)

	var size_guess := source.size
	if size_guess == Vector2.ZERO:
		size_guess = source.get_combined_minimum_size()
	if size_guess == Vector2.ZERO:
		size_guess = source.custom_minimum_size
	if size_guess == Vector2.ZERO:
		size_guess = Vector2(120, 80)
	_drag_preview_offset = size_guess / 2.0

	_ensure_drag_layer()
	if _drag_layer == null:
		return

	var preview := EmployeeCardClass.new()
	preview.employee_id = employee_id
	preview.draggable = false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = size_guess
	preview.size = size_guess
	preview.scale = Vector2(1.05, 1.05)
	preview.modulate = Color(1, 1, 1, 0.85)

	var emp_def := _get_employee_def(employee_id)
	if not emp_def.is_empty():
		preview.setup(emp_def)

	_drag_layer.add_child(preview)
	_drag_preview = preview

	var viewport := get_viewport()
	if viewport != null:
		_drag_preview.position = viewport.get_mouse_position() - _drag_preview_offset
	set_process(true)

func _process(_delta: float) -> void:
	if _drag_preview == null or not is_instance_valid(_drag_preview):
		set_process(false)
		return

	var viewport := get_viewport()
	if viewport == null:
		set_process(false)
		return
	var mouse_pos := viewport.get_mouse_position()
	_drag_preview.position = mouse_pos - _drag_preview_offset

	var target := _find_drop_target(mouse_pos)
	_set_hover_drop_target(target)

func _end_drag_visuals() -> void:
	_set_hover_drop_target(null)

	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null

	if _drag_source_card != null and is_instance_valid(_drag_source_card):
		_drag_source_card.modulate = _drag_source_modulate
	_drag_source_card = null
	_drag_source_modulate = Color(1, 1, 1, 1)
	_dragging_employee_id = ""
	_drag_preview_offset = Vector2.ZERO
	set_process(false)

func _ensure_drag_layer() -> void:
	if _drag_layer != null and is_instance_valid(_drag_layer):
		return

	_drag_layer = CanvasLayer.new()
	_drag_layer.layer = 101
	add_child(_drag_layer)

func _find_drop_target(global_pos: Vector2) -> Control:
	var viewport := get_viewport()
	if viewport == null:
		return null

	var hovered := viewport.gui_get_hovered_control() if viewport.has_method("gui_get_hovered_control") else null
	var cur: Node = hovered
	while cur != null:
		if cur is Control and cur.is_in_group("employee_card_drop_target"):
			return cur as Control
		cur = cur.get_parent()

	# 兜底：遍历 group（避免 hovered 被鼠标过滤影响）
	var best: Control = null
	var best_area := INF
	for n in get_tree().get_nodes_in_group("employee_card_drop_target"):
		if not (n is Control):
			continue
		var c: Control = n
		if not c.visible:
			continue
		var rect := c.get_global_rect()
		if rect.has_point(global_pos):
			var area := rect.size.x * rect.size.y
			if area < best_area:
				best_area = area
				best = c

	return best

func _set_hover_drop_target(target: Control) -> void:
	if _hover_drop_target == target:
		return

	if _hover_drop_target != null and is_instance_valid(_hover_drop_target):
		if _hover_drop_target.has_method("set_drop_highlighted"):
			_hover_drop_target.call("set_drop_highlighted", false)

	_hover_drop_target = target

	if _hover_drop_target != null and is_instance_valid(_hover_drop_target):
		if _hover_drop_target.has_method("set_drop_highlighted"):
			_hover_drop_target.call("set_drop_highlighted", true)


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
