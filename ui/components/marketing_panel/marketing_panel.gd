# 营销面板组件
# 发起营销：选择营销类型/员工/板件/产品/持续时间，并在地图上选点
class_name MarketingPanel
extends Control

signal marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int)
signal cancelled()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var type_container: HFlowContainer = $MarginContainer/VBoxContainer/TypeSection/TypeContainer
@onready var marketer_option: OptionButton = $MarginContainer/VBoxContainer/MarketerSection/MarketerOption
@onready var board_option: OptionButton = $MarginContainer/VBoxContainer/BoardSection/BoardOption
@onready var product_option: OptionButton = $MarginContainer/VBoxContainer/ProductSection/ProductOption
@onready var duration_spin: SpinBox = $MarginContainer/VBoxContainer/DurationSection/DurationSpin
@onready var target_label: Label = $MarginContainer/VBoxContainer/TargetSection/TargetLabel
@onready var range_info_label: Label = $MarginContainer/VBoxContainer/TargetSection/RangeInfoLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MarketingTypeButtonClass = preload("res://ui/components/marketing_panel/marketing_type_button.gd")

# 营销类型定义（用于 UI 文案与范围提示；具体可用性由外部传入）
const MARKETING_TYPES: Array[Dictionary] = [
	{"id": "billboard", "name": "广告牌", "icon": "B", "color": Color("#94c1c7"), "range": 2},
	{"id": "mailbox", "name": "邮箱营销", "icon": "M", "color": Color("#8fb5ba"), "range": 3},
	{"id": "airplane", "name": "飞机广告", "icon": "A", "color": Color("#7aa9af"), "range": 5},
	{"id": "radio", "name": "电台广告", "icon": "R", "color": Color("#659da5"), "range": 0},  # 全图
]

# 外部数据
var _available_marketers: Array[Dictionary] = []  # [{id, type, max_duration}]
var _available_boards_by_type: Dictionary = {}  # type_id -> Array[int]

# 当前选择
var _selected_type: String = ""
var _selected_target: Vector2i = Vector2i(-1, -1)
var _selected_employee_type: String = ""
var _selected_board_number: int = 0
var _selected_product: String = ""
var _selected_duration: int = 1

var _type_buttons: Dictionary = {}  # type_id -> marketing_type_button instance
var _marketer_max_duration_by_id: Dictionary = {}  # employee_type -> max_duration

var _map_callback: Callable  # 用于请求地图选择

func _ready() -> void:
	if confirm_btn != null:
		confirm_btn.pressed.connect(_on_confirm_pressed)
		confirm_btn.disabled = true
	if cancel_btn != null:
		cancel_btn.pressed.connect(_on_cancel_pressed)

	if marketer_option != null:
		marketer_option.item_selected.connect(_on_marketer_selected)
	if board_option != null:
		board_option.item_selected.connect(_on_board_selected)
	if product_option != null:
		product_option.item_selected.connect(_on_product_selected)
	if duration_spin != null:
		duration_spin.value_changed.connect(_on_duration_changed)

	_rebuild_product_options()
	_rebuild_type_buttons()
	_rebuild_marketer_options()
	_rebuild_board_options()
	_update_target_display()
	_update_confirm_state()

func set_available_marketers(marketers: Array[Dictionary]) -> void:
	_available_marketers = marketers.duplicate(true)
	_rebuild_type_buttons()
	_rebuild_marketer_options()
	_update_confirm_state()

func set_available_boards(boards_by_type: Dictionary) -> void:
	_available_boards_by_type = boards_by_type.duplicate(true)
	_rebuild_type_buttons()
	_rebuild_board_options()
	_update_confirm_state()

func set_map_selection_callback(callback: Callable) -> void:
	_map_callback = callback

func set_selected_target(position: Vector2i) -> void:
	_selected_target = position
	_update_target_display()
	_update_confirm_state()

func clear_selection() -> void:
	_selected_type = ""
	_selected_target = Vector2i(-1, -1)
	_selected_employee_type = ""
	_selected_board_number = 0
	_selected_duration = 1
	_marketer_max_duration_by_id.clear()

	for btn in _type_buttons.values():
		if is_instance_valid(btn):
			btn.set_selected(false)

	if marketer_option != null:
		marketer_option.clear()
		marketer_option.disabled = true

	if board_option != null:
		board_option.clear()
		board_option.disabled = true

	if duration_spin != null:
		duration_spin.min_value = 1
		duration_spin.max_value = 1
		duration_spin.value = 1

	_update_target_display()
	_update_confirm_state()

