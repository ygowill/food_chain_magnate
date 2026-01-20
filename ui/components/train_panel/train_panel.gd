# 培训面板组件
# 显示可培训员工（来源）并选择培训目标
class_name TrainPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal train_requested(from_employee: String, to_employee: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

@onready var counter_label: Label = $MarginContainer/VBoxContainer/CounterRow/CounterLabel
@onready var trainable_section_label: Label = $MarginContainer/VBoxContainer/TrainableSection/SectionLabel
@onready var trainable_container: HFlowContainer = $MarginContainer/VBoxContainer/TrainableSection/TrainableContainer
@onready var path_container: HFlowContainer = $MarginContainer/VBoxContainer/PathSection/ScrollContainer/PathContainer
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ConfirmButton

var _employee_pool: Dictionary = {}  # employee_type -> count
var _employee_registry = null
var _trainable_sources: Dictionary = {}  # employee_type -> count
var _trainable_order: Array[String] = []
var _train_remaining: int = 0
var _train_total: int = 0
var _max_steps_one_employee: int = 1

var _selected_source: String = ""
var _selected_target: String = ""
var _selected_steps_required: int = 0

var _requires_same_color_by_source: Dictionary = {}  # employee_type -> bool
var _badge_text_by_source: Dictionary = {}  # employee_type -> String (e.g. "预支")
var _selected_requires_same_color: bool = false
var _steps_by_target: Dictionary = {}  # target_type -> steps_required

func _get_confirm_button() -> Button:
	return confirm_btn

func _apply_embedding(embedded: bool) -> void:
	# TrainPanel 的确认按钮不在 ButtonRow 内：嵌入 RightPanel 后由右侧 footer 承担确认动作。
	if confirm_btn != null:
		confirm_btn.visible = not embedded

func _get_relayout_delay_frames() -> int:
	# HFlowContainer(选卡) 在首次嵌入/首次显示时可能未拿到稳定宽度导致不换行。
	return 2

func _on_panel_ready() -> void:
	if trainable_container != null and is_instance_valid(trainable_container):
		if trainable_container.has_signal("employee_selected"):
			trainable_container.employee_selected.connect(_on_source_selected)
	if path_container != null and is_instance_valid(path_container):
		if path_container.has_signal("employee_selected"):
			path_container.employee_selected.connect(_on_target_selected)

func _on_relayout() -> void:
	if trainable_container != null and is_instance_valid(trainable_container):
		trainable_container.queue_sort()
	if path_container != null and is_instance_valid(path_container):
		path_container.queue_sort()

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_employee_pool(pool: Dictionary) -> void:
	_employee_pool = pool.duplicate(true)
	_update_states()

func set_trainable_employees(employees: Array[String]) -> void:
	var sources := {}
	for v in employees:
		var emp_type := str(v)
		if emp_type.is_empty():
			continue
		sources[emp_type] = int(sources.get(emp_type, 0)) + 1
	set_trainable_sources(sources)

func set_trainable_sources(sources: Dictionary, section_label_text: String = "") -> void:
	_trainable_sources.clear()
	_trainable_order.clear()

	for k in sources.keys():
		if not (k is String):
			continue
		var emp_type: String = str(k)
		if emp_type.is_empty():
			continue
		var count_val = sources.get(k, 0)
		var count := 0
		if count_val is int:
			count = int(count_val)
		elif count_val is float:
			var f: float = float(count_val)
			if f == int(f):
				count = int(f)
		if count <= 0:
			continue
		_trainable_sources[emp_type] = count
		_trainable_order.append(emp_type)

	_trainable_order.sort()
	if trainable_section_label != null and not section_label_text.is_empty():
		trainable_section_label.text = section_label_text
	_update_states()

func set_source_requires_same_color(map: Dictionary) -> void:
	_requires_same_color_by_source = map.duplicate(true)
	_update_states()

func set_source_badges(map: Dictionary) -> void:
	_badge_text_by_source = map.duplicate(true)
	_update_states()

func set_train_count(remaining: int, total: int) -> void:
	_train_remaining = remaining
	_train_total = total
	_update_counter()
	_update_states()

func set_max_steps_one_employee(max_steps: int) -> void:
	_max_steps_one_employee = maxi(0, max_steps)
	_update_states()

func refresh() -> void:
	_update_counter()
	_update_states()
	_request_relayout()

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

func _update_states() -> void:
	var can_train := _train_remaining > 0

	# 若剩余次数为 0，则清空选择，避免出现“已选但无法确认”的误导。
	if not can_train:
		_clear_selection(true)

	_refresh_trainable_picker()
	_refresh_target_picker()

	if confirm_btn != null:
		var ok := can_train and not _selected_source.is_empty() and not _selected_target.is_empty()
		ok = ok and _selected_steps_required > 0 and _selected_steps_required <= _train_remaining
		confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func _refresh_trainable_picker() -> void:
	if trainable_container == null:
		return

	var can_train := _train_remaining > 0

	# 若来源不再可用（例如模式切换/数量变更），清空选择与路径。
	if not _selected_source.is_empty() and not _trainable_sources.has(_selected_source):
		_clear_selection(true)

	var items: Array[Dictionary] = []
	for emp_type in _trainable_order:
		var emp_def := _get_employee_def(emp_type)
		var count: int = int(_trainable_sources.get(emp_type, 1))

		var tag_text := str(_badge_text_by_source.get(emp_type, "")).strip_edges()
		if tag_text.is_empty() and bool(_requires_same_color_by_source.get(emp_type, false)):
			tag_text = "在岗"

		items.append({
			"id": emp_type,
			"employee_def": emp_def,
			"badge_text": str(count), # 数量角标
			"tag_text": tag_text,
			"enabled": can_train and count > 0,
		})

	if trainable_container.has_method("set_items"):
		trainable_container.set_items(items, _selected_source)
	_request_relayout()

func _refresh_target_picker() -> void:
	if path_container == null:
		return

	_recompute_steps_by_target()

	# 无来源时：清空并提示
	if _selected_source.is_empty():
		if path_container.has_method("clear"):
			path_container.clear()
		var label := Label.new()
		label.text = "请选择培训来源"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		path_container.add_child(label)
		_selected_target = ""
		_selected_steps_required = 0
		return

	if _steps_by_target.is_empty():
		if path_container.has_method("clear"):
			path_container.clear()
		var label2 := Label.new()
		label2.text = "无可培训目标"
		label2.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		path_container.add_child(label2)
		_selected_target = ""
		_selected_steps_required = 0
		return

	# 校验当前目标是否仍可用
	if not _selected_target.is_empty():
		var steps_required: int = int(_steps_by_target.get(_selected_target, 0))
		var pool_count: int = int(_employee_pool.get(_selected_target, 0))
		if steps_required <= 0 or steps_required > _train_remaining or pool_count <= 0:
			_selected_target = ""
			_selected_steps_required = 0

	# 创建培训目标列表（按步数、再按 id 排序）
	var targets: Array[String] = []
	for k in _steps_by_target.keys():
		if not (k is String):
			continue
		var tid := str(k)
		if tid.is_empty():
			continue
		targets.append(tid)
	targets.sort_custom(func(a: String, b: String) -> bool:
		var sa := int(_steps_by_target.get(a, 0))
		var sb := int(_steps_by_target.get(b, 0))
		if sa != sb:
			return sa < sb
		return a < b
	)

	var items: Array[Dictionary] = []
	for target_type in targets:
		var target_def := _get_employee_def(target_type)
		var pool_count: int = int(_employee_pool.get(target_type, 0))
		var steps_required: int = int(_steps_by_target.get(target_type, 1))
		var enabled := _train_remaining > 0 and pool_count > 0 and steps_required > 0 and steps_required <= _train_remaining

		items.append({
			"id": target_type,
			"employee_def": target_def,
			"badge_text": str(pool_count), # 数量角标（库存）
			"tag_text": "%d步" % steps_required,
			"enabled": enabled,
		})

	if path_container.has_method("set_items"):
		path_container.set_items(items, _selected_target)

	_selected_steps_required = int(_steps_by_target.get(_selected_target, 0)) if not _selected_target.is_empty() else 0
	_request_relayout()

func _recompute_steps_by_target() -> void:
	_steps_by_target.clear()

	if _selected_source.is_empty():
		return

	var emp_def := _get_employee_def(_selected_source)
	var from_role := str(emp_def.get("role", ""))
	var max_steps := maxi(0, _max_steps_one_employee)

	# BFS：计算在 max_steps 内可达的最终目标（最短步数）
	var visited := {}
	visited[_selected_source] = 0
	var queue: Array[String] = [_selected_source]
	var qi := 0

	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var dist := int(visited.get(cur, 0))
		if dist >= max_steps:
			continue

		var cur_def := _get_employee_def(cur)
		var cur_train_to: Array = Array(cur_def.get("train_to", []))
		for nxt_val in cur_train_to:
			var nxt := str(nxt_val)
			if nxt.is_empty():
				continue
			if visited.has(nxt):
				continue
			var ndist := dist + 1
			if ndist > max_steps:
				continue

			# 在岗同色培训：路径中的每一步都保持同色
			if _selected_requires_same_color and not from_role.is_empty():
				var nxt_def := _get_employee_def(nxt)
				var to_role := str(nxt_def.get("role", ""))
				if not to_role.is_empty() and to_role != from_role:
					continue

			visited[nxt] = ndist
			queue.append(nxt)

			# 记录为可选目标（最短步数）
			if not _steps_by_target.has(nxt):
				_steps_by_target[nxt] = ndist

func _on_source_selected(employee_type: String) -> void:
	_selected_source = str(employee_type).strip_edges()
	_selected_target = ""
	_selected_steps_required = 0
	_selected_requires_same_color = bool(_requires_same_color_by_source.get(_selected_source, false))

	_update_states()

func _on_target_selected(target_type: String) -> void:
	_selected_target = str(target_type).strip_edges()
	_update_states()

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_source.is_empty() or _selected_target.is_empty():
		return
	if _train_remaining <= 0:
		return
	if _selected_steps_required <= 0 or _selected_steps_required > _train_remaining:
		return

	train_requested.emit(_selected_source, _selected_target)
	_clear_selection(true)
	_update_states()

func _clear_selection(clear_source: bool) -> void:
	if clear_source:
		_selected_source = ""
	_selected_target = ""
	_selected_steps_required = 0
	_steps_by_target.clear()
	if clear_source:
		_selected_requires_same_color = false
