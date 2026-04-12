# Game scene：教学目标解析器
# 负责：
# - 将教程步骤需要聚焦的 UI 节点解析成稳定 target 字典
# - 隔离主控制器对 left_panel / toolbar / modal / overlay 路径细节的依赖
class_name GameTutorialTargetsResolver
extends RefCounted

var _status_bar: Control = null
var _map_view: Control = null
var _action_panel: Control = null
var _left_panel: Control = null
var _toolbar: Control = null
var _turn_order_track: Control = null
var _get_restructuring_modal: Callable = Callable()
var _get_turn_order_modal: Callable = Callable()
var _get_active_context_overlay: Callable = Callable()
var _get_active_docked_panel: Callable = Callable()
var _get_employee_tree_panel: Callable = Callable()

const RECRUIT_PANEL_SCRIPT_PATH := "res://ui/components/recruit_panel/recruit_panel.gd"
const TRAIN_PANEL_SCRIPT_PATH := "res://ui/components/train_panel/train_panel.gd"
const MARKETING_PANEL_SCRIPT_PATH := "res://ui/components/marketing_panel/marketing_panel.gd"
const PRODUCTION_PANEL_SCRIPT_PATH := "res://ui/components/production_panel/production_panel.gd"

func _init(
	status_bar: Control,
	map_view: Control,
	action_panel: Control,
	left_panel: Control,
	toolbar: Control,
	turn_order_track: Control,
	get_restructuring_modal: Callable,
	get_turn_order_modal: Callable,
	get_active_context_overlay: Callable,
	get_active_docked_panel: Callable,
	get_employee_tree_panel: Callable = Callable()
) -> void:
	_status_bar = status_bar
	_map_view = map_view
	_action_panel = action_panel
	_left_panel = left_panel
	_toolbar = toolbar
	_turn_order_track = turn_order_track
	_get_restructuring_modal = get_restructuring_modal
	_get_turn_order_modal = get_turn_order_modal
	_get_active_context_overlay = get_active_context_overlay
	_get_active_docked_panel = get_active_docked_panel
	_get_employee_tree_panel = get_employee_tree_panel

func dispose() -> void:
	_status_bar = null
	_map_view = null
	_action_panel = null
	_left_panel = null
	_toolbar = null
	_turn_order_track = null
	_get_restructuring_modal = Callable()
	_get_turn_order_modal = Callable()
	_get_active_context_overlay = Callable()
	_get_active_docked_panel = Callable()
	_get_employee_tree_panel = Callable()