func _rebuild_type_buttons() -> void:
	for btn in _type_buttons.values():
		if is_instance_valid(btn):
			btn.queue_free()
	_type_buttons.clear()

	if type_container == null:
		return

	var marketers_by_type: Dictionary = {}
	for marketer in _available_marketers:
		var m_type: String = str(marketer.get("type", ""))
		if not marketers_by_type.has(m_type):
			marketers_by_type[m_type] = []
		marketers_by_type[m_type].append(marketer)

	for type_def in MARKETING_TYPES:
		var type_id: String = str(type_def.id)
		var marketer_count: int = Array(marketers_by_type.get(type_id, [])).size()
		var board_count: int = Array(_available_boards_by_type.get(type_id, [])).size()
		var is_available := marketer_count > 0 and board_count > 0

		var btn = MarketingTypeButtonClass.new()
		btn.type_id = type_id
		btn.type_def = type_def
		btn.is_available = is_available
		btn.marketer_count = marketer_count
		btn.board_count = board_count
		btn.type_selected.connect(_on_type_selected)
		type_container.add_child(btn)
		_type_buttons[type_id] = btn

func _on_type_selected(type_id: String) -> void:
	_selected_type = type_id
	_selected_target = Vector2i(-1, -1)
	_selected_employee_type = ""
	_selected_board_number = 0
	_selected_duration = 1

	for tid in _type_buttons.keys():
		var btn = _type_buttons[tid]
		if is_instance_valid(btn):
			btn.set_selected(tid == type_id)

	_rebuild_marketer_options()
	_rebuild_board_options()
	_update_target_display()
	_update_confirm_state()

	# 请求地图选择
	if _map_callback.is_valid():
		var range_val := _get_type_range(_selected_type)
		_map_callback.call(_selected_type, range_val)

func _rebuild_marketer_options() -> void:
	_selected_employee_type = ""
	_marketer_max_duration_by_id.clear()

	if marketer_option == null:
		return

	marketer_option.clear()

	if _selected_type.is_empty():
		marketer_option.disabled = true
		return

	var counts := {}
	for marketer in _available_marketers:
		if str(marketer.get("type", "")) != _selected_type:
			continue
		var emp_id: String = str(marketer.get("id", ""))
		if emp_id.is_empty():
			continue
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

		var md := int(marketer.get("max_duration", 1))
		if not _marketer_max_duration_by_id.has(emp_id):
			_marketer_max_duration_by_id[emp_id] = md
		else:
			_marketer_max_duration_by_id[emp_id] = maxi(int(_marketer_max_duration_by_id[emp_id]), md)

	var ids: Array[String] = []
	for k in counts.keys():
		ids.append(str(k))
	ids.sort()

	for emp_id in ids:
		var count: int = int(counts.get(emp_id, 0))
		var label := "%s ×%d" % [_get_employee_display_name(emp_id), count]
		marketer_option.add_item(label)
		var idx := marketer_option.get_item_count() - 1
		marketer_option.set_item_metadata(idx, emp_id)

	if marketer_option.get_item_count() > 0:
		marketer_option.disabled = false
		marketer_option.select(0)
		_apply_selected_marketer(0)
	else:
		marketer_option.disabled = true

func _apply_selected_marketer(index: int) -> void:
	if marketer_option == null:
		return
	if index < 0 or index >= marketer_option.get_item_count():
		return

	var meta = marketer_option.get_item_metadata(index)
	_selected_employee_type = str(meta)

	var max_duration := int(_marketer_max_duration_by_id.get(_selected_employee_type, 1))
	if max_duration <= 0:
		max_duration = 1

	if duration_spin != null:
		duration_spin.min_value = 1
		duration_spin.max_value = max_duration
		duration_spin.value = float(max_duration)

	_selected_duration = max_duration

