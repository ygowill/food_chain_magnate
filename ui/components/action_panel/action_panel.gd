# 动作面板组件
# 显示当前阶段可用的动作，支持触发执行
class_name ActionPanel
extends Control

signal action_requested(action_id: String, params: Dictionary)

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const PiecePlacementOverlayScript = preload("res://ui/components/piece_placement/piece_placement_overlay.gd")

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer
@onready var context_panel: Control = $MarginContainer/VBoxContainer/ContextPanel
@onready var context_title_label: Label = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ContextTitleLabel
@onready var context_hint_label: Label = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ContextHintLabel
@onready var restaurant_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RestaurantRow
@onready var restaurant_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RestaurantRow/RestaurantOption
@onready var employee_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/EmployeeRow
@onready var employee_option: HFlowContainer = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/EmployeeRow/EmployeeOption
@onready var piece_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/PieceRow
@onready var piece_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/PieceRow/PieceOption
@onready var rotation_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow
@onready var rotation_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow/RotationOption
@onready var house_number_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/HouseNumberRow
@onready var house_number_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/HouseNumberRow/HouseNumberOption
@onready var direction_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/DirectionRow
@onready var direction_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/DirectionRow/DirectionOption
@onready var cancel_context_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ButtonsRow/CancelContextButton
@onready var confirm_context_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ButtonsRow/ConfirmContextButton
@onready var rewind_phase_button: Button = $MarginContainer/VBoxContainer/UtilityRow/RewindPhaseButton

var _action_registry = null  # ActionRegistry
var _game_state: GameState = null
var _current_player_id: int = -1
var _action_buttons: Dictionary = {}  # action_id -> ActionButton
var _mandatory_action_ids: Dictionary = {}  # action_id -> true
var _context_overlay: Node = null
var _context_syncing: bool = false
var _globally_disabled: bool = false
var _globally_disabled_reason: String = ""