func get_targets() -> Dictionary:
	return {
		"status_bar": _status_bar,
		"map_view": _map_view,
		"action_panel": _action_panel,
		"action_panel_context_panel": _get_action_panel_tutorial_target("MarginContainer/VBoxContainer/ContextPanel"),
		"action_panel_rotation_row": _get_action_panel_tutorial_target("MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow"),
		"left_player_overview": _get_left_panel_tutorial_target("MarginContainer/MainVBox/RestaurantOverviewSection"),
		"left_inventory_section": _get_left_panel_tutorial_target("MarginContainer/MainVBox/DualColumnArea/LeftColumn/InventorySection"),
		"left_employee_scroll": _get_left_panel_tutorial_target("MarginContainer/MainVBox/DualColumnArea/LeftColumn/EmployeesScroll"),
		"left_milestones_section": _get_left_panel_tutorial_target("MarginContainer/MainVBox/DualColumnArea/RightColumn/MilestonesSection"),
		"left_activity_feed": _get_left_panel_tutorial_target("MarginContainer/MainVBox/ActivityFeed"),
		"toolbar": _toolbar,
		"turn_order_track": _turn_order_track,
		"toolbar_employee_tree_button": _get_toolbar_tutorial_target("EmployeeTreeButton"),
		"toolbar_log_button": _get_toolbar_tutorial_target("LogButton"),
		"toolbar_milestones_button": _get_toolbar_tutorial_target("MilestonesButton"),
		"toolbar_reserve_area_button": _get_toolbar_tutorial_target("ReserveAreaButton"),
		"toolbar_reserve_cards_button": _get_toolbar_tutorial_target("ReserveCardsButton"),
		"toolbar_distance_button": _get_toolbar_tutorial_target("DistanceToolButton"),
		"employee_tree_viewport": _get_employee_tree_tutorial_target("viewport"),
		"employee_tree_sample_card": _get_employee_tree_tutorial_target("sample_card"),
		"employee_tree_sample_card_header": _get_employee_tree_tutorial_target("sample_card_header"),
		"employee_tree_sample_card_remaining_badge": _get_employee_tree_tutorial_target("sample_card_remaining_badge"),
		"employee_tree_sample_card_entry_marker": _get_employee_tree_tutorial_target("sample_card_entry_marker"),
		"employee_tree_sample_card_range_marker": _get_employee_tree_tutorial_target("sample_card_range_marker"),
		"employee_tree_sample_card_salary_marker": _get_employee_tree_tutorial_target("sample_card_salary_marker"),
		"employee_tree_sample_card_description": _get_employee_tree_tutorial_target("sample_card_description"),
		"restructuring_player_buttons": _get_restructuring_tutorial_target("Panel/MarginContainer/VBoxContainer/PlayerRow/PlayerButtons"),
		"restructuring_hand_host": _get_restructuring_tutorial_target("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/HandHost"),
		"restructuring_company_host": _get_restructuring_tutorial_target("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/CompanyHost"),
		"restructuring_button_row": _get_restructuring_tutorial_target("Panel/MarginContainer/VBoxContainer/ButtonRow"),
		"turn_order_modal_selection_label": _get_turn_order_tutorial_target("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SelectionLabel"),
		"turn_order_modal_display": _get_turn_order_tutorial_target("Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/TurnOrderDisplay"),
		"active_context_overlay": _get_active_context_overlay_target(),
		"active_docked_panel": _get_active_docked_panel_target("", ""),
		"recruit_panel_items_container": _get_active_docked_panel_target(RECRUIT_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer"),
		"train_panel_sources_section": _get_active_docked_panel_target(TRAIN_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/TrainableSection"),
		"train_panel_targets_section": _get_active_docked_panel_target(TRAIN_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/PathSection"),
		"marketing_panel_type_section": _get_active_docked_panel_target(MARKETING_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TypeSection"),
		"marketing_panel_board_section": _get_active_docked_panel_target(MARKETING_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/BoardSection"),
		"marketing_panel_rotation_section": _get_active_docked_panel_target(MARKETING_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/RotationSection"),
		"marketing_panel_target_section": _get_active_docked_panel_target(MARKETING_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer/ContentVBox/TargetSection"),
		"production_panel_mode_label": _get_active_docked_panel_target(PRODUCTION_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ModeLabel"),
		"production_panel_products_container": _get_active_docked_panel_target(PRODUCTION_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/ScrollContainer/ProductsContainer"),
		"production_panel_summary_label": _get_active_docked_panel_target(PRODUCTION_PANEL_SCRIPT_PATH, "MarginContainer/VBoxContainer/SummaryLabel"),
	}

func _get_left_panel_tutorial_target(path: String) -> Control:
	if _left_panel == null or not is_instance_valid(_left_panel):
		return null
	var node := _left_panel.get_node_or_null(path)
	if node is Control:
		return node as Control
	return null

func _get_action_panel_tutorial_target(path: String) -> Control:
	if _action_panel == null or not is_instance_valid(_action_panel):
		return null
	var node := _action_panel.get_node_or_null(path)
	if node is Control:
		return node as Control
	return null

func _get_toolbar_tutorial_target(child_name: String) -> Control:
	if _toolbar == null or not is_instance_valid(_toolbar):
		return null
	var node := _toolbar.get_node_or_null(child_name)
	if node is Control:
		return node as Control
	return null

func _get_restructuring_tutorial_target(path: String) -> Control:
	if not _get_restructuring_modal.is_valid():
		return null
	var modal = _get_restructuring_modal.call()
	if not (modal is Control):
		return null
	var modal_control: Control = modal
	if not is_instance_valid(modal_control):
		return null
	var node := modal_control.get_node_or_null(path)
	if node is Control:
		return node as Control
	return null

func _get_turn_order_tutorial_target(path: String) -> Control:
	if not _get_turn_order_modal.is_valid():
		return null
	var modal = _get_turn_order_modal.call()
	if not (modal is Control):
		return null
	var modal_control: Control = modal
	if not is_instance_valid(modal_control):
		return null
	var node := modal_control.get_node_or_null(path)
	if node is Control:
		return node as Control
	return null

func _get_active_context_overlay_target() -> Control:
	if not _get_active_context_overlay.is_valid():
		return null
	var overlay = _get_active_context_overlay.call()
	if overlay is Control and is_instance_valid(overlay) and (overlay as Control).visible:
		return overlay as Control
	return null

func _get_active_docked_panel_target(expected_script_path: String, path: String) -> Control:
	if not _get_active_docked_panel.is_valid():
		return null
	var panel = _get_active_docked_panel.call()
	if not (panel is Control):
		return null
	var panel_control: Control = panel
	if not is_instance_valid(panel_control) or not panel_control.visible:
		return null
	if not expected_script_path.is_empty():
		var scr = panel_control.get_script()
		if scr == null or not (scr is Script):
			return null
		if str((scr as Script).resource_path) != expected_script_path:
			return null
	if path.is_empty():
		return panel_control
	var node := panel_control.get_node_or_null(path)
	if node is Control:
		return node as Control
	return null

func _get_employee_tree_tutorial_target(target_kind: String) -> Control:
	if not _get_employee_tree_panel.is_valid():
		return null
	var panel = _get_employee_tree_panel.call()
	if not (panel is Control):
		return null
	var panel_control: Control = panel
	if not is_instance_valid(panel_control) or not panel_control.visible:
		return null

	match str(target_kind):
		"viewport":
			if panel_control.has_method("get_tutorial_viewport"):
				var viewport = panel_control.call("get_tutorial_viewport")
				if viewport is Control and is_instance_valid(viewport):
					return viewport as Control
		"sample_card":
			if panel_control.has_method("get_tutorial_sample_card"):
				var sample = panel_control.call("get_tutorial_sample_card")
				if sample is Control and is_instance_valid(sample):
					return sample as Control
		"sample_card_header":
			return _get_employee_tree_sample_card_target(panel_control, "header")
		"sample_card_remaining_badge":
			return _get_employee_tree_sample_card_target(panel_control, "remaining_badge")
		"sample_card_entry_marker":
			return _get_employee_tree_sample_card_target(panel_control, "entry_marker")
		"sample_card_range_marker":
			return _get_employee_tree_sample_card_target(panel_control, "range_marker")
		"sample_card_salary_marker":
			return _get_employee_tree_sample_card_target(panel_control, "salary_marker")
		"sample_card_description":
			return _get_employee_tree_sample_card_target(panel_control, "description")
	return null

func _get_employee_tree_sample_card_target(panel_control: Control, target_kind: String) -> Control:
	if panel_control == null or not is_instance_valid(panel_control):
		return null
	if not panel_control.has_method("get_tutorial_sample_card_target"):
		return null
	var target = panel_control.call("get_tutorial_sample_card_target", target_kind)
	if target is Control and is_instance_valid(target):
		return target as Control
	return null
