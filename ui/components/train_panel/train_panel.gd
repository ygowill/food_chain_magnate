# 培训面板组件
# 显示待命区可培训员工，支持选择培训目标
class_name TrainPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal train_requested(from_employee: String, to_employee: String)

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")

@onready var counter_label: Label = $MarginContainer/VBoxContainer/CounterRow/CounterLabel
@onready var trainable_section_label: Label = $MarginContainer/VBoxContainer/TrainableSection/SectionLabel
@onready var trainable_container: HFlowContainer = $MarginContainer/VBoxContainer/TrainableSection/TrainableContainer
@onready var path_container: VBoxContainer = $MarginContainer/VBoxContainer/PathSection/ScrollContainer/PathContainer
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
var _trainable_cards: Dictionary = {}  # employee_type -> TrainableCard
var _requires_same_color_by_source: Dictionary = {}  # employee_type -> bool
var _badge_text_by_source: Dictionary = {}  # employee_type -> String
var _selected_requires_same_color: bool = false
var _steps_by_target: Dictionary = {}  # target_type -> steps_required

func _get_confirm_button() -> Button:
	return confirm_btn

func _apply_embedding(embedded: bool) -> void:
	# TrainPanel 的确认按钮不在 ButtonRow 内：嵌入 RightPanel 后由右侧 footer 承担确认动作。
	if confirm_btn != null:
		confirm_btn.visible = not embedded

func _get_relayout_delay_frames() -> int:
	# 训练源卡牌使用 HFlowContainer：在首次嵌入 RightPanel/首次显示时可能未拿到稳定宽度导致不换行。
	return 2

func _on_relayout() -> void:
	if trainable_container != null and is_instance_valid(trainable_container):
		trainable_container.queue_sort()

func set_employee_registry(registry) -> void:
	_employee_registry = registry

func set_employee_pool(pool: Dictionary) -> void:
	_employee_pool = pool.duplicate()

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
	_rebuild_trainable_list()

func set_source_requires_same_color(map: Dictionary) -> void:
	_requires_same_color_by_source = map.duplicate(true)

func set_source_badges(map: Dictionary) -> void:
	_badge_text_by_source = map.duplicate(true)

func set_train_count(remaining: int, total: int) -> void:
	_train_remaining = remaining
	_train_total = total
	_update_counter()
	_update_states()

func set_max_steps_one_employee(max_steps: int) -> void:
	_max_steps_one_employee = maxi(0, max_steps)
	# 若当前已选中来源，则重新构建可达目标列表（例如 coach/guru slot 被消耗后最大步数下降）
	if not _selected_source.is_empty():
		_show_train_path(_selected_source)

func refresh() -> void:
	_rebuild_trainable_list()
	_update_counter()

func _rebuild_trainable_list() -> void:
	# 清除旧卡牌
	UiRebuildHelpersClass.free_nodes_dict(_trainable_cards)

	if trainable_container == null:
		return

	for emp_type in _trainable_order:
		var emp_def := _get_employee_def(emp_type)
		var count: int = int(_trainable_sources.get(emp_type, 1))
		var requires_same_color := bool(_requires_same_color_by_source.get(emp_type, false))
		var badge_text := str(_badge_text_by_source.get(emp_type, ""))

		var card := TrainableCard.new()
		card.employee_type = emp_type
		card.employee_def = emp_def
		card.source_count = count
		card.badge_text = badge_text
		card.requires_same_color = requires_same_color
		card.card_clicked.connect(_on_trainable_clicked)
		trainable_container.add_child(card)
		_trainable_cards[emp_type] = card

	_clear_selection()

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

	for emp_type in _trainable_cards.keys():
		var card: TrainableCard = _trainable_cards[emp_type]
		if is_instance_valid(card):
			card.set_enabled(can_train)

	# TrainTargetItem 的“可选”状态也依赖剩余培训次数
	if path_container != null:
		for child in path_container.get_children():
			if child is TrainTargetItem:
				child.train_remaining = _train_remaining
				child.update_display()

	if confirm_btn != null:
		var ok := can_train and not _selected_source.is_empty() and not _selected_target.is_empty() and _selected_steps_required > 0 and _selected_steps_required <= _train_remaining
		confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func _on_trainable_clicked(employee_type: String) -> void:
	_selected_source = employee_type
	_selected_target = ""
	_selected_steps_required = 0
	_selected_requires_same_color = bool(_requires_same_color_by_source.get(employee_type, false))

	# 高亮选中
	for emp_type in _trainable_cards.keys():
		var card: TrainableCard = _trainable_cards[emp_type]
		if is_instance_valid(card):
			card.set_selected(emp_type == employee_type)

	_show_train_path(employee_type)
	_update_states()

