# 招聘面板组件
# 显示可招聘的入门级员工，支持招聘操作
class_name RecruitPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal recruit_requested(employee_type: String)
signal cancelled()

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var counter_label: Label = $MarginContainer/VBoxContainer/CounterRow/CounterLabel
@onready var items_container: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ItemsContainer
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton

var _employee_pool: Dictionary = {}  # employee_type -> count
var _employee_registry = null
var _recruit_remaining: int = 0
var _recruit_total: int = 0
var _selected_employee_type: String = ""

func _get_confirm_button() -> Button:
	return confirm_btn

func _get_cancel_button() -> Button:
	return cancel_btn

func _get_relayout_delay_frames() -> int:
	# HFlowContainer 在首次嵌入 RightPanel/首次显示时，可能在 size 还未稳定时完成布局；
	# 延迟到布局稳定后强制重排一次。
	return 2

func _on_relayout() -> void:
	if items_container != null and is_instance_valid(items_container):
		items_container.queue_sort()

func _on_panel_ready() -> void:
	UiStylesClass.apply_button_primary(confirm_btn)
	UiStylesClass.apply_button_secondary(cancel_btn)
	if items_container != null and is_instance_valid(items_container):
		if items_container.has_signal("employee_selected"):
			items_container.employee_selected.connect(_on_card_selected)

func set_employee_registry(registry) -> void:
	_employee_registry = registry
	_refresh_picker()

func set_employee_pool(pool: Dictionary) -> void:
	_employee_pool = pool.duplicate()
	_refresh_picker()
	_update_confirm_state()
	_request_relayout()

func set_recruit_count(remaining: int, total: int) -> void:
	_recruit_remaining = remaining
	_recruit_total = total
	_update_counter()
	_refresh_picker()
	_update_confirm_state()

func refresh() -> void:
	_refresh_picker()
	_update_counter()
	_update_confirm_state()
	_request_relayout()

func clear_selection() -> void:
	_selected_employee_type = ""
	_refresh_picker()
	_update_confirm_state()

func _refresh_picker() -> void:
	if items_container == null:
		return

	# 获取入门级员工列表
	var entry_level_ids := _get_entry_level_employee_ids()

	var can_recruit := _recruit_remaining > 0
	if not can_recruit:
		_selected_employee_type = ""
	elif not _selected_employee_type.is_empty():
		var selected_count: int = int(_employee_pool.get(_selected_employee_type, 0))
		if selected_count <= 0:
			_selected_employee_type = ""

	var items: Array[Dictionary] = []
	for emp_type in entry_level_ids:
		var count: int = int(_employee_pool.get(emp_type, 0))
		var emp_def := _get_employee_def(emp_type)
		items.append({
			"id": emp_type,
			"employee_def": emp_def,
			"badge_text": str(count),
			"enabled": can_recruit and count > 0,
		})

	if items_container.has_method("set_items"):
		items_container.set_items(items, _selected_employee_type)
	else:
		# 兜底：脚本缺失时仍能显示基础卡，避免 UI 空白。
		UiRebuildHelpersClass.free_children(items_container)
		for item in items:
			var emp_id := str(item.get("id", ""))
			var c := EmployeeCardClass.new()
			c.variant = EmployeeCard.CardVariant.COMPACT
			c.draggable = false
			c.employee_id = emp_id
			var d_val = item.get("employee_def", {})
			if d_val is Dictionary:
				c.setup(Dictionary(d_val))
			items_container.add_child(c)

	right_panel_footer_changed.emit()
	_request_relayout()

func _get_entry_level_employee_ids() -> Array[String]:
	var result: Array[String] = []

	# 优先：使用静态 EmployeeRegistry（模块系统 V2 在初始化时配置）
	if EmployeeRegistryClass.is_loaded():
		for key in _employee_pool.keys():
			var emp_type := str(key)
			var emp_def := _get_employee_def(emp_type)
			var tags: Array = Array(emp_def.get("tags", []))
			if tags.has("entry_level"):
				result.append(emp_type)
	elif _employee_registry != null and _employee_registry.has_method("get_all_employee_ids"):
		# 兼容：旧式注入 registry
		var all_ids: Array = _employee_registry.get_all_employee_ids()
		for id in all_ids:
			var emp_def2 := _get_employee_def(str(id))
			var tags2: Array = Array(emp_def2.get("tags", []))
			if tags2.has("entry_level"):
				result.append(str(id))
	else:
		# 兜底：从 pool 中推断（pool 中的都是可招聘的）
		for key2 in _employee_pool.keys():
			result.append(str(key2))

	result.sort()
	return result

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
		counter_label.text = "招聘次数: %d / %d" % [_recruit_remaining, _recruit_total]

func _on_card_selected(employee_type: String) -> void:
	_selected_employee_type = employee_type
	_refresh_picker()
	_update_confirm_state()

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return

	var ok := true
	ok = ok and _recruit_remaining > 0
	ok = ok and not _selected_employee_type.is_empty()
	if ok:
		var selected_count: int = int(_employee_pool.get(_selected_employee_type, 0))
		ok = ok and selected_count > 0

	confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_employee_type.is_empty():
		return

	var emp_type := _selected_employee_type
	clear_selection()
	recruit_requested.emit(emp_type)

func _on_cancel_pressed() -> void:
	clear_selection()
	cancelled.emit()
