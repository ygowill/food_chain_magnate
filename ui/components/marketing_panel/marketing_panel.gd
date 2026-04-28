# 营销面板组件
# 发起营销：选择营销类型/员工/板件/产品/持续时间，并在地图上选点
class_name MarketingPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int, rotation: int, axis: String, staff_id: int)
signal cancelled()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var type_container: Container = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TypeSection/TypeContainer
@onready var marketer_option: HFlowContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/MarketerSection/MarketerOption
@onready var board_flow: Container = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BoardSection/BoardFlow
@onready var product_flow: Container = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/ProductSection/ProductFlow
@onready var duration_flow: Container = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/DurationSection/DurationFlow
@onready var rotation_section: Control = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/RotationSection
@onready var rotate_left_btn: Button = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/RotationSection/RotationRow/RotationControls/RotateLeftButton
@onready var rotation_value_label: Label = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/RotationSection/RotationRow/RotationControls/RotationValueLabel
@onready var rotate_right_btn: Button = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/RotationSection/RotationRow/RotationControls/RotateRightButton
@onready var target_label: Label = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TargetSection/TargetLabel
@onready var range_info_label: Label = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TargetSection/RangeInfoLabel
@onready var error_label: Label = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TargetSection/ErrorLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MarketingBoardButtonClass = preload("res://ui/components/marketing_panel/marketing_board_button.gd")
const MarketingTypeButtonClass = preload("res://ui/components/marketing_panel/marketing_type_button.gd")
const MarketingPanelIconCacheClass = preload("res://ui/components/marketing_panel/marketing_panel_icon_cache.gd")
const MarketingPanelTypeSpecsBuilderClass = preload("res://ui/components/marketing_panel/marketing_panel_type_specs_builder.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

# 营销面板内的产品图标目标尺寸（方形，居中）。
const PRODUCT_ICON_SIZE := Vector2i(32, 32)
# 营销类型按钮中的图标（板件图）使用统一的方形尺寸，避免不同贴图尺寸导致布局/观感异常。
const MARKETING_TYPE_ICON_SIZE := Vector2i(36, 36)

# 营销类型定义（用于 UI 文案与范围提示；具体可用性由外部传入）
const MARKETING_TYPES: Array[Dictionary] = [
	{"id": "billboard", "name": "广告牌", "icon": "B", "color": Color("#94c1c7"), "range": 2},
	{"id": "mailbox", "name": "邮箱营销", "icon": "M", "color": Color("#8fb5ba"), "range": 3},
	{"id": "airplane", "name": "飞机广告", "icon": "A", "color": Color("#7aa9af"), "range": 5},
	{"id": "radio", "name": "电台广告", "icon": "R", "color": Color("#659da5"), "range": 0},  # 全图
]

# 模块营销 type 的 UI 名称兜底（若未在 MARKETING_TYPES 中声明）。
# 说明：营销 type 本身是数据驱动/模块可扩展的；UI 需要一个可读名称。
const MARKETING_TYPE_NAME_OVERRIDES: Dictionary = {
	"gourmet_guide": "美食指南",
}

# 外部数据
var _available_marketers: Array[Dictionary] = []  # [{staff_id, employee_type, marketing_types, max_duration, capacity, used, remaining}]
var _available_boards_by_type: Dictionary = {}  # type_id -> Array[int]

# 当前选择
var _selected_type: String = ""
var _selected_target: Vector2i = Vector2i(-1, -1)
var _selected_employee_type: String = ""
var _selected_staff_id: int = -1
var _selected_board_number: int = 0
var _selected_product: String = ""
var _selected_duration: int = 1
var _selected_rotation: int = 0
var _selected_axis: String = ""

var _type_buttons: Dictionary = {}  # type_id -> marketing_type_button instance
var _marketer_info_by_key: Dictionary = {}  # picker key -> marketer info

var _map_callback: Callable  # 用于请求地图选择
var _icon_cache = MarketingPanelIconCacheClass.new()

var _board_button_group: ButtonGroup = ButtonGroup.new()
var _product_button_group: ButtonGroup = ButtonGroup.new()
var _duration_button_group: ButtonGroup = ButtonGroup.new()

var _board_button_by_number: Dictionary = {} # int -> MarketingBoardButton
var _product_button_by_id: Dictionary = {} # String -> Button
var _duration_button_by_value: Dictionary = {} # int -> Button

static func _format_staff_usage_badge(remaining: int, capacity: int) -> String:
	var safe_capacity := maxi(0, capacity)
	if safe_capacity <= 1:
		return ""
	return "%d/%d" % [maxi(0, remaining), safe_capacity]

static func _extract_marketing_type_ids_from_marketer(marketer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var marketing_types_val = marketer.get("marketing_types", [])
	if marketing_types_val is Array:
		for type_val in Array(marketing_types_val):
			var type_id := str(type_val).strip_edges()
			if type_id.is_empty() or seen.has(type_id):
				continue
			seen[type_id] = true
			out.append(type_id)

	var legacy_type := str(marketer.get("type", "")).strip_edges()
	if not legacy_type.is_empty() and not seen.has(legacy_type):
		seen[legacy_type] = true
		out.append(legacy_type)

	out.sort()
	return out

static func _normalize_marketer_entries(marketers: Array[Dictionary]) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	var order: Array[String] = []
	var legacy_index := 0

	for marketer_val in marketers:
		if not (marketer_val is Dictionary):
			continue
		var marketer: Dictionary = marketer_val
		var staff_id := int(marketer.get("staff_id", -1))
		var emp_id := str(marketer.get("employee_type", marketer.get("id", ""))).strip_edges()
		if emp_id.is_empty():
			continue
		var key := ""
		if staff_id > 0:
			key = "staff:%d" % staff_id
		else:
			legacy_index += 1
			key = "legacy:%s:%d" % [emp_id, legacy_index]

		var type_ids := _extract_marketing_type_ids_from_marketer(marketer)
		if type_ids.is_empty():
			continue

		if not by_key.has(key):
			var entry := marketer.duplicate(true)
			entry["employee_type"] = emp_id
			entry["id"] = emp_id
			entry["marketing_types"] = type_ids
			entry.erase("type")
			by_key[key] = entry
			order.append(key)
			continue

		var existing: Dictionary = by_key[key]
		var merged_seen := {}
		var merged_types: Array[String] = []
		var existing_types_val = existing.get("marketing_types", [])
		if existing_types_val is Array:
			for existing_type_val in Array(existing_types_val):
				var existing_type := str(existing_type_val).strip_edges()
				if existing_type.is_empty() or merged_seen.has(existing_type):
					continue
				merged_seen[existing_type] = true
				merged_types.append(existing_type)
		for type_id2 in type_ids:
			if merged_seen.has(type_id2):
				continue
			merged_seen[type_id2] = true
			merged_types.append(type_id2)
		merged_types.sort()
		existing["marketing_types"] = merged_types
		by_key[key] = existing

	var out: Array[Dictionary] = []
	for key2 in order:
		var entry_val = by_key.get(key2, null)
		if entry_val is Dictionary:
			out.append(Dictionary(entry_val).duplicate(true))
	return out

func set_visual_modules(modules: Array[String]) -> void:
	_icon_cache.set_visual_modules(modules)
	_rebuild_type_buttons()
	_rebuild_product_buttons()
	_rebuild_board_buttons()

func _get_confirm_button() -> Button:
	return confirm_btn

func _get_cancel_button() -> Button:
	return cancel_btn

func _on_panel_ready() -> void:
	UiStylesClass.apply_button_primary(confirm_btn)
	UiStylesClass.apply_button_secondary(cancel_btn)
	if marketer_option != null:
		if marketer_option.has_signal("employee_selected"):
			marketer_option.employee_selected.connect(_on_marketer_selected)

	_board_button_group.allow_unpress = false
	_product_button_group.allow_unpress = false

	_setup_rotation_controls()
	_update_rotation_section()
	_rebuild_product_buttons()
	_rebuild_marketer_options()
	_rebuild_type_buttons()
	_sync_selected_type_after_data_change(true)
	_update_target_display()
	_update_confirm_state()

func set_available_marketers(marketers: Array[Dictionary]) -> void:
	_available_marketers = _normalize_marketer_entries(marketers)
	_rebuild_marketer_options()
	_rebuild_type_buttons()
	_sync_selected_type_after_data_change(true)
	_update_confirm_state()

func set_available_boards(boards_by_type: Dictionary) -> void:
	_available_boards_by_type = boards_by_type.duplicate(true)
	_rebuild_type_buttons()
	_sync_selected_type_after_data_change(true)
	_update_confirm_state()

func set_map_selection_callback(callback: Callable) -> void:
	_map_callback = callback

func set_selected_target(position: Vector2i, axis: String = "") -> void:
	_selected_target = position
	if not axis.is_empty():
		_selected_axis = axis
	_update_target_display()
	_update_confirm_state()
	clear_error()

func clear_selection() -> void:
	_selected_type = ""
	_selected_target = Vector2i(-1, -1)
	_selected_employee_type = ""
	_selected_staff_id = -1
	_selected_board_number = 0
	_selected_duration = 1
	_selected_rotation = 0
	_selected_axis = ""
	_marketer_info_by_key.clear()
	clear_error()

	for btn in _type_buttons.values():
		if is_instance_valid(btn):
			btn.set_selected(false)

	if marketer_option != null:
		marketer_option.clear()

	_clear_board_buttons()
	_clear_duration_buttons()
	_sync_rotation_controls()

	_update_target_display()
	_update_confirm_state()

func _rebuild_type_buttons() -> void:
	UiRebuildHelpersClass.free_nodes_dict(_type_buttons)

	if type_container == null:
		return

	var build_r: Dictionary = MarketingPanelTypeSpecsBuilderClass.build_type_specs(
		_get_type_specs_marketers(),
		_available_boards_by_type,
		MARKETING_TYPES,
		MARKETING_TYPE_NAME_OVERRIDES
	)
	var specs_val = build_r.get("specs", [])
	var specs: Array = specs_val if (specs_val is Array) else []

	for spec_val in specs:
		if not (spec_val is Dictionary):
			continue
		var spec: Dictionary = spec_val
		var type_id := str(spec.get("type_id", "")).strip_edges()
		if type_id.is_empty():
			continue

		var type_def_val = spec.get("type_def", {})
		var type_def_use: Dictionary = type_def_val if (type_def_val is Dictionary) else {}

		var btn = MarketingTypeButtonClass.new()
		btn.type_id = type_id
		btn.type_def = type_def_use
		btn.icon_texture = _icon_cache.get_marketing_icon_texture(type_id, MARKETING_TYPE_ICON_SIZE)
		btn.is_available = bool(spec.get("is_available", false))
		btn.marketer_count = int(spec.get("marketer_count", 0))
		btn.board_count = int(spec.get("board_count", 0))
		btn.type_selected.connect(_on_type_selected)
		type_container.add_child(btn)
		_type_buttons[type_id] = btn

	_sync_type_button_selection()

func _on_type_selected(type_id: String) -> void:
	_select_type(type_id)

func _select_type(type_id: String) -> void:
	var next_type := str(type_id).strip_edges()
	if next_type.is_empty():
		return

	_selected_type = next_type
	_selected_target = Vector2i(-1, -1)
	_selected_board_number = 0
	_selected_axis = ""
	_update_rotation_section()
	clear_error()

	_sync_type_button_selection()
	_rebuild_board_buttons()
	_update_target_display()
	_update_confirm_state()

func _get_type_specs_marketers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _selected_staff_id > 0:
		var selected_key := "staff:%d" % _selected_staff_id
		var selected_info: Dictionary = Dictionary(_marketer_info_by_key.get(selected_key, {}))
		if not selected_info.is_empty():
			out.append(selected_info.duplicate(true))
			return out
		for marketer_val in _available_marketers:
			if not (marketer_val is Dictionary):
				continue
			var marketer: Dictionary = marketer_val
			if int(marketer.get("staff_id", -1)) == _selected_staff_id:
				out.append(marketer.duplicate(true))
				return out

	for marketer_val2 in _available_marketers:
		if marketer_val2 is Dictionary:
			out.append(Dictionary(marketer_val2).duplicate(true))
	return out

func _get_available_type_ids_for_current_selection() -> Array[String]:
	var out: Array[String] = []
	var build_r: Dictionary = MarketingPanelTypeSpecsBuilderClass.build_type_specs(
		_get_type_specs_marketers(),
		_available_boards_by_type,
		MARKETING_TYPES,
		MARKETING_TYPE_NAME_OVERRIDES
	)
	var available_val = build_r.get("available_type_ids", [])
	if available_val is Array:
		for type_val in Array(available_val):
			var type_id := str(type_val).strip_edges()
			if type_id.is_empty():
				continue
			out.append(type_id)
	return out

func _sync_type_button_selection() -> void:
	for tid in _type_buttons.keys():
		var btn = _type_buttons[tid]
		if is_instance_valid(btn):
			btn.set_selected(str(tid) == _selected_type)

func _sync_selected_type_after_data_change(auto_select_single: bool) -> void:
	var available_type_ids := _get_available_type_ids_for_current_selection()
	var selected_is_valid := false
	for type_id in available_type_ids:
		if type_id == _selected_type:
			selected_is_valid = true
			break

	if not selected_is_valid:
		_selected_type = ""
		_selected_board_number = 0
		_selected_target = Vector2i(-1, -1)
		_selected_axis = ""

	if _selected_type.is_empty() and auto_select_single and available_type_ids.size() == 1:
		_select_type(str(available_type_ids[0]))
		return

	_sync_type_button_selection()
	_update_rotation_section()
	if _selected_type.is_empty():
		_clear_board_buttons()
	else:
		_rebuild_board_buttons()
	_update_target_display()
	_update_confirm_state()

func _rebuild_marketer_options() -> void:
	var previous_staff_id := _selected_staff_id
	_selected_employee_type = ""
	_marketer_info_by_key.clear()
	_selected_staff_id = -1

	if marketer_option == null:
		return

	var items: Array[Dictionary] = []
	var selected_key := ""
	var first_enabled_key := ""
	var first_key := ""
	for marketer_val in _available_marketers:
		if not (marketer_val is Dictionary):
			continue
		var marketer: Dictionary = marketer_val
		var staff_id := int(marketer.get("staff_id", -1))
		var emp_id := str(marketer.get("employee_type", marketer.get("id", ""))).strip_edges()
		if staff_id <= 0 or emp_id.is_empty():
			continue
		var key := "staff:%d" % staff_id
		var remaining := int(marketer.get("remaining", 0))
		var capacity := int(marketer.get("capacity", 0))
		var enabled := remaining > 0
		var info := marketer.duplicate(true)
		info["key"] = key
		_marketer_info_by_key[key] = info
		items.append({
			"id": emp_id,
			"key": key,
			"employee_def": _get_employee_def_for_card(emp_id),
			"badge_text": _format_staff_usage_badge(remaining, capacity),
			"tag_text": "",
			"enabled": enabled,
		})
		if first_key.is_empty():
			first_key = key
		if enabled and first_enabled_key.is_empty():
			first_enabled_key = key
		if previous_staff_id > 0 and previous_staff_id == staff_id:
			selected_key = key

	if selected_key.is_empty():
		selected_key = first_enabled_key if not first_enabled_key.is_empty() else first_key

	if not items.is_empty():
		marketer_option.set_items(items, selected_key)
		_apply_selected_marketer_by_key(selected_key)
	else:
		marketer_option.clear()
		_selected_employee_type = ""
		_selected_staff_id = -1
		_clear_duration_buttons()

func _apply_selected_marketer_by_key(item_key: String) -> void:
	var key := str(item_key).strip_edges()
	var info: Dictionary = Dictionary(_marketer_info_by_key.get(key, {}))
	if info.is_empty():
		_selected_employee_type = ""
		_selected_staff_id = -1
		_clear_duration_buttons()
		return

	_selected_employee_type = str(info.get("employee_type", info.get("id", ""))).strip_edges()
	_selected_staff_id = int(info.get("staff_id", -1))

	var max_duration := int(info.get("max_duration", 1))
	if max_duration <= 0:
		max_duration = 1

	_selected_duration = max_duration
	_rebuild_duration_buttons(max_duration)

func _setup_rotation_controls() -> void:
	if rotate_left_btn != null:
		rotate_left_btn.focus_mode = Control.FOCUS_NONE
		rotate_left_btn.tooltip_text = "向左旋转 90度"
		UiStylesClass.apply_button_secondary(rotate_left_btn)
		if not rotate_left_btn.pressed.is_connected(_on_rotate_left_pressed):
			rotate_left_btn.pressed.connect(_on_rotate_left_pressed)
	if rotate_right_btn != null:
		rotate_right_btn.focus_mode = Control.FOCUS_NONE
		rotate_right_btn.tooltip_text = "向右旋转 90度"
		UiStylesClass.apply_button_secondary(rotate_right_btn)
		if not rotate_right_btn.pressed.is_connected(_on_rotate_right_pressed):
			rotate_right_btn.pressed.connect(_on_rotate_right_pressed)
	if rotation_value_label != null:
		UiStylesClass.apply_label_dark(rotation_value_label)
	_sync_rotation_controls()

func _sync_rotation_controls() -> void:
	var can_rotate := not _selected_type.is_empty() and _selected_type != "airplane"
	if rotation_value_label != null:
		rotation_value_label.text = "%d度" % _selected_rotation
	if rotate_left_btn != null:
		rotate_left_btn.disabled = not can_rotate
	if rotate_right_btn != null:
		rotate_right_btn.disabled = not can_rotate

func _update_rotation_section() -> void:
	# airplane rotation has no meaning; orientation is determined by the attached edge (issue_tracker #40).
	var is_airplane := _selected_type == "airplane"
	if rotation_section != null:
		rotation_section.visible = not is_airplane
	if is_airplane and _selected_rotation != 0:
		_selected_rotation = 0
	_sync_rotation_controls()

func get_selected_rotation() -> int:
	return _selected_rotation

func can_rotate() -> bool:
	return not _selected_type.is_empty() and _selected_type != "airplane"

func set_selected_rotation(rotation: int) -> void:
	var rot := int(rotation)
	if not rot in [0, 90, 180, 270]:
		rot = 0
	if _selected_type == "airplane":
		rot = 0
	if _selected_rotation == rot:
		_sync_rotation_controls()
		return

	_selected_rotation = rot
	_selected_target = Vector2i(-1, -1)
	_selected_axis = ""
	_update_target_display()
	clear_error()
	_sync_rotation_controls()

	for bn in _board_button_by_number.keys():
		var b = _board_button_by_number.get(bn, null)
		if is_instance_valid(b) and b.has_method("set_board_rotation"):
			b.call("set_board_rotation", _selected_rotation)
		elif is_instance_valid(b) and b is Control:
			(b as Control).queue_redraw()

	_sync_board_button_previews()
	_update_confirm_state()
	_request_map_selection_refresh()

func rotate_ccw() -> void:
	set_selected_rotation(_selected_rotation - 90)

func rotate_cw() -> void:
	set_selected_rotation(_selected_rotation + 90)

func _on_rotate_left_pressed() -> void:
	rotate_ccw()

func _on_rotate_right_pressed() -> void:
	rotate_cw()

func _request_map_selection_refresh() -> void:
	if not _map_callback.is_valid():
		return
	if _selected_type.is_empty():
		return
	if _selected_employee_type.is_empty():
		return
	if _selected_board_number <= 0:
		return
	_map_callback.call(_selected_type, _selected_employee_type, _selected_board_number, _selected_rotation)

func _get_board_base_size(board_number: int) -> Vector2i:
	if board_number <= 0:
		return Vector2i.ONE
	if not MarketingRegistryClass.is_loaded():
		return Vector2i.ONE
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Vector2i.ONE
	if def is MarketingDef:
		var fs: Vector2i = (def as MarketingDef).footprint_size
		return fs if fs != Vector2i.ZERO else Vector2i.ONE
	if def.has_method("get"):
		var fs_val = def.get("footprint_size")
		if fs_val is Vector2i:
			var v: Vector2i = fs_val
			return v if v != Vector2i.ZERO else Vector2i.ONE
	return Vector2i.ONE

func _set_selected_board_number(board_number: int) -> void:
	var bn := int(board_number)
	if bn <= 0:
		return
	_selected_board_number = bn
	_update_rotation_section()

	_selected_target = Vector2i(-1, -1)
	_selected_axis = ""
	_update_target_display()
	clear_error()

	# Ensure the corresponding button is pressed (rebuild/select paths both use this).
	if _board_button_by_number.has(bn):
		var btn = _board_button_by_number[bn]
		if is_instance_valid(btn) and btn is Button:
			(btn as Button).button_pressed = true

	_sync_board_button_previews()
	_sync_rotation_controls()
	_update_confirm_state()
	_request_map_selection_refresh()

func _sync_board_button_previews() -> void:
	var product_tex := _icon_cache.get_product_icon_texture(_selected_product)
	for bn in _board_button_by_number.keys():
		var btn = _board_button_by_number.get(bn, null)
		if not is_instance_valid(btn):
			continue
		if btn.has_method("set_preview"):
			btn.call("set_preview", _selected_rotation, product_tex, int(bn) == _selected_board_number)
		else:
			# Fallback for earlier versions of the button script.
			if btn is Object:
				btn.set("board_rotation", _selected_rotation)
				btn.set("product_texture", product_tex)
				btn.set("show_product", int(bn) == _selected_board_number)
			if btn is Control:
				(btn as Control).queue_redraw()

func _clear_board_buttons() -> void:
	_board_button_by_number.clear()
	UiRebuildHelpersClass.free_children(board_flow)

func _clear_product_buttons() -> void:
	_product_button_by_id.clear()
	UiRebuildHelpersClass.free_children(product_flow)

func _clear_duration_buttons() -> void:
	_duration_button_by_value.clear()
	UiRebuildHelpersClass.free_children(duration_flow)

func _rebuild_duration_buttons(max_duration: int) -> void:
	_clear_duration_buttons()

	if duration_flow == null:
		return

	var max_d := maxi(1, int(max_duration))
	_duration_button_group.allow_unpress = false

	for d in range(1, max_d + 1):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(40, 32)
		btn.toggle_mode = true
		btn.button_group = _duration_button_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = str(d)
		btn.pressed.connect(func():
			_on_duration_button_pressed(d)
		)
		duration_flow.add_child(btn)
		_duration_button_by_value[d] = btn

	var to_select := clampi(_selected_duration, 1, max_d)
	_selected_duration = to_select
	if _duration_button_by_value.has(to_select):
		var b: Button = _duration_button_by_value[to_select]
		b.button_pressed = true
		_on_duration_button_pressed(to_select)

func _rebuild_board_buttons() -> void:
	_clear_board_buttons()
	_selected_board_number = 0

	if board_flow == null:
		return

	if _selected_type.is_empty():
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

	var type_tex: Texture2D = _icon_cache.get_marketing_texture(_selected_type)

	for bn in boards:
		var btn = MarketingBoardButtonClass.new()
		btn.custom_minimum_size = Vector2(108, 84)
		btn.toggle_mode = true
		btn.button_group = _board_button_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.board_number = bn
		btn.base_size = _get_board_base_size(bn)
		btn.board_rotation = _selected_rotation
		btn.marketing_texture = type_tex
		btn.product_texture = _icon_cache.get_product_icon_texture(_selected_product)
		btn.show_product = false
		btn.tooltip_text = "#%d  %dx%d" % [bn, btn.get_rotated_size().x, btn.get_rotated_size().y]
		btn.pressed.connect(func():
			_on_board_button_pressed(bn)
		)
		board_flow.add_child(btn)
		_board_button_by_number[bn] = btn

	if not boards.is_empty():
		_set_selected_board_number(boards[0])

func _rebuild_product_buttons() -> void:
	_clear_product_buttons()

	if product_flow == null:
		return
	if not ProductRegistryClass.is_loaded():
		return

	var ids: Array[String] = []
	for pid_val in ProductRegistryClass.get_all_ids():
		ids.append(str(pid_val))
	ids.sort()

	var first_pid := ""
	for pid in ids:
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

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(44, 44)
		btn.toggle_mode = true
		btn.button_group = _product_button_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.icon = _icon_cache.get_product_icon_texture_scaled(pid, PRODUCT_ICON_SIZE)
		btn.expand_icon = true
		btn.text = ""
		btn.tooltip_text = name
		btn.set_meta("product_id", pid)
		btn.pressed.connect(func():
			_on_product_button_pressed(pid)
		)
		product_flow.add_child(btn)
		_product_button_by_id[pid] = btn
		if first_pid.is_empty():
			first_pid = pid

	var to_select := _selected_product
	if to_select.is_empty() or not _product_button_by_id.has(to_select):
		to_select = first_pid
	_selected_product = to_select
	if not to_select.is_empty() and _product_button_by_id.has(to_select):
		var b: Button = _product_button_by_id[to_select]
		b.button_pressed = true
		_on_product_button_pressed(to_select)

func _on_marketer_selected(employee_type: String) -> void:
	if marketer_option == null:
		return
	var key := ""
	if marketer_option.has_method("get_selected_key"):
		key = str(marketer_option.get_selected_key()).strip_edges()
	if key.is_empty():
		return
	_apply_selected_marketer_by_key(key)
	_selected_target = Vector2i(-1, -1)
	_selected_axis = ""
	clear_error()
	_rebuild_type_buttons()
	_sync_selected_type_after_data_change(true)
	_update_target_display()
	_update_confirm_state()

func _get_employee_def_for_card(employee_type: String) -> Dictionary:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return {"id": emp_id, "name": emp_id}
	if not EmployeeRegistryClass.is_loaded():
		return {"id": emp_id, "name": emp_id}
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val != null and def_val.has_method("to_dict"):
		return def_val.to_dict()
	return {"id": emp_id, "name": emp_id}

func _on_board_button_pressed(board_number: int) -> void:
	_set_selected_board_number(board_number)

func _on_product_button_pressed(product_id: String) -> void:
	_selected_product = str(product_id)
	_sync_board_button_previews()
	_update_confirm_state()
	clear_error()

func _on_duration_button_pressed(duration: int) -> void:
	_selected_duration = int(duration)
	_update_confirm_state()
	clear_error()

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

func _get_marketing_effect_hint(type_id: String) -> String:
	match type_id:
		"billboard":
			return "影响：四向相邻房屋"
		"mailbox":
			return "影响：同街区房屋"
		"airplane":
			return "影响：整行/列（角落需选择方向）"
		"radio":
			return "影响：周围 3x3 板块内房屋"
		"gourmet_guide":
			return "影响：所有有花园的房屋"
		_:
			return ""

func _get_employee_range_hint(employee_type: String) -> String:
	if employee_type.is_empty():
		return ""
	if not EmployeeRegistryClass.is_loaded():
		return ""
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null:
		return ""
	if not (def_val is EmployeeDef):
		return ""
	var def: EmployeeDef = def_val
	var range_type := str(def.range_type)
	var range_value := int(def.range_value)
	if range_type.is_empty() or range_value < 0:
		return "可放置距离：不限"
	if range_type == "road":
		return "可放置距离：公路 %d" % range_value
	if range_type == "air":
		return "可放置距离：飞艇 %d" % range_value
	return "可放置距离：%s %d" % [range_type, range_value]

func _update_target_display() -> void:
	if target_label == null:
		return

	if _selected_employee_type.is_empty():
		target_label.text = "请先选择营销员"
		target_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	elif _selected_type.is_empty():
		target_label.text = "请选择营销类型"
		target_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	elif _selected_target == Vector2i(-1, -1):
		target_label.text = "请在地图上选择目标位置"
		target_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 0.8))
	else:
		var axis_text := ""
		if _selected_type == "airplane":
			if _selected_axis == "row":
				axis_text = "（横飞）"
			elif _selected_axis == "col":
				axis_text = "（竖飞）"
			else:
				axis_text = "（未选择方向）"
		target_label.text = "目标位置: (%d, %d)%s" % [_selected_target.x, _selected_target.y, axis_text]
		target_label.add_theme_color_override("font_color", Color(0.28, 0.55, 0.22, 1))

	if range_info_label != null:
		if _selected_employee_type.is_empty() or _selected_type.is_empty():
			range_info_label.text = ""
		else:
			var lines: Array[String] = []
			var effect_hint := _get_marketing_effect_hint(_selected_type)
			if not effect_hint.is_empty():
				lines.append(effect_hint)
			var range_hint := _get_employee_range_hint(_selected_employee_type)
			if not range_hint.is_empty():
				lines.append(range_hint)
			lines.append("绿色高亮：可放置格")
			range_info_label.text = "\n".join(lines)

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
	if _selected_type == "airplane" and _selected_target != Vector2i(-1, -1):
		ok = ok and (_selected_axis == "row" or _selected_axis == "col")

	confirm_btn.disabled = not ok
	right_panel_footer_changed.emit()

func set_error(message: String) -> void:
	if error_label == null:
		return
	var msg := message.strip_edges()
	if msg.is_empty():
		clear_error()
		return
	error_label.text = msg
	error_label.visible = true

func clear_error() -> void:
	if error_label == null:
		return
	error_label.text = ""
	error_label.visible = false

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return

	marketing_requested.emit(
		_selected_employee_type,
		_selected_board_number,
		_selected_target,
		_selected_product,
		_selected_duration,
		_selected_rotation,
		_selected_axis,
		_selected_staff_id
	)

func _on_cancel_pressed() -> void:
	cancelled.emit()