func _rebuild_board_options() -> void:
	_selected_board_number = 0

	if board_option == null:
		return

	board_option.clear()

	if _selected_type.is_empty():
		board_option.disabled = true
		return

	var boards_any = _available_boards_by_type.get(_selected_type, [])
	var boards: Array[int] = []
	if boards_any is Array:
		for v in boards_any:
			if v is int:
				boards.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					boards.append(int(f))
	boards.sort()

	for bn in boards:
		board_option.add_item("#%d" % bn)
		var idx := board_option.get_item_count() - 1
		board_option.set_item_metadata(idx, bn)

	if board_option.get_item_count() > 0:
		board_option.disabled = false
		board_option.select(0)
		_apply_selected_board(0)
	else:
		board_option.disabled = true

func _apply_selected_board(index: int) -> void:
	if board_option == null:
		return
	if index < 0 or index >= board_option.get_item_count():
		return

	var meta = board_option.get_item_metadata(index)
	_selected_board_number = int(meta)

func _rebuild_product_options() -> void:
	_selected_product = ""

	if product_option == null:
		return

	product_option.clear()

	if not ProductRegistryClass.is_loaded():
		product_option.disabled = true
		return

	for pid in ProductRegistryClass.get_all_ids():
		var def_val = ProductRegistryClass.get_def(pid)
		if def_val != null and def_val.has_method("has_tag") and def_val.has_tag("no_marketing"):
			continue

		var name := pid
		if def_val != null and def_val.has_method("to_dict"):
			var d: Dictionary = def_val.to_dict()
			name = str(d.get("name", pid))
		elif def_val != null and def_val.has_method("is_drink"):
			# 兜底：ProductDef 有字段 name
			name = str(def_val.name)

		product_option.add_item(name)
		var idx := product_option.get_item_count() - 1
		product_option.set_item_metadata(idx, pid)

	if product_option.get_item_count() > 0:
		product_option.disabled = false
		product_option.select(0)
		var meta = product_option.get_item_metadata(0)
		_selected_product = str(meta)
	else:
		product_option.disabled = true

func _on_marketer_selected(index: int) -> void:
	_apply_selected_marketer(index)
	_update_confirm_state()

func _on_board_selected(index: int) -> void:
	_apply_selected_board(index)
	_update_confirm_state()

func _on_product_selected(index: int) -> void:
	if product_option == null:
		return
	var meta = product_option.get_item_metadata(index)
	_selected_product = str(meta)
	_update_confirm_state()

func _on_duration_changed(value: float) -> void:
	_selected_duration = int(value)
	_update_confirm_state()

func _get_employee_display_name(employee_type: String) -> String:
	if employee_type.is_empty():
		return ""
	if not EmployeeRegistryClass.is_loaded():
		return employee_type
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null:
		return employee_type
	if def_val.has_method("to_dict"):
		var d: Dictionary = def_val.to_dict()
		return str(d.get("name", employee_type))
	return employee_type

func _get_type_range(type_id: String) -> int:
	for type_def in MARKETING_TYPES:
		if str(type_def.id) == type_id:
			return int(type_def.get("range", 0))
	return 0

func _update_target_display() -> void:
	if target_label == null:
		return

	if _selected_type.is_empty():
		target_label.text = "请先选择营销类型"
		target_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	elif _selected_target == Vector2i(-1, -1):
		target_label.text = "请在地图上选择目标位置"
		target_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4, 1))
	else:
		target_label.text = "目标位置: (%d, %d)" % [_selected_target.x, _selected_target.y]
		target_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))

	if range_info_label != null:
		if _selected_type.is_empty():
			range_info_label.text = ""
		else:
			var range_val := _get_type_range(_selected_type)
			if range_val == 0:
				range_info_label.text = "范围: 全图"
			else:
				range_info_label.text = "范围: %d 格" % range_val

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return

	var ok := true
	ok = ok and not _selected_type.is_empty()
	ok = ok and not _selected_employee_type.is_empty()
	ok = ok and _selected_board_number > 0
	ok = ok and not _selected_product.is_empty()
	ok = ok and _selected_target != Vector2i(-1, -1)
	ok = ok and _selected_duration > 0

	confirm_btn.disabled = not ok

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return

	marketing_requested.emit(
		_selected_employee_type,
		_selected_board_number,
		_selected_target,
		_selected_product,
		_selected_duration
	)

func _on_cancel_pressed() -> void:
	cancelled.emit()