func _show_train_path(employee_type: String) -> void:
	# 清除旧路径/选择
	if path_container != null:
		UiRebuildHelpersClass.free_children(path_container)

	if confirm_btn != null:
		confirm_btn.disabled = true
	right_panel_footer_changed.emit()
	_steps_by_target.clear()
	_selected_target = ""
	_selected_steps_required = 0

	var emp_def := _get_employee_def(employee_type)
	var from_role := str(emp_def.get("role", ""))
	var max_steps := maxi(0, _max_steps_one_employee)

	# BFS：计算在 max_steps 内可达的最终目标（最短步数）
	var visited := {}
	visited[employee_type] = 0
	var queue: Array[String] = [employee_type]
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

	if _steps_by_target.is_empty():
		var no_path_label := Label.new()
		no_path_label.text = "无可培训目标"
		no_path_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		path_container.add_child(no_path_label)
		return

	# 创建培训目标选项（按步数、再按 id 排序）
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

	for target_type in targets:
		var target_def := _get_employee_def(target_type)
		var pool_count: int = int(_employee_pool.get(target_type, 0))
		var steps_required: int = int(_steps_by_target.get(target_type, 1))

		var target_item := TrainTargetItem.new()
		target_item.target_type = target_type
		target_item.target_def = target_def
		target_item.pool_count = pool_count
		target_item.steps_required = steps_required
		target_item.train_remaining = _train_remaining
		target_item.target_selected.connect(_on_target_selected)
		path_container.add_child(target_item)

func _on_target_selected(target_type: String) -> void:
	_selected_target = target_type
	_selected_steps_required = int(_steps_by_target.get(target_type, 1))

	# 高亮选中的目标
	if path_container != null:
		for child in path_container.get_children():
			if child is TrainTargetItem:
				child.set_selected(child.target_type == target_type)

	_update_states()

func _on_confirm_pressed() -> void:
	if _selected_source.is_empty() or _selected_target.is_empty():
		return
	if _train_remaining <= 0:
		return
	if _selected_steps_required <= 0 or _selected_steps_required > _train_remaining:
		return

	train_requested.emit(_selected_source, _selected_target)
	_clear_selection()
	_update_states()

func _clear_selection() -> void:
	_selected_source = ""
	_selected_target = ""
	_selected_steps_required = 0
	_steps_by_target.clear()

	for card in _trainable_cards.values():
		if is_instance_valid(card):
			card.set_selected(false)

	UiRebuildHelpersClass.free_children(path_container)


