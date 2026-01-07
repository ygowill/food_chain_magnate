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
var _ceo_card: EmployeeCard = null

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
	# 清除旧的卡槽
	for slot in _slot_nodes:
		if is_instance_valid(slot):
			slot.queue_free()
	_slot_nodes.clear()

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

	# 创建经理层卡槽
	if manager_container != null:
		for i in range(_ceo_slots):
			var slot := CardSlot.new()
			slot.slot_index = i
			slot.card_placed.connect(_on_card_placed)
			slot.card_removed.connect(_on_card_removed)
			manager_container.add_child(slot)
			_slot_nodes.append(slot)

	# 填充已有员工到卡槽
	_fill_existing_employees()

	# 更新显示
	_update_display()

func _fill_existing_employees() -> void:
	var employees: Array = Array(_player_data.get("employees", []))
	var slot_index := 0

	for emp_id in employees:
		var id: String = str(emp_id)
		if id == "ceo":
			continue

		if slot_index < _slot_nodes.size():
			var slot: CardSlot = _slot_nodes[slot_index]
			var emp_def := _get_employee_def(id)

			var card := EmployeeCardClass.new()
			card.employee_id = id
			if not emp_def.is_empty():
				card.setup(emp_def)
			else:
				card.setup({"id": id, "name": id})

			slot.place_card(card)
			slot_index += 1

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
	_update_structure()

func _on_card_removed(slot_index: int, employee_id: String) -> void:
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

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(130, 90)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
		style.border_color = Color(0.3, 0.3, 0.35, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

		# 空卡槽提示
		var hint := Label.new()
		hint.text = "空卡槽"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
		hint.name = "Hint"
		add_child(hint)

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
