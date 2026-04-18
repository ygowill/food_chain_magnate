# 培训面板组件
# 上方选择培训员实例，中间选择被培训员工实例，下方显示最终可达目标。
class_name TrainPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal train_requested(trainer_staff_id: int, source_staff_id: int, from_employee: String, to_employee: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var counter_label: Label = $MarginContainer/VBoxContainer/CounterRow/CounterLabel
@onready var trainer_section_label: Label = $MarginContainer/VBoxContainer/TrainerSection/SectionLabel
@onready var trainer_container: HFlowContainer = $MarginContainer/VBoxContainer/TrainerSection/TrainerContainer
@onready var source_section_label: Label = $MarginContainer/VBoxContainer/SourceSection/SectionLabel
@onready var source_container: HFlowContainer = $MarginContainer/VBoxContainer/SourceSection/SourceContainer
@onready var target_section_label: Label = $MarginContainer/VBoxContainer/TargetSection/SectionLabel
@onready var target_container: HFlowContainer = $MarginContainer/VBoxContainer/TargetSection/ScrollContainer/TargetContainer
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ConfirmButton

var _employee_pool: Dictionary = {}
var _employee_registry = null
var _train_remaining: int = 0
var _train_total: int = 0

var _trainer_items: Array[Dictionary] = []
var _trainer_by_key: Dictionary = {}
var _selected_trainer_key: String = ""
var _selected_trainer_staff_id: int = -1
var _selected_trainer_employee_type: String = ""
var _selected_trainer_remaining: int = 0

var _source_items: Array[Dictionary] = []
var _source_by_key: Dictionary = {}
var _selected_source_key: String = ""
var _selected_source_staff_id: int = -1
var _selected_source_employee_type: String = ""
var _selected_requires_same_color: bool = false

var _target_items: Array[Dictionary] = []
var _target_by_key: Dictionary = {}
var _selected_target_key: String = ""
var _selected_target_employee_type: String = ""
var _selected_steps_required: int = 0

func _get_confirm_button() -> Button:
	return confirm_btn

func _apply_embedding(embedded: bool) -> void:
	if confirm_btn != null:
		confirm_btn.visible = not embedded

func _get_relayout_delay_frames() -> int:
	return 2

func _on_panel_ready() -> void:
	UiStylesClass.apply_button_primary(confirm_btn)
	if trainer_container != null and trainer_container.has_signal("employee_selected"):
		trainer_container.employee_selected.connect(_on_trainer_selected)
	if source_container != null and source_container.has_signal("employee_selected"):
		source_container.employee_selected.connect(_on_source_selected)
	if target_container != null and target_container.has_signal("employee_selected"):
		target_container.employee_selected.connect(_on_target_selected)

func _on_relayout() -> void:
	if trainer_container != null and is_instance_valid(trainer_container):
		trainer_container.queue_sort()
	if source_container != null and is_instance_valid(source_container):
		source_container.queue_sort()
	if target_container != null and is_instance_valid(target_container):
		target_container.queue_sort()

func set_employee_registry(registry) -> void:
	_employee_registry = registry
	_refresh_all()

func set_employee_pool(pool: Dictionary) -> void:
	_employee_pool = pool.duplicate(true)
	_refresh_targets()
	_update_confirm_state()

func set_train_count(remaining: int, total: int) -> void:
	_train_remaining = remaining
	_train_total = total
	_update_counter()
	_refresh_trainers()
	_refresh_sources()
	_refresh_targets()
	_update_confirm_state()

func set_trainer_items(items: Array[Dictionary], section_label_text: String = "") -> void:
	_trainer_items = items.duplicate(true)
	if trainer_section_label != null and not section_label_text.is_empty():
		trainer_section_label.text = section_label_text
	_refresh_trainers()
	_refresh_sources()
	_refresh_targets()
	_update_confirm_state()

func set_source_items(items: Array[Dictionary], section_label_text: String = "") -> void:
	_source_items = items.duplicate(true)
	if source_section_label != null and not section_label_text.is_empty():
		source_section_label.text = section_label_text
	_refresh_sources()
	_refresh_targets()
	_update_confirm_state()

func set_target_items(items: Array[Dictionary], section_label_text: String = "") -> void:
	_target_items = items.duplicate(true)
	if target_section_label != null and not section_label_text.is_empty():
		target_section_label.text = section_label_text
	_refresh_targets()
	_update_confirm_state()

func get_selected_trainer_staff_id() -> int:
	return _selected_trainer_staff_id

func get_selected_source_staff_id() -> int:
	return _selected_source_staff_id

func get_selected_source_employee_type() -> String:
	return _selected_source_employee_type

func refresh() -> void:
	_update_counter()
	_refresh_all()
	_request_relayout()

func clear_selection() -> void:
	_selected_trainer_key = ""
	_selected_trainer_staff_id = -1
	_selected_trainer_employee_type = ""
	_selected_trainer_remaining = 0
	_selected_source_key = ""
	_selected_source_staff_id = -1
	_selected_source_employee_type = ""
	_selected_requires_same_color = false
	_selected_target_key = ""
	_selected_target_employee_type = ""
	_selected_steps_required = 0
	_refresh_all()
	_update_confirm_state()

func _refresh_all() -> void:
	_refresh_trainers()
	_refresh_sources()
	_refresh_targets()
	_update_confirm_state()

func _get_employee_def(employee_type: String) -> Dictionary:
	if _employee_registry != null and _employee_registry.has_method("get_employee"):
		var emp = _employee_registry.get_employee(employee_type)
		if emp != null and emp.has_method("to_dict"):
			return emp.to_dict()
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val != null and def_val.has_method("to_dict"):
			return def_val.to_dict()
	return {"id": employee_type, "name": employee_type}

func _update_counter() -> void:
	if counter_label != null:
		counter_label.text = "培训次数: %d / %d" % [_train_remaining, _train_total]

func _refresh_trainers() -> void:
	if trainer_container == null:
		return
	_trainer_by_key.clear()

	var items: Array[Dictionary] = []
	for item_val in _trainer_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var staff_id := int(item.get("staff_id", -1))
		var emp_type := str(item.get("employee_type", item.get("id", ""))).strip_edges()
		if staff_id <= 0 or emp_type.is_empty():
			continue
		var key := "staff:%d" % staff_id
		_trainer_by_key[key] = item.duplicate(true)
		items.append({
			"id": emp_type,
			"key": key,
			"employee_def": _get_employee_def(emp_type),
			"badge_text": "%d/%d" % [maxi(0, int(item.get("remaining", 0))), maxi(0, int(item.get("capacity", item.get("cap_per_instance", 0))))],
			"tag_text": "可用" if int(item.get("remaining", 0)) > 0 else "已用",
			"enabled": _train_remaining > 0 and int(item.get("remaining", 0)) > 0,
		})

	if not _selected_trainer_key.is_empty():
		var selected_info: Dictionary = Dictionary(_trainer_by_key.get(_selected_trainer_key, {}))
		if selected_info.is_empty() or int(selected_info.get("remaining", 0)) <= 0:
			_clear_trainer_selection()

	if trainer_container.has_method("set_items"):
		trainer_container.set_items(items, _selected_trainer_key)

func _refresh_sources() -> void:
	if source_container == null:
		return
	_source_by_key.clear()

	var items: Array[Dictionary] = []
	var can_choose := _train_remaining > 0 and _selected_trainer_staff_id > 0
	for item_val in _source_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var staff_id := int(item.get("staff_id", -1))
		var emp_type := str(item.get("employee_type", item.get("id", ""))).strip_edges()
		if emp_type.is_empty():
			continue
		var key := "staff:%d" % staff_id if staff_id > 0 else str(item.get("key", "%s#pending" % emp_type))
		_source_by_key[key] = item.duplicate(true)
		items.append({
			"id": emp_type,
			"key": key,
			"employee_def": _get_employee_def(emp_type),
			"badge_text": str(int(item.get("badge_count", 1))),
			"tag_text": str(item.get("tag_text", "")).strip_edges(),
			"enabled": can_choose and bool(item.get("enabled", true)),
		})

	if not _selected_source_key.is_empty():
		var selected_info: Dictionary = Dictionary(_source_by_key.get(_selected_source_key, {}))
		if selected_info.is_empty() or not can_choose:
			_clear_source_selection()

	if source_container.has_method("set_items"):
		source_container.set_items(items, _selected_source_key)

func _refresh_targets() -> void:
	if target_container == null:
		return
	_target_by_key.clear()

	var items: Array[Dictionary] = []
	var can_choose := _train_remaining > 0 and _selected_trainer_staff_id > 0 and _selected_source_staff_id != 0 and not _selected_source_employee_type.is_empty()
	for item_val in _target_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var emp_type := str(item.get("employee_type", item.get("id", ""))).strip_edges()
		if emp_type.is_empty():
			continue
		var key := str(item.get("key", emp_type)).strip_edges()
		if key.is_empty():
			key = emp_type
		_target_by_key[key] = item.duplicate(true)
		items.append({
			"id": emp_type,
			"key": key,
			"employee_def": _get_employee_def(emp_type),
			"badge_text": str(int(item.get("pool_count", _employee_pool.get(emp_type, 0)))),
			"tag_text": "%d步" % int(item.get("steps_required", 0)),
			"enabled": can_choose and bool(item.get("enabled", true)),
		})

	if not _selected_target_key.is_empty():
		var selected_info: Dictionary = Dictionary(_target_by_key.get(_selected_target_key, {}))
		if selected_info.is_empty() or not can_choose:
			_clear_target_selection()

	if target_container.has_method("set_items"):
		target_container.set_items(items, _selected_target_key)

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return
	var ok := true
	ok = ok and _train_remaining > 0
	ok = ok and _selected_trainer_staff_id > 0
	ok = ok and not _selected_source_employee_type.is_empty()
	ok = ok and not _selected_target_employee_type.is_empty()
	ok = ok and _selected_steps_required > 0
	ok = ok and _selected_steps_required <= _selected_trainer_remaining
	confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func _on_trainer_selected(_employee_type: String) -> void:
	var key := ""
	if trainer_container != null and trainer_container.has_method("get_selected_key"):
		key = str(trainer_container.get_selected_key()).strip_edges()
	var info: Dictionary = Dictionary(_trainer_by_key.get(key, {}))
	if info.is_empty():
		_clear_trainer_selection()
	else:
		_selected_trainer_key = key
		_selected_trainer_staff_id = int(info.get("staff_id", -1))
		_selected_trainer_employee_type = str(info.get("employee_type", info.get("id", ""))).strip_edges()
		_selected_trainer_remaining = int(info.get("remaining", 0))
	_clear_source_selection()
	_clear_target_selection()
	_update_confirm_state()

func _on_source_selected(employee_type: String) -> void:
	var key := ""
	if source_container != null and source_container.has_method("get_selected_key"):
		key = str(source_container.get_selected_key()).strip_edges()
	var info: Dictionary = Dictionary(_source_by_key.get(key, {}))
	if info.is_empty():
		_selected_source_key = ""
		_selected_source_staff_id = -1
		_selected_source_employee_type = str(employee_type).strip_edges()
		_selected_requires_same_color = false
	else:
		_selected_source_key = key
		_selected_source_staff_id = int(info.get("staff_id", -1))
		_selected_source_employee_type = str(info.get("employee_type", employee_type)).strip_edges()
		_selected_requires_same_color = bool(info.get("requires_same_color", false))
	_clear_target_selection()
	_update_confirm_state()

func _on_target_selected(employee_type: String) -> void:
	var key := ""
	if target_container != null and target_container.has_method("get_selected_key"):
		key = str(target_container.get_selected_key()).strip_edges()
	var info: Dictionary = Dictionary(_target_by_key.get(key, {}))
	_selected_target_key = key
	_selected_target_employee_type = str(employee_type).strip_edges()
	_selected_steps_required = int(info.get("steps_required", 0))
	_update_confirm_state()

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_trainer_staff_id <= 0 or _selected_source_employee_type.is_empty() or _selected_target_employee_type.is_empty():
		return
	train_requested.emit(_selected_trainer_staff_id, _selected_source_staff_id, _selected_source_employee_type, _selected_target_employee_type)
	_clear_source_selection()
	_clear_target_selection()
	_update_confirm_state()

func _clear_trainer_selection() -> void:
	_selected_trainer_key = ""
	_selected_trainer_staff_id = -1
	_selected_trainer_employee_type = ""
	_selected_trainer_remaining = 0

func _clear_source_selection() -> void:
	_selected_source_key = ""
	_selected_source_staff_id = -1
	_selected_source_employee_type = ""
	_selected_requires_same_color = false

func _clear_target_selection() -> void:
	_selected_target_key = ""
	_selected_target_employee_type = ""
	_selected_steps_required = 0