# 不在 UI 中展示的内部动作
const HIDDEN_ACTION_IDS := {
	ActionIdsClass.END_TURN: true,
	ActionIdsClass.ADVANCE_PHASE: true,
	# 定价类强制动作改为“准备离开 Working 时自动执行”，不在面板中展示。
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

# 定价类强制动作在 UI 中隐藏，并在执行 skip 前由 Game 自动补完（见 Game._maybe_auto_complete_mandatory_actions_before_skip）。
# 为避免软锁：当 skip 仅因“缺少这些可自动补完的强制动作”而不可用时，ActionPanel 仍应允许点击 skip。
const AUTO_MANDATORY_ACTION_IDS := {
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

# 动作显示名称映射
const ACTION_DISPLAY_NAMES: Dictionary = {
	ActionIdsClass.ADVANCE_PHASE: "推进阶段",
	ActionIdsClass.SKIP: "确认结束",
	ActionIdsClass.SKIP_SUB_PHASE: "跳过子阶段",
	"choose_turn_order": "选择顺序",
	"submit_restructuring": "确认重组",
	"recruit": "招聘",
	"train": "培训",
	"initiate_marketing": "发起营销",
	"produce_food": "生产食物",
	"procure_drinks": "采购饮料",
	"place_house": "放置房屋",
	"add_garden": "添加花园",
	"place_restaurant": "放置餐厅",
	"move_restaurant": "移动餐厅",
	ActionIdsClass.SET_PRICE: "设定价格",
	ActionIdsClass.SET_LUXURY_PRICE: "设定奢侈品价格",
	ActionIdsClass.SET_DISCOUNT: "设定折扣",
	"fire": "解雇员工",
}

# 动作说明映射
const ACTION_DESCRIPTIONS: Dictionary = {
	ActionIdsClass.ADVANCE_PHASE: "强制推进到下一阶段",
	ActionIdsClass.SKIP: "确认结束本阶段/子阶段",
	ActionIdsClass.SKIP_SUB_PHASE: "跳过当前子阶段（Working）",
	"choose_turn_order": "在顺序轨上选择位置",
	"submit_restructuring": "提交本回合公司结构（重组阶段）",
	"recruit": "招聘一名入门级员工",
	"train": "培训待命区的员工",
	"initiate_marketing": "发起营销活动",
	"produce_food": "使用厨房员工生产食物",
	"procure_drinks": "使用采购员获取饮料",
	"place_house": "放置新房屋",
	"add_garden": "为房屋添加花园",
	"place_restaurant": "放置新餐厅",
	"move_restaurant": "移动已有餐厅",
	ActionIdsClass.SET_PRICE: "设定产品价格",
	ActionIdsClass.SET_LUXURY_PRICE: "设定奢侈品价格",
	ActionIdsClass.SET_DISCOUNT: "设定折扣",
	"fire": "解雇员工",
}

func _get_executor_display_name(action_id: String) -> String:
	if _action_registry == null or not _action_registry.has_method("get_executor"):
		return ""
	var ex = _action_registry.get_executor(action_id)
	if ex == null:
		return ""
	return str(ex.display_name).strip_edges()

func _get_executor_description(action_id: String) -> String:
	if _action_registry == null or not _action_registry.has_method("get_executor"):
		return ""
	var ex = _action_registry.get_executor(action_id)
	if ex == null:
		return ""
	return str(ex.description).strip_edges()

func _should_auto_hide_if_not_initiatable(action_id: String) -> bool:
	if _action_registry == null or not _action_registry.has_method("get_executor"):
		return false
	var ex = _action_registry.get_executor(action_id)
	if ex == null:
		return false
	# ActionExecutor 提供 ui_hide_if_not_initiatable 属性；模块侧可按需设置，避免 UI 硬编码 action_id。
	return bool(ex.ui_hide_if_not_initiatable)

func _get_working_sub_phase_order_names(state: GameState) -> Array[String]:
	if state == null:
		return []
	if state.round_state is Dictionary:
		var rs: Dictionary = state.round_state
		var order_val = rs.get("working_sub_phase_order", null)
		if order_val is Array:
			var order: Array[String] = []
			for it in Array(order_val):
				var s := str(it).strip_edges()
				if not s.is_empty():
					order.append(s)
			if not order.is_empty():
				return order

	return [
		DefsClass.SUB_PHASE_RECRUIT,
		DefsClass.SUB_PHASE_TRAIN,
		DefsClass.SUB_PHASE_MARKETING,
		DefsClass.SUB_PHASE_GET_FOOD,
		DefsClass.SUB_PHASE_GET_DRINKS,
		DefsClass.SUB_PHASE_PLACE_HOUSES,
		DefsClass.SUB_PHASE_PLACE_RESTAURANTS,
	]

func _should_show_skip_sub_phase_button() -> bool:
	if _game_state == null:
		return true
	if str(_game_state.phase) != DefsClass.PHASE_WORKING:
		return true
	var current_sub := str(_game_state.sub_phase).strip_edges()
	if current_sub.is_empty():
		return true

	var order := _get_working_sub_phase_order_names(_game_state)
	if order.is_empty():
		return true
	var idx := order.find(current_sub)
	if idx < 0:
		return true
	return idx < order.size() - 1

func _get_skip_sub_phase_display_name() -> String:
	if _game_state == null:
		return "跳过子阶段"
	match str(_game_state.sub_phase):
		DefsClass.SUB_PHASE_RECRUIT:
			return "跳过招聘"
		DefsClass.SUB_PHASE_TRAIN:
			return "跳过培训"
		DefsClass.SUB_PHASE_MARKETING:
			return "跳过营销"
		DefsClass.SUB_PHASE_GET_FOOD:
			return "跳过生产食物"
		DefsClass.SUB_PHASE_GET_DRINKS:
			return "跳过采购饮料"
		DefsClass.SUB_PHASE_PLACE_HOUSES:
			return "跳过放置房屋"
		DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
			return "跳过放置餐厅"
		_:
			return "跳过子阶段"

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if items_container != null:
		items_container.add_theme_constant_override("separation", 4)
	_setup_context_ui()
	_setup_utility_ui()

func _setup_utility_ui() -> void:
	if not is_instance_valid(rewind_phase_button):
		return
	UiSignalHelpersClass.safe_connect(rewind_phase_button, "pressed", _on_rewind_phase_pressed)

func _setup_context_ui() -> void:
	if not is_instance_valid(context_panel):
		return
	context_panel.visible = false

	UiSignalHelpersClass.safe_connect(cancel_context_button, "pressed", _on_cancel_context_pressed)
	UiSignalHelpersClass.safe_connect(confirm_context_button, "pressed", _on_confirm_context_pressed)
	UiSignalHelpersClass.safe_connect(restaurant_option, "item_selected", _on_restaurant_option_selected)
	UiSignalHelpersClass.safe_connect(employee_option, "employee_selected", _on_employee_option_selected)
	UiSignalHelpersClass.safe_connect(piece_option, "item_selected", _on_piece_option_selected)
	UiSignalHelpersClass.safe_connect(rotation_option, "item_selected", _on_rotation_option_selected)
	UiSignalHelpersClass.safe_connect(house_number_option, "item_selected", _on_house_number_option_selected)
	UiSignalHelpersClass.safe_connect(direction_option, "item_selected", _on_direction_option_selected)

func bind_context_overlay(overlay: Node) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	if _context_overlay == overlay:
		_refresh_context_from_overlay()
		return

	_detach_overlay_signals()
	_context_overlay = overlay
	_attach_overlay_signals()
	_refresh_context_from_overlay()

func clear_context_overlay() -> void:
	_detach_overlay_signals()
	_context_overlay = null
	_hide_context_panel()

func _attach_overlay_signals() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return
	UiSignalHelpersClass.safe_connect(_context_overlay, "ui_state_changed", _on_overlay_ui_state_changed)

func _detach_overlay_signals() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return
	var sig := StringName("ui_state_changed")
	if not _context_overlay.has_signal(sig):
		return
	if _context_overlay.is_connected(sig, _on_overlay_ui_state_changed):
		_context_overlay.disconnect(sig, _on_overlay_ui_state_changed)

func _on_overlay_ui_state_changed() -> void:
	_refresh_context_from_overlay()

func _hide_context_panel() -> void:
	if is_instance_valid(context_panel):
		context_panel.visible = false

func _show_context_panel() -> void:
	if is_instance_valid(context_panel):
		context_panel.visible = true

func _refresh_context_from_overlay() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		_hide_context_panel()
		return
	if _context_overlay is Control and not (_context_overlay as Control).visible:
		clear_context_overlay()
		return

	if _context_overlay is RestaurantPlacementOverlay:
		_refresh_restaurant_placement_context(_context_overlay as RestaurantPlacementOverlay)
		return
	if _context_overlay is HousePlacementOverlay:
		_refresh_house_placement_context(_context_overlay as HousePlacementOverlay)
		return
	if PiecePlacementOverlayScript != null and _context_overlay is PiecePlacementOverlayScript:
		_refresh_piece_placement_context(_context_overlay)
		return

	clear_context_overlay()

func _refresh_restaurant_placement_context(overlay: RestaurantPlacementOverlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode := overlay.get_mode()
	context_title_label.text = "🏪 放置餐厅" if mode != "move_restaurant" else "🏪 移动餐厅"
	context_hint_label.text = overlay.get_hint_text()

	restaurant_row.visible = (mode == "move_restaurant")
	employee_row.visible = false
	piece_row.visible = false
	direction_row.visible = false
	rotation_row.visible = true
	house_number_row.visible = false

	_rebuild_rotation_option(overlay.get_selected_rotation())
	_rebuild_employee_option(overlay.get_available_employees(), overlay.get_selected_employee())
	employee_row.visible = not overlay.get_available_employees().is_empty()

	if mode == "move_restaurant":
		_rebuild_restaurant_option(
			overlay.get_available_restaurants(),
			overlay.get_selected_restaurant()
		)

	confirm_context_button.text = "确认移动" if mode == "move_restaurant" else "确认放置"
	confirm_context_button.disabled = not overlay.can_confirm()

	_context_syncing = false

func _refresh_house_placement_context(overlay: HousePlacementOverlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode := overlay.get_mode()
	context_title_label.text = "🌳 添加花园" if mode == "add_garden" else "🏠 放置房屋"
	context_hint_label.text = overlay.get_hint_text()

	restaurant_row.visible = false
	employee_row.visible = false
	piece_row.visible = false
	rotation_row.visible = (mode == "place_house")
	house_number_row.visible = (mode == "place_house")
	direction_row.visible = (mode == "add_garden")

	_rebuild_employee_option(overlay.get_available_employees(), overlay.get_selected_employee())
	employee_row.visible = not overlay.get_available_employees().is_empty()

	if mode == "place_house":
		_rebuild_rotation_option(overlay.get_selected_rotation())
		_rebuild_house_number_option(
			overlay.get_available_house_numbers(),
			overlay.get_selected_house_number()
		)
	if mode == "add_garden":
		_rebuild_direction_option(overlay.get_selected_direction())

	confirm_context_button.text = "确认添加花园" if mode == "add_garden" else "确认放置"
	confirm_context_button.disabled = not overlay.can_confirm()

	_context_syncing = false

func _refresh_piece_placement_context(overlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode := str(overlay.get_mode()).strip_edges()
	var title := _get_executor_display_name(mode)
	if title.is_empty():
		context_title_label.text = "🧩 放置板块"
	else:
		context_title_label.text = "🧩 %s" % title
	context_hint_label.text = overlay.get_hint_text()

	restaurant_row.visible = false
	employee_row.visible = false
	piece_row.visible = true
	rotation_row.visible = true
	house_number_row.visible = false
	direction_row.visible = false

	_rebuild_piece_option(overlay.get_available_pieces(), overlay.get_selected_piece())
	_rebuild_rotation_option(overlay.get_selected_rotation())

	confirm_context_button.text = "确认放置"
	confirm_context_button.disabled = not overlay.can_confirm()

	_context_syncing = false

func _rebuild_rotation_option(selected_rotation: int) -> void:
	if not is_instance_valid(rotation_option):
		return
	rotation_option.clear()
	for rot in [0, 90, 180, 270]:
		rotation_option.add_item("%d°" % rot)
		var idx := rotation_option.get_item_count() - 1
		rotation_option.set_item_metadata(idx, rot)
	_select_option_by_metadata_int(rotation_option, selected_rotation)

func _rebuild_house_number_option(available_numbers: Array[int], selected_house_number: int) -> void:
	if not is_instance_valid(house_number_option):
		return
	house_number_option.clear()
	house_number_option.add_item("请选择...")
	house_number_option.set_item_metadata(0, -1)
	var nums: Array[int] = []
	for n_val in available_numbers:
		nums.append(int(n_val))
	nums.sort()
	for n in nums:
		house_number_option.add_item(str(n))
		var idx := house_number_option.get_item_count() - 1
		house_number_option.set_item_metadata(idx, int(n))
	_select_option_by_metadata_int(house_number_option, int(selected_house_number))

func _rebuild_direction_option(selected_direction: String) -> void:
	if not is_instance_valid(direction_option):
		return
	direction_option.clear()
	for d in ["N", "E", "S", "W"]:
		direction_option.add_item(d)
		var idx := direction_option.get_item_count() - 1
		direction_option.set_item_metadata(idx, d)
	_select_option_by_metadata_string(direction_option, selected_direction)

func _rebuild_restaurant_option(restaurant_ids: Array[String], selected_restaurant_id: String) -> void:
	if not is_instance_valid(restaurant_option):
		return
	restaurant_option.clear()
	var ids := restaurant_ids.duplicate()
	ids.sort()
	for rid in ids:
		var s := str(rid).strip_edges()
		if s.is_empty():
			continue
		var label := s
		if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("get_restaurant_display_label"):
			var v = _context_overlay.call("get_restaurant_display_label", s)
			var t := str(v).strip_edges()
			if not t.is_empty():
				label = t
		restaurant_option.add_item(label)
		var idx := restaurant_option.get_item_count() - 1
		restaurant_option.set_item_metadata(idx, s)
	_select_option_by_metadata_string(restaurant_option, selected_restaurant_id)

func _rebuild_piece_option(piece_ids: Array[String], selected_piece_id: String) -> void:
	if not is_instance_valid(piece_option):
		return
	piece_option.clear()
	var ids := piece_ids.duplicate()
	if ids.is_empty():
		piece_option.add_item("请选择...")
		piece_option.set_item_metadata(0, "")
		piece_option.select(0)
		return

	for pid in ids:
		var s := str(pid).strip_edges()
		if s.is_empty():
			continue
		var label := s
		if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("get_piece_display_label"):
			var v = _context_overlay.call("get_piece_display_label", s)
			var t := str(v).strip_edges()
			if not t.is_empty():
				label = t
		piece_option.add_item(label)
		var idx := piece_option.get_item_count() - 1
		piece_option.set_item_metadata(idx, s)
	_select_option_by_metadata_string(piece_option, selected_piece_id)

func _rebuild_employee_option(employee_ids: Array[String], selected_employee_id: String) -> void:
	if not is_instance_valid(employee_option):
		return
	var ids: Array[String] = []
	var seen := {}
	for v in employee_ids:
		var s := str(v).strip_edges()
		if s.is_empty():
			continue
		if not seen.has(s):
			ids.append(s)
		seen[s] = int(seen.get(s, 0)) + 1
	ids.sort()

	var items: Array[Dictionary] = []
	for emp_id in ids:
		items.append({
			"id": emp_id,
			"employee_def": _get_employee_def_for_card(emp_id),
			"badge_text": "",
			"enabled": true,
		})

	var selected := str(selected_employee_id).strip_edges()
	if selected.is_empty() and not ids.is_empty():
		selected = str(ids[0])
	employee_option.set_items(items, selected)

func _select_option_by_metadata_int(option: OptionButton, desired: int) -> void:
	if option == null or not is_instance_valid(option):
		return
	for i in range(option.get_item_count()):
		if int(option.get_item_metadata(i)) == desired:
			option.select(i)
			return
	if option.get_item_count() > 0:
		option.select(0)

func _select_option_by_metadata_string(option: OptionButton, desired: String) -> void:
	if option == null or not is_instance_valid(option):
		return
	var d := str(desired).strip_edges()
	if not d.is_empty():
		for i in range(option.get_item_count()):
			if str(option.get_item_metadata(i)) == d:
				option.select(i)
				return
	if option.get_item_count() > 0:
		option.select(0)

func _call_context_overlay_method(method: StringName, args: Array = []) -> bool:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return false
	if not _context_overlay.has_method(method):
		return false
	_context_overlay.callv(method, args)
	return true

func _on_cancel_context_pressed() -> void:
	if not _call_context_overlay_method("request_cancel"):
		clear_context_overlay()
		return
	clear_context_overlay()

func _on_confirm_context_pressed() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		clear_context_overlay()
		return
	if confirm_context_button != null and confirm_context_button.disabled:
		return
	_call_context_overlay_method("request_confirm")
	if confirm_context_button != null:
		confirm_context_button.disabled = true

func _on_restaurant_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(restaurant_option):
		return
	var rid := str(restaurant_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_restaurant", [rid])

func _on_employee_option_selected(employee_type: String) -> void:
	if _context_syncing:
		return
	var emp_id := str(employee_type).strip_edges()
	_call_context_overlay_method("set_selected_employee", [emp_id])

func _on_piece_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(piece_option):
		return
	var pid := str(piece_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_piece", [pid])

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

func _on_rotation_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(rotation_option):
		return
	var rot := int(rotation_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_rotation", [rot])

func _on_house_number_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(house_number_option):
		return
	var n := int(house_number_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_house_number", [n])

func _on_direction_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(direction_option):
		return
	var d := str(direction_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_direction", [d])

func set_action_registry(registry) -> void:
	_action_registry = registry
	refresh()

func set_game_state(state: GameState) -> void:
	_game_state = state
	_update_title()
	refresh()

func set_current_player(player_id: int) -> void:
	# 联机模式：行动面板始终以“本地玩家”为上下文（避免显示他人的可用动作导致误导/无法继续）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		_current_player_id = int(NetContext.local_player_id)
	else:
		_current_player_id = player_id
	_update_title()
	refresh()

func _update_title() -> void:
	if not is_instance_valid(title_label):
		return

	var base := "可用动作"
	var suffix := ("（%s）" % _globally_disabled_reason) if _globally_disabled and not _globally_disabled_reason.is_empty() else ""

	# 联机模式：标题只展示“本地可操作性”，不展示玩家名（避免 hotseat 语义干扰）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		if _globally_disabled and _globally_disabled_reason == "联机：等待其他玩家操作":
			title_label.text = "等待其他玩家行动"
			return
		if _game_state != null:
			var phase := str(_game_state.phase)
			var local_pid := int(NetContext.local_player_id)
			if phase != DefsClass.PHASE_RESTRUCTURING and int(_game_state.get_current_player_id()) != local_pid:
				title_label.text = "等待其他玩家行动"
				return
		title_label.text = base + suffix
		return

	if _game_state == null or _current_player_id < 0:
		title_label.text = base + suffix
		return

	var name := Globals.get_player_name(_current_player_id) if Globals != null else ("玩家%d" % (_current_player_id + 1))
	title_label.text = "%s（行动: %s）%s" % [base, name, suffix]

func set_available_actions(action_ids: Array[String]) -> void:
	_rebuild_action_buttons(action_ids)

func set_action_enabled(action_id: String, enabled: bool) -> void:
	if _action_buttons.has(action_id):
		var btn: ActionButton = _action_buttons[action_id]
		if is_instance_valid(btn):
			btn.set_enabled(enabled)

func set_action_disabled_reason(action_id: String, reason: String) -> void:
	if _action_buttons.has(action_id):
		var btn: ActionButton = _action_buttons[action_id]
		if is_instance_valid(btn) and btn.has_method("set_disabled_reason"):
			btn.set_disabled_reason(reason)

func set_globally_disabled(reason: String) -> void:
	var r := str(reason).strip_edges()
	var was_disabled := _globally_disabled
	_globally_disabled = not r.is_empty()
	_globally_disabled_reason = r
	_update_title()
	_apply_global_disabled_state()
	# 重要：当从“全局禁用”恢复为可操作时，需要主动刷新一次以恢复各按钮的 enabled 状态。
	# 否则在联机模式中（先 refresh 再 set_globally_disabled），按钮可能会一直停留在 disabled=true。
	if was_disabled and not _globally_disabled:
		refresh()

func _apply_global_disabled_state() -> void:
	# 全局禁用用于“回放/查看历史”态，避免误操作产生时间线分支。
	if is_instance_valid(rewind_phase_button):
		rewind_phase_button.disabled = (_game_state == null) or _globally_disabled
	if is_instance_valid(confirm_context_button):
		confirm_context_button.disabled = _globally_disabled
	if is_instance_valid(cancel_context_button):
		cancel_context_button.disabled = _globally_disabled
	if is_instance_valid(restaurant_option):
		restaurant_option.disabled = _globally_disabled
	if is_instance_valid(rotation_option):
		rotation_option.disabled = _globally_disabled
	if is_instance_valid(house_number_option):
		house_number_option.disabled = _globally_disabled
	if is_instance_valid(direction_option):
		direction_option.disabled = _globally_disabled
	if is_instance_valid(employee_option) and employee_option.has_method("set_disabled"):
		employee_option.call("set_disabled", _globally_disabled)

	for aid in _action_buttons.keys():
		var btn_val = _action_buttons[aid]
		if not is_instance_valid(btn_val):
			continue
		var btn: ActionButton = btn_val
		if _globally_disabled:
			btn.set_enabled(false)
			btn.set_disabled_reason(_globally_disabled_reason)
		else:
			# 恢复由 refresh() 决定的 enabled 状态（这里不强行改回 true）。
			btn.set_disabled_reason("")

func refresh() -> void:
	if is_instance_valid(rewind_phase_button):
		rewind_phase_button.disabled = (_game_state == null)
	if _game_state == null:
		_rebuild_action_buttons([])
		return

	var available_ids: Array[String] = []
	var executable_ids: Array[String] = []
	var has_player_executable_info := false
	_mandatory_action_ids.clear()

	# 通过 ActionRegistry 获取可用动作
	if _action_registry != null and _action_registry.has_method("get_available_actions"):
		available_ids = _action_registry.get_available_actions(_game_state)
		if _action_registry.has_method("get_mandatory_actions"):
			for mid in _action_registry.get_mandatory_actions(_game_state):
				_mandatory_action_ids[str(mid)] = true
		if _current_player_id >= 0:
			# UI 侧需要“可启动”判定：允许先点击进入面板/选点，再补齐参数执行
			if _action_registry.has_method("get_player_initiatable_actions"):
				executable_ids = _action_registry.get_player_initiatable_actions(_game_state, _current_player_id)
				has_player_executable_info = true
			elif _action_registry.has_method("get_player_available_actions"):
				executable_ids = _action_registry.get_player_available_actions(_game_state, _current_player_id)
				has_player_executable_info = true
	else:
		# 备用：根据阶段硬编码部分常用动作
		available_ids = _get_fallback_actions(_game_state.phase, _game_state.sub_phase)

	# 隐藏内部动作
	var visible_ids: Array[String] = []
	for aid in available_ids:
		if HIDDEN_ACTION_IDS.has(aid):
			continue
		visible_ids.append(aid)

	var visible_executable: Array[String] = []
	for aid2 in executable_ids:
		if HIDDEN_ACTION_IDS.has(aid2):
			continue
		visible_executable.append(aid2)

	# Restructuring（hotseat 提交制）：隐藏“确认结束(skip)”，避免误解/误点造成卡住
	if _game_state.phase == DefsClass.PHASE_RESTRUCTURING and int(_game_state.round_number) > 1:
		var filtered_ids: Array[String] = []
		for aid_skip in visible_ids:
			if aid_skip == ActionIdsClass.SKIP:
				continue
			filtered_ids.append(aid_skip)
		visible_ids = filtered_ids

		var filtered_executable: Array[String] = []
		for aid_skip2 in visible_executable:
			if aid_skip2 == ActionIdsClass.SKIP:
				continue
			filtered_executable.append(aid_skip2)
		visible_executable = filtered_executable

	# Working：即使当前子阶段无任何可执行动作，也必须保留“跳过子阶段”，否则会造成软锁
	# （例如 Train 子阶段没有可培训来源/次数时，skip 被 validate 拒绝，只能用 skip_sub_phase 推进）。
	#
	# 但当 skip_sub_phase 实际效果等于“结束回合/结束工作阶段”（例如最后子阶段），不应再展示该按钮以避免误导。
	if visible_ids.has(ActionIdsClass.SKIP_SUB_PHASE) and not _should_show_skip_sub_phase_button():
		var filtered_skip_sub: Array[String] = []
		for v in visible_ids:
			if v == ActionIdsClass.SKIP_SUB_PHASE:
				continue
			filtered_skip_sub.append(v)
		visible_ids = filtered_skip_sub

		if has_player_executable_info:
			var filtered_exec_skip_sub: Array[String] = []
			for v2 in visible_executable:
				if v2 == ActionIdsClass.SKIP_SUB_PHASE:
					continue
				filtered_exec_skip_sub.append(v2)
			visible_executable = filtered_exec_skip_sub

	# P1：默认不再自动隐藏“玩家依赖动作”，改为灰显 + 原因（提升发现性）。
	# 但对少数“模块/里程碑动作”，若对当前玩家不可启动则直接隐藏（issue_tracker #78）。
	if has_player_executable_info:
		var filtered_visible: Array[String] = []
		for aid_hide in visible_ids:
			if _should_auto_hide_if_not_initiatable(aid_hide) and not visible_executable.has(aid_hide):
				continue
			filtered_visible.append(aid_hide)
		visible_ids = filtered_visible

	# 强制动作优先显示
	if not _mandatory_action_ids.is_empty():
		var ordered: Array[String] = []
		for aidm in visible_ids:
			if _mandatory_action_ids.has(aidm):
				ordered.append(aidm)
		for aidn in visible_ids:
			if not _mandatory_action_ids.has(aidn):
				ordered.append(aidn)
		visible_ids = ordered

	_rebuild_action_buttons(visible_ids)

	# 若能计算“当前玩家可执行动作”，则对不可执行动作做灰显，并写入原因
	if has_player_executable_info:
		for aid3 in visible_ids:
			var enabled := visible_executable.has(aid3)
			if (not enabled) and aid3 == ActionIdsClass.SKIP and _should_enable_skip_via_auto_mandatory_actions():
				enabled = true
			# 保留调试用强制推进按钮
			if aid3 == ActionIdsClass.ADVANCE_PHASE:
				enabled = true
			set_action_enabled(aid3, enabled)
			if enabled:
				set_action_disabled_reason(aid3, "")
			else:
				set_action_disabled_reason(aid3, _compute_disabled_reason(aid3))
	else:
		for aid4 in visible_ids:
			set_action_enabled(aid4, true)
			set_action_disabled_reason(aid4, "")

	_apply_global_disabled_state()

func _on_rewind_phase_pressed() -> void:
	# 作为“面板工具”而非游戏动作：由 GamePanelController 接管该 action_id，并触发时间线回退。
	clear_context_overlay()
	action_requested.emit("rewind_to_turn_start", {})

func _get_fallback_actions(phase: String, sub_phase: String) -> Array[String]:
	var result: Array[String] = [ActionIdsClass.SKIP]

	match phase:
		DefsClass.PHASE_SETUP:
			result.append("place_restaurant")
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			result.append("choose_turn_order")
		DefsClass.PHASE_WORKING:
			match sub_phase:
				DefsClass.SUB_PHASE_RECRUIT:
					result.append("recruit")
				DefsClass.SUB_PHASE_TRAIN:
					result.append("train")
				DefsClass.SUB_PHASE_MARKETING:
					result.append("initiate_marketing")
				DefsClass.SUB_PHASE_GET_FOOD:
					result.append("produce_food")
				DefsClass.SUB_PHASE_GET_DRINKS:
					result.append("procure_drinks")
				DefsClass.SUB_PHASE_PLACE_HOUSES:
					result.append("place_house")
					result.append("add_garden")
				DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
					result.append("place_restaurant")
					result.append("move_restaurant")
		DefsClass.PHASE_PAYDAY:
			result.append("fire")

	return result

func _sort_action_ids_for_display(action_ids: Array[String]) -> Array[String]:
	# 固定 UI 顺序：把“跳过子阶段/确认结束”放在列表底部，并保持 skip_sub_phase 在 skip 上方。
	# 其它动作保持相对顺序不变（避免无关面板顺序抖动）。
	var out: Array[String] = []
	var has_skip_sub := false
	var has_skip := false
	for v in action_ids:
		var aid := str(v)
		if aid == ActionIdsClass.SKIP_SUB_PHASE:
			has_skip_sub = true
			continue
		if aid == ActionIdsClass.SKIP:
			has_skip = true
			continue
		out.append(aid)

	if has_skip_sub:
		out.append(ActionIdsClass.SKIP_SUB_PHASE)
	if has_skip:
		out.append(ActionIdsClass.SKIP)
	return out

func _rebuild_action_buttons(action_ids: Array[String]) -> void:
	# 清除旧按钮
	UiRebuildHelpersClass.free_nodes_dict(_action_buttons)

	if items_container == null:
		return

	var ids := _sort_action_ids_for_display(action_ids)

	# 创建新按钮
	for action_id in ids:
		var btn := ActionButton.new()
		btn.action_id = action_id
		if action_id == ActionIdsClass.SKIP_SUB_PHASE:
			btn.display_name = _get_skip_sub_phase_display_name()
		else:
			var ex_name := _get_executor_display_name(action_id)
			btn.display_name = ex_name if not ex_name.is_empty() else ACTION_DISPLAY_NAMES.get(action_id, action_id)
		var ex_desc := _get_executor_description(action_id)
		btn.description = ex_desc if not ex_desc.is_empty() else ACTION_DESCRIPTIONS.get(action_id, "")
		btn.is_mandatory = _mandatory_action_ids.has(action_id)
		btn.action_clicked.connect(_on_action_clicked)
		items_container.add_child(btn)
		_action_buttons[action_id] = btn

func _on_action_clicked(action_id: String) -> void:
	action_requested.emit(action_id, {})


# === 内部类：动作按钮 ===
class ActionButton extends Button:
	signal action_clicked(action_id: String)

	var action_id: String = ""
	var display_name: String = ""
	var description: String = ""
	var disabled_reason: String = ""
	var is_mandatory: bool = false

	func _ready() -> void:
		_build_ui()
		pressed.connect(_on_pressed)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _build_ui() -> void:
		custom_minimum_size = Vector2(180, 36)
		var base := display_name if not display_name.is_empty() else action_id
		text = ("【强制】%s" % base) if is_mandatory else base
		var fs := 14
		if Globals != null:
			fs = int(Globals.get_scaled_font_size(14))
		add_theme_font_size_override("font_size", fs)

	func set_enabled(enabled: bool) -> void:
		disabled = not enabled
		modulate = Color(1, 1, 1, 1) if enabled else Color(0.5, 0.5, 0.5, 0.7)

	func set_disabled_reason(reason: String) -> void:
		disabled_reason = str(reason).strip_edges()

	func _on_pressed() -> void:
		action_clicked.emit(action_id)

	func _on_mouse_entered() -> void:
		if disabled and not disabled_reason.is_empty():
			tooltip_text = "不可用：%s" % disabled_reason
		elif not description.is_empty():
			tooltip_text = description

	func _on_mouse_exited() -> void:
		tooltip_text = ""

func _get_missing_mandatory_actions_for_current_player() -> Array[String]:
	if _game_state == null:
		return []
	if _current_player_id < 0:
		return []

	var player := _game_state.get_player(_current_player_id)
	var required: Array[String] = MandatoryActionsRulesClass.get_required_mandatory_actions(player)
	if required.is_empty():
		return []

	if not (_game_state.round_state is Dictionary):
		return []
	var mac_val = _game_state.round_state.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return []
	var mac: Dictionary = mac_val

	var completed_val = mac.get(_current_player_id, null)
	if completed_val == null and mac.has(str(_current_player_id)):
		completed_val = mac.get(str(_current_player_id), null)
	if not (completed_val is Array):
		return []
	var completed: Array = completed_val

	var missing: Array[String] = []
	for action_id in required:
		var aid := str(action_id).strip_edges()
		if aid.is_empty():
			continue
		if completed.has(aid):
			continue
		missing.append(aid)

	return missing

func _is_missing_params_error(r: Result) -> bool:
	if r == null or r.ok:
		return false
	return int(r.error_code) == Result.ErrorCode.MISSING_PARAMS

func _should_enable_skip_via_auto_mandatory_actions() -> bool:
	if _action_registry == null or _game_state == null:
		return false
	if _current_player_id < 0:
		return false
	if not _action_registry.has_method("get_executor"):
		return false

	# 仅当 skip 的失败原因是“缺少强制动作”时才考虑启用；其他原因（例如未到 Working 最后子阶段）不应放行。
	var skip_exec = _action_registry.get_executor(ActionIdsClass.SKIP)
	if skip_exec == null:
		return false
	var test_command := Command.create(ActionIdsClass.SKIP, _current_player_id)
	test_command.phase = _game_state.phase
	test_command.sub_phase = _game_state.sub_phase
	var r = skip_exec.validate(_game_state, test_command)
	if not (r is Result) or r.ok:
		return false

	var err := str(r.error).strip_edges()
	if err.find("强制动作") == -1:
		return false

	var missing := _get_missing_mandatory_actions_for_current_player()
	if missing.is_empty():
		return false
	for aid in missing:
		if not AUTO_MANDATORY_ACTION_IDS.has(aid):
			return false

	return true

func _compute_disabled_reason(action_id: String) -> String:
	if _action_registry == null or _game_state == null:
		return "当前不可用"
	if _current_player_id < 0:
		return "当前不可用"
	if not _action_registry.has_method("get_executor"):
		return "当前不可用"

	var executor = _action_registry.get_executor(action_id)
	if executor == null:
		return "未注册动作：%s" % action_id

	var test_command := Command.create(action_id, _current_player_id)
	test_command.phase = _game_state.phase
	test_command.sub_phase = _game_state.sub_phase

	var r = executor.validate(_game_state, test_command)
	if r is Result and not r.ok:
		var msg := str(r.error)
		if _is_missing_params_error(r) and executor.has_method("can_initiate"):
			var can = executor.can_initiate(_game_state, _current_player_id)
			if can is bool and not bool(can):
				return "条件不足，无法启动该动作"
		return msg

	return "当前不可用"