# === 内部类：可培训员工卡牌 ===
class TrainableCard extends PanelContainer:
	signal card_clicked(employee_type: String)

	var employee_type: String = ""
	var employee_def: Dictionary = {}
	var source_count: int = 1
	var badge_text: String = ""
	var requires_same_color: bool = false

	var _enabled: bool = true
	var _selected: bool = false
	var _name_label: Label
	var _role_color: ColorRect
	var _count_label: Label
	var _badge_label: Label

	const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(100, 60)
		mouse_filter = Control.MOUSE_FILTER_STOP

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		add_child(vbox)

		# 顶部：角色颜色 + 名称
		var top_hbox := HBoxContainer.new()
		top_hbox.add_theme_constant_override("separation", 4)
		vbox.add_child(top_hbox)

		_role_color = ColorRect.new()
		_role_color.custom_minimum_size = Vector2(6, 20)
		top_hbox.add_child(_role_color)

		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 13)
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_hbox.add_child(_name_label)

		_count_label = Label.new()
		_count_label.add_theme_font_size_override("font_size", 12)
		_count_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 1))
		top_hbox.add_child(_count_label)

		_badge_label = Label.new()
		_badge_label.add_theme_font_size_override("font_size", 11)
		_badge_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6, 1))
		top_hbox.add_child(_badge_label)

		update_display()
		_update_style()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if _enabled:
					card_clicked.emit(employee_type)

	func update_display() -> void:
		if _name_label != null:
			var name: String = str(employee_def.get("name", employee_type))
			_name_label.text = name

		if _count_label != null:
			if source_count > 1:
				_count_label.text = "×%d" % source_count
				_count_label.visible = true
			else:
				_count_label.text = ""
				_count_label.visible = false

		if _badge_label != null:
			if not badge_text.is_empty():
				_badge_label.text = badge_text
				_badge_label.visible = true
			elif requires_same_color:
				_badge_label.text = "在岗"
				_badge_label.visible = true
			else:
				_badge_label.text = ""
				_badge_label.visible = false

		if _role_color != null:
			var role: String = str(employee_def.get("role", "special"))
			_role_color.color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))

	func set_enabled(enabled: bool) -> void:
		_enabled = enabled
		_update_style()

	func set_selected(selected: bool) -> void:
		_selected = selected
		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _selected:
			style.bg_color = Color(0.25, 0.35, 0.45, 0.95)
			style.border_color = Color(0.4, 0.6, 0.8, 1)
			style.set_border_width_all(2)
		elif _enabled:
			style.bg_color = Color(0.18, 0.2, 0.22, 0.9)
		else:
			style.bg_color = Color(0.15, 0.15, 0.18, 0.6)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)


# === 内部类：培训目标选项 ===
class TrainTargetItem extends PanelContainer:
	signal target_selected(target_type: String)

	var target_type: String = ""
	var target_def: Dictionary = {}
	var pool_count: int = 0
	var steps_required: int = 1
	var train_remaining: int = 0

	var _selected: bool = false
	var _name_label: Label
	var _count_label: Label
	var _select_btn: Button

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(200, 50)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		add_child(hbox)

		# 目标名称
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 14)
		_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(_name_label)

		# 库存数量
		_count_label = Label.new()
		_count_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(_count_label)

		# 选择按钮
		_select_btn = Button.new()
		_select_btn.text = "选择"
		_select_btn.add_theme_font_size_override("font_size", 12)
		_select_btn.pressed.connect(_on_select_pressed)
		hbox.add_child(_select_btn)

		update_display()
		_update_style()

	func update_display() -> void:
		if _name_label != null:
			var name: String = str(target_def.get("name", target_type))
			if steps_required > 1:
				_name_label.text = "→ (%d步) %s" % [steps_required, name]
			else:
				_name_label.text = "→ %s" % name

		if _count_label != null:
			_count_label.text = "库存: %d" % pool_count
			if pool_count <= 0:
				_count_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4, 1))
			else:
				_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))

		if _select_btn != null:
			_select_btn.disabled = pool_count <= 0 or steps_required <= 0 or steps_required > train_remaining

	func set_selected(selected: bool) -> void:
		_selected = selected
		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _selected:
			style.bg_color = Color(0.2, 0.3, 0.4, 0.9)
			style.border_color = Color(0.4, 0.6, 0.8, 1)
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(0.15, 0.17, 0.2, 0.8)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)

	func _on_select_pressed() -> void:
		if pool_count <= 0:
			return
		if steps_required <= 0 or steps_required > train_remaining:
			return
		target_selected.emit(target_type)
