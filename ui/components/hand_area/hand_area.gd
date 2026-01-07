# 员工手牌区组件
# 显示玩家拥有的所有员工卡（在岗 + 待命 + 忙碌营销员）
class_name HandArea
extends Control

signal cards_selected(employee_ids: Array[String])
signal card_dropped(employee_id: String, target: Control)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var active_container: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ActiveSection/ActiveContainer
@onready var reserve_container: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ReserveSection/ReserveContainer
@onready var busy_container: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BusySection/BusyContainer

@onready var active_section: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ActiveSection
@onready var reserve_section: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ReserveSection
@onready var busy_section: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BusySection

var _employee_registry = null  # EmployeeRegistry 引用
var _active_employees: Array[String] = []
var _reserve_employees: Array[String] = []
var _busy_marketers: Array[String] = []

var _selected_ids: Array[String] = []
var _cards: Dictionary = {}  # employee_id -> EmployeeCard

var _multi_select: bool = false  # 是否支持多选

func _ready() -> void:
	pass

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_multi_select(enabled: bool) -> void:
	_multi_select = enabled

func set_employees(employees: Array[String], reserve: Array[String], busy_marketers: Array[String]) -> void:
	_active_employees = employees.duplicate()
	_reserve_employees = reserve.duplicate()
	_busy_marketers = busy_marketers.duplicate()
	_rebuild_cards()

func get_selected_employees() -> Array[String]:
	return _selected_ids.duplicate()

func clear_selection() -> void:
	_selected_ids.clear()
	_update_selection_display()

func _rebuild_cards() -> void:
	# 清除旧卡牌
	for card in _cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()

	# 创建在岗员工卡牌
	_build_cards_for_container(_active_employees, active_container, false)

	# 创建待命区员工卡牌
	_build_cards_for_container(_reserve_employees, reserve_container, false)

	# 创建忙碌营销员卡牌
	_build_cards_for_container(_busy_marketers, busy_container, true)

	# 更新区域可见性
	if active_section != null:
		active_section.visible = not _active_employees.is_empty()
	if reserve_section != null:
		reserve_section.visible = not _reserve_employees.is_empty()
	if busy_section != null:
		busy_section.visible = not _busy_marketers.is_empty()

func _build_cards_for_container(employee_ids: Array[String], container: Control, is_busy: bool) -> void:
	if container == null:
		return

	for emp_id in employee_ids:
		var card := EmployeeCardClass.new()
		card.employee_id = emp_id
		card.draggable = not is_busy

		# 获取员工定义
		var emp_def := _get_employee_def(emp_id)
		if not emp_def.is_empty():
			card.setup(emp_def)

		if is_busy:
			card.set_busy(true)

		card.card_clicked.connect(_on_card_clicked)
		card.card_drag_started.connect(_on_card_drag_started)
		card.card_drag_ended.connect(_on_card_drag_ended)

		container.add_child(card)
		_cards[emp_id] = card

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

func _on_card_clicked(employee_id: String) -> void:
	if _multi_select:
		if _selected_ids.has(employee_id):
			_selected_ids.erase(employee_id)
		else:
			_selected_ids.append(employee_id)
	else:
		if _selected_ids.has(employee_id):
			_selected_ids.clear()
		else:
			_selected_ids = [employee_id]

	_update_selection_display()
	cards_selected.emit(_selected_ids.duplicate())

func _on_card_drag_started(employee_id: String) -> void:
	# TODO: 实现拖拽视觉效果
	pass

func _on_card_drag_ended(employee_id: String, drop_position: Vector2) -> void:
	# 检测放置目标
	var target := _find_drop_target(drop_position)
	if target != null:
		card_dropped.emit(employee_id, target)

func _find_drop_target(global_pos: Vector2) -> Control:
	# 查找放置目标（公司结构面板等）
	# TODO: 实现放置目标检测
	return null

func _update_selection_display() -> void:
	for emp_id in _cards.keys():
		var card: EmployeeCard = _cards[emp_id]
		if is_instance_valid(card):
			card.set_selected(_selected_ids.has(emp_id))
