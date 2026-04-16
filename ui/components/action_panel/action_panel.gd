# 动作面板组件
# 显示当前阶段可用的动作，支持触发执行
class_name ActionPanel
extends Control

signal action_requested(action_id: String, params: Dictionary)
signal guided_action_dismissed(action_id: String)

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const ContextControllerClass = preload("res://ui/components/action_panel/action_panel_context_controller.gd")
const ActionsControllerClass = preload("res://ui/components/action_panel/action_panel_actions_controller.gd")

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var guided_action_panel: Control = $MarginContainer/VBoxContainer/GuidedActionPanel
@onready var guided_action_title_label: Label = $MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/GuidedActionTitleLabel
@onready var guided_action_hint_label: Label = $MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/GuidedActionHintLabel
@onready var open_guided_action_button: Button = $MarginContainer/VBoxContainer/GuidedActionPanel/MarginContainer/VBoxContainer/OpenGuidedActionButton
@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ItemsContainer
@onready var context_panel: Control = $MarginContainer/VBoxContainer/ContextPanel
@onready var context_title_label: Label = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ContextTitleLabel
@onready var context_hint_label: Label = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ContextHintLabel
@onready var restaurant_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RestaurantRow
@onready var restaurant_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RestaurantRow/RestaurantOption
@onready var employee_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/EmployeeRow
@onready var employee_option: HFlowContainer = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/EmployeeRow/EmployeeOption
@onready var piece_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/PieceRow
@onready var piece_flow: HFlowContainer = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/PieceRow/PieceFlow
@onready var rotation_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow
@onready var rotate_left_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow/RotationControls/RotateLeftButton
@onready var rotation_value_label: Label = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow/RotationControls/RotationValueLabel
@onready var rotate_right_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/RotationRow/RotationControls/RotateRightButton
@onready var house_number_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/HouseNumberRow
@onready var house_number_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/HouseNumberRow/HouseNumberOption
@onready var direction_row: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/DirectionRow
@onready var direction_option: OptionButton = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/DirectionRow/DirectionOption
@onready var options_container: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer
@onready var custom_context_container: Control = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/OptionsContainer/CustomContextContainer
@onready var cancel_context_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ButtonsRow/CancelContextButton
@onready var skip_context_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ButtonsRow/SkipContextButton
@onready var confirm_context_button: Button = $MarginContainer/VBoxContainer/ContextPanel/MarginContainer/VBoxContainer/ButtonsRow/ConfirmContextButton
@onready var rewind_phase_button: Button = $MarginContainer/VBoxContainer/UtilityRow/RewindPhaseButton

var _action_registry = null  # ActionRegistry
var _game_state: GameState = null
var _current_player_id: int = -1
var _mandatory_action_ids: Dictionary = {}  # action_id -> true
var _context_controller = null
var _actions_controller = null
var _globally_disabled: bool = false
var _globally_disabled_reason: String = ""
var _visible_action_ids: Array[String] = []
var _visible_initiatable_action_ids: Array[String] = []
var _action_enabled: Dictionary = {} # action_id -> bool
var _action_disabled_reason: Dictionary = {} # action_id -> String
var _guided_action_id: String = ""
var _flow_confirm_end_visible: bool = false
var _flow_skip_step_visible: bool = false
var _external_action_block_reason_provider: Callable = Callable()

