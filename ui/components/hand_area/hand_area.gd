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

var _drag_layer: CanvasLayer = null
var _drag_preview: EmployeeCard = null
var _dragging_employee_id: String = ""
var _drag_source_card: EmployeeCard = null
var _drag_source_modulate: Color = Color(1, 1, 1, 1)
var _drag_preview_offset: Vector2 = Vector2.ZERO
var _hover_drop_target: Control = null
var _drag_enabled: bool = true

func _ready() -> void:
	set_process(false)
	if active_container != null:
		active_container.add_to_group("employee_card_drop_target")
	if reserve_container != null:
		reserve_container.add_to_group("employee_card_drop_target")

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_drag_enabled(enabled: bool) -> void:
	if _drag_enabled == enabled:
		return
	_drag_enabled = enabled
	_rebuild_cards()

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
	_end_drag_visuals()

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
		card.draggable = (not is_busy) and _drag_enabled and emp_id != "ceo"

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
	_start_drag_visuals(employee_id)

func _on_card_drag_ended(employee_id: String, drop_position: Vector2) -> void:
	# 检测放置目标
	var target := _find_drop_target(drop_position)
	_end_drag_visuals()
	if target != null:
		card_dropped.emit(employee_id, target)

func _find_drop_target(global_pos: Vector2) -> Control:
	# 查找放置目标（公司结构面板等）
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

func _process(_delta: float) -> void:
	if _drag_preview == null or not is_instance_valid(_drag_preview):
		set_process(false)
		return

	var mouse_pos := get_viewport().get_mouse_position()
	_drag_preview.position = mouse_pos - _drag_preview_offset

	var target := _find_drop_target(mouse_pos)
	_set_hover_drop_target(target)

func _start_drag_visuals(employee_id: String) -> void:
	if employee_id.is_empty():
		return
	if not _cards.has(employee_id):
		return
	var source_val = _cards.get(employee_id, null)
	if not (source_val is EmployeeCard):
		return
	var source: EmployeeCard = source_val
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

	_drag_preview.position = get_viewport().get_mouse_position() - _drag_preview_offset
	set_process(true)

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
	_drag_layer.layer = 100
	add_child(_drag_layer)

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

func _update_selection_display() -> void:
	for emp_id in _cards.keys():
		var card: EmployeeCard = _cards[emp_id]
		if is_instance_valid(card):
			card.set_selected(_selected_ids.has(emp_id))