# 不在 UI 中展示的内部动作
const BASE_HIDDEN_ACTION_IDS := {
	ActionIdsClass.END_TURN: true,
	ActionIdsClass.ADVANCE_PHASE: true,
	# 定价类强制动作改为“准备离开 Working 时自动执行”，不在面板中展示。
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

func _get_hidden_action_ids() -> Dictionary:
	var hidden: Dictionary = BASE_HIDDEN_ACTION_IDS.duplicate()

	var engine = null
	if Globals != null and Globals.current_game_engine != null and Globals.current_game_engine is GameEngine:
		engine = Globals.current_game_engine
	if engine == null:
		return hidden

	var manifests_val = engine.get("module_manifests_v2") if engine != null else null
	var manifests: Dictionary = manifests_val if manifests_val is Dictionary else {}
	var plan: Array[String] = []
	if engine.has_method("get_module_plan_v2"):
		plan = Array(engine.get_module_plan_v2(), TYPE_STRING, "", null)

	for mid in plan:
		var manifest_val = manifests.get(mid, null)
		if not (manifest_val is ModuleManifest):
			continue
		var manifest: ModuleManifest = manifest_val
		var provides: Dictionary = manifest.provides
		var ui_val = provides.get("ui", null)
		if not (ui_val is Dictionary):
			continue
		var ui: Dictionary = ui_val
		var ids_val = ui.get("hidden_action_ids", null)
		if not (ids_val is Array):
			continue
		for aid in Array(ids_val):
			var s := str(aid).strip_edges()
			if not s.is_empty():
				hidden[s] = true

	return hidden

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
	UiStylesClass.apply_button_secondary(skip_context_button)
	UiStylesClass.apply_button_secondary(confirm_context_button)
	UiStylesClass.apply_button_secondary(cancel_context_button)
	UiStylesClass.apply_button_secondary(rewind_phase_button)
	_apply_context_visual_styles()
	_apply_guided_action_visual_styles()
	_connect_guided_action_signals()
	_sync_guided_action_placeholder()

func _build_ui() -> void:
	if items_container != null:
		items_container.add_theme_constant_override("separation", 4)
	_setup_context_ui()
	_setup_utility_ui()

func _apply_context_visual_styles() -> void:
	UiStylesClass.apply_panel_poster_alt(context_panel)
	_apply_label_style_recursive(options_container)
	UiStylesClass.apply_label_dark(context_title_label)
	UiStylesClass.apply_label_hint_dark(context_hint_label)
	UiStylesClass.apply_option_button_field(restaurant_option)
	UiStylesClass.apply_option_button_field(house_number_option)
	UiStylesClass.apply_option_button_field(direction_option)
	UiStylesClass.apply_button_secondary(rotate_left_button)
	UiStylesClass.apply_button_secondary(rotate_right_button)
	UiStylesClass.apply_label_dark(rotation_value_label)

func _apply_guided_action_visual_styles() -> void:
	UiStylesClass.apply_panel_poster_alt(guided_action_panel)
	UiStylesClass.apply_label_dark(guided_action_title_label)
	UiStylesClass.apply_label_hint_dark(guided_action_hint_label)
	UiStylesClass.apply_button_primary(open_guided_action_button)

func _connect_guided_action_signals() -> void:
	if is_instance_valid(open_guided_action_button):
		UiSignalHelpersClass.safe_connect(open_guided_action_button, "pressed", _on_open_guided_action_pressed)
	if is_instance_valid(context_panel):
		UiSignalHelpersClass.safe_connect(context_panel, "visibility_changed", _on_context_panel_visibility_changed)

func _on_context_panel_visibility_changed() -> void:
	_sync_guided_action_placeholder()

func _should_show_guided_action_placeholder() -> bool:
	if not _flow_confirm_end_visible:
		return false
	if not _guided_action_id.is_empty():
		return false
	if is_instance_valid(context_panel) and context_panel.visible:
		return false
	return true

func _sync_guided_action_placeholder() -> void:
	if not is_instance_valid(guided_action_panel):
		return

	var show := _should_show_guided_action_placeholder()
	guided_action_panel.visible = show
	if not show:
		if is_instance_valid(open_guided_action_button):
			open_guided_action_button.visible = true
		_sync_guided_action_button_state()
		return

	if is_instance_valid(guided_action_title_label):
		guided_action_title_label.text = "当前没有更多可执行动作"
	if is_instance_valid(guided_action_hint_label):
		guided_action_hint_label.text = "这表示当前阶段已经没有更多可执行动作，所以面板下方会显示“确认结束”。如果你接受当前结果，就点击“确认结束”继续流程；如果想重新安排本回合，也可以使用“回退到回合开始”。"
	if is_instance_valid(open_guided_action_button):
		open_guided_action_button.visible = false
	_sync_guided_action_button_state()

func _sync_guided_action_button_state() -> void:
	if not is_instance_valid(open_guided_action_button):
		return
	var aid := _guided_action_id.strip_edges()
	var enabled := (not aid.is_empty()) and get_action_enabled(aid)
	open_guided_action_button.disabled = not enabled

	var reason := ""
	if not enabled and not aid.is_empty():
		reason = get_action_disabled_reason(aid)
	elif not enabled and _globally_disabled and not _globally_disabled_reason.is_empty():
		reason = _globally_disabled_reason

	if open_guided_action_button.disabled and not reason.is_empty():
		open_guided_action_button.tooltip_text = "不可用：%s" % reason
	else:
		open_guided_action_button.tooltip_text = ""

func _on_open_guided_action_pressed() -> void:
	var aid := _guided_action_id.strip_edges()
	if aid.is_empty():
		return
	if not get_action_enabled(aid):
		return
	action_requested.emit(aid, {})

func _apply_label_style_recursive(root: Node) -> void:
	if root == null:
		return
	if root is Label:
		UiStylesClass.apply_label_dark(root)
	for child in root.get_children():
		_apply_label_style_recursive(child)

func _setup_utility_ui() -> void:
	if not is_instance_valid(rewind_phase_button):
		return
	UiSignalHelpersClass.safe_connect(rewind_phase_button, "pressed", _on_rewind_phase_pressed)

func _setup_context_ui() -> void:
	if not is_instance_valid(context_panel):
		return
	if _context_controller == null:
		_context_controller = ContextControllerClass.new()
	_context_controller.setup(self)
	_context_controller.set_action_registry(_action_registry)

func _ensure_actions_controller() -> void:
	if _actions_controller == null or not is_instance_valid(_actions_controller):
		_actions_controller = ActionsControllerClass.new()
	if _actions_controller != null and is_instance_valid(_actions_controller):
		_actions_controller.setup(self)

func bind_context_overlay(overlay: Node) -> void:
	if _context_controller == null:
		_setup_context_ui()
	if _context_controller == null:
		return
	_context_controller.bind_context_overlay(overlay)

func clear_context_overlay() -> void:
	if _context_controller == null:
		_setup_context_ui()
	if _context_controller == null:
		if is_instance_valid(context_panel):
			context_panel.visible = false
		return
	_context_controller.clear_context_overlay()

func set_action_registry(registry) -> void:
	_action_registry = registry
	if _context_controller != null:
		_context_controller.set_action_registry(_action_registry)
	refresh()

func set_external_action_block_reason_provider(provider: Callable) -> void:
	_external_action_block_reason_provider = provider
	refresh()

func set_map_skin(skin) -> void:
	if _context_controller == null:
		_setup_context_ui()
	if _context_controller == null:
		return
	_context_controller.set_map_skin(skin)

func set_game_state(state: GameState) -> void:
	_game_state = state
	_update_title()
	refresh()

func set_display_context(state: GameState, player_id: int) -> void:
	_game_state = state
	# 联机模式：行动面板始终以“本地玩家”为上下文（避免显示他人的可用动作导致误导/无法继续）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		_current_player_id = int(NetContext.local_player_id)
	else:
		_current_player_id = int(player_id)
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
		if _game_state != null and int(NetContext.local_player_id) >= 0:
			if not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(_game_state):
				title_label.text = "等待其他玩家行动"
				return
		title_label.text = base + suffix
		return

	if _game_state == null or _current_player_id < 0:
		title_label.text = base + suffix
		return

	title_label.text = base + suffix

func set_available_actions(action_ids: Array[String]) -> void:
	# 测试/调试入口：不依赖 GameState/ActionRegistry 的简化路径
	_ensure_actions_controller()
	if _actions_controller != null and is_instance_valid(_actions_controller):
		_actions_controller.set_available_actions(action_ids)

func set_action_enabled(action_id: String, enabled: bool) -> void:
	var aid := str(action_id)
	if aid.is_empty():
		return
	_action_enabled[aid] = bool(enabled)

func set_action_disabled_reason(action_id: String, reason: String) -> void:
	var aid := str(action_id)
	if aid.is_empty():
		return
	_action_disabled_reason[aid] = str(reason).strip_edges()

func get_guided_action_id() -> String:
	return _guided_action_id

func is_globally_disabled() -> bool:
	return _globally_disabled

func get_visible_action_ids() -> Array[String]:
	return _visible_action_ids.duplicate()

func get_flow_controls_config() -> Dictionary:
	var skip_sub_visible := _flow_skip_step_visible and _visible_action_ids.has(ActionIdsClass.SKIP_SUB_PHASE)
	var skip_visible := _flow_confirm_end_visible and _visible_action_ids.has(ActionIdsClass.SKIP)

	var skip_sub_enabled := get_action_enabled(ActionIdsClass.SKIP_SUB_PHASE)
	var skip_sub_reason := get_action_disabled_reason(ActionIdsClass.SKIP_SUB_PHASE)
	var skip_enabled := get_action_enabled(ActionIdsClass.SKIP)
	var skip_reason := get_action_disabled_reason(ActionIdsClass.SKIP)

	# rewind：无 state 或全局禁用时不可用（与旧 ActionPanel 一致）
	var rewind_enabled := (_game_state != null) and (not _globally_disabled)

	return {
		"confirm_end": {
			"visible": skip_visible,
			"text": ACTION_DISPLAY_NAMES.get(ActionIdsClass.SKIP, "确认结束"),
			"enabled": skip_enabled,
			"disabled_reason": skip_reason,
		},
		"skip_step": {
			"visible": skip_sub_visible,
			"text": _get_skip_sub_phase_display_name(),
			"enabled": skip_sub_enabled,
			"disabled_reason": skip_sub_reason,
		},
		"rewind": {
			"enabled": rewind_enabled,
		},
	}

func get_action_enabled(action_id: String) -> bool:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return false
	if _globally_disabled:
		return false
	return bool(_action_enabled.get(aid, false))

func get_action_disabled_reason(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return ""
	if _globally_disabled and not _globally_disabled_reason.is_empty():
		return _globally_disabled_reason
	return str(_action_disabled_reason.get(aid, "")).strip_edges()

func _get_external_action_block_reason(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return ""
	if not _external_action_block_reason_provider.is_valid():
		return ""
	var value = _external_action_block_reason_provider.call(aid, _game_state, _current_player_id)
	return str(value).strip_edges()

func get_action_display_name(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return ""
	if aid == ActionIdsClass.SKIP_SUB_PHASE:
		return _get_skip_sub_phase_display_name()
	var ex_name := _get_executor_display_name(aid)
	return ex_name if not ex_name.is_empty() else str(ACTION_DISPLAY_NAMES.get(aid, aid))

func get_action_description(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return ""
	var ex_desc := _get_executor_description(aid)
	return ex_desc if not ex_desc.is_empty() else str(ACTION_DESCRIPTIONS.get(aid, ""))

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
	if is_instance_valid(skip_context_button):
		skip_context_button.disabled = _globally_disabled
	if is_instance_valid(confirm_context_button):
		confirm_context_button.disabled = _globally_disabled
	if is_instance_valid(cancel_context_button):
		cancel_context_button.disabled = _globally_disabled
	if is_instance_valid(restaurant_option):
		restaurant_option.disabled = _globally_disabled
	if is_instance_valid(rotate_left_button):
		rotate_left_button.disabled = _globally_disabled
	if is_instance_valid(rotate_right_button):
		rotate_right_button.disabled = _globally_disabled
	if is_instance_valid(house_number_option):
		house_number_option.disabled = _globally_disabled
	if is_instance_valid(direction_option):
		direction_option.disabled = _globally_disabled
	if is_instance_valid(employee_option) and employee_option.has_method("set_disabled"):
		employee_option.call("set_disabled", _globally_disabled)
	if is_instance_valid(piece_flow):
		for child in piece_flow.get_children():
			if child is BaseButton:
				(child as BaseButton).disabled = _globally_disabled
	_sync_guided_action_button_state()
	if _actions_controller != null and is_instance_valid(_actions_controller) and _actions_controller.has_method("sync_rendered_action_buttons"):
		_actions_controller.call("sync_rendered_action_buttons")

func refresh() -> void:
	_ensure_actions_controller()
	if _actions_controller != null and is_instance_valid(_actions_controller):
		_actions_controller.refresh()

func _on_rewind_phase_pressed() -> void:
	# 作为“面板工具”而非游戏动作：由 GamePanelController 接管该 action_id，并触发时间线回退。
	clear_context_overlay()
	action_requested.emit("rewind_to_turn_start", {})
