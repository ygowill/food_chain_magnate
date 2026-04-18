# Game scene：阶段面板/交互协调器
# 负责：
# - ActionPanel -> 行为分派（执行命令 / 打开面板）
# - 基础 UI 组件数据绑定（玩家面板/顺序轨/库存/手牌/公司结构）
# - 阶段面板/覆盖层生命周期委托（见 game_panel_*）
class_name GamePanelController
extends RefCounted

const WorkingPanelsClass = preload("res://ui/scenes/game/panel/working/panels.gd")
const MarketingPanelsClass = preload("res://ui/scenes/game/panel/marketing_panels.gd")
const PlacementOverlaysClass = preload("res://ui/scenes/game/panel/placement_overlays.gd")
const EndPanelsClass = preload("res://ui/scenes/game/panel/end_panels.gd")
const RestructuringControllerClass = preload("res://ui/scenes/game/panel/restructuring_controller.gd")
const ModalsControllerClass = preload("res://ui/scenes/game/panel/modals_controller.gd")
const ViewsControllerClass = preload("res://ui/scenes/game/panel/views_controller.gd")
const PopupLayoutControllerClass = preload("res://ui/scenes/game/panel/popup_layout_controller.gd")
const UiComponentsBinderClass = preload("res://ui/scenes/game/panel/ui_components_binder.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")

const _GUIDED_ACTION_DOCK_SCRIPT_PATHS := {
	"res://ui/components/recruit_panel/recruit_panel.gd": true,
	"res://ui/components/train_panel/train_panel.gd": true,
	"res://ui/components/marketing_panel/marketing_panel.gd": true,
	"res://ui/components/production_panel/production_panel.gd": true,
}

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _refresh_ui: Callable

var _working_panels = null
var _marketing_panels = null
var _placement_overlays = null
var _end_panels = null

var _restructuring_controller = null
var _modals_controller = null
var _views_controller = null
var _ui_components_binder = null
var _popup_layout_controller = null

var _view_player_id: int = -1
var _last_guided_action_id: String = ""
var _action_panel_context_bound: bool = false
var _last_action_panel_context_overlay = null

func _init(scene, map_controller, overlay_controller, execute_command: Callable, refresh_ui: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_refresh_ui = refresh_ui
	# 联机模式：默认视角锁定到本地玩家（避免默认跟随 current_player 导致“重组拖拽不了自己”的体验）
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and NetContext.local_player_id >= 0:
		_view_player_id = int(NetContext.local_player_id)

	_popup_layout_controller = PopupLayoutControllerClass.new(_scene)
	var hide_all := Callable(self, "_hide_all_phase_panels")
	var center_popup := Callable(_popup_layout_controller, "center_popup")

	_working_panels = WorkingPanelsClass.new(_scene, _map_controller, _execute_command, hide_all, center_popup, _overlay_controller)
	_marketing_panels = MarketingPanelsClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all, center_popup)
	_placement_overlays = PlacementOverlaysClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all)
	_end_panels = EndPanelsClass.new(
		_scene,
		_overlay_controller,
		_execute_command,
		hide_all,
		center_popup,
		_refresh_ui,
		{
			"net_client": NetClient,
			"scene_manager": SceneManager,
			"globals": Globals,
		}
	)
	_restructuring_controller = RestructuringControllerClass.new(
		_scene,
		_execute_command,
		Callable(self, "get_view_player_id"),
		Callable(self, "_on_view_player_selected")
	)
	_modals_controller = ModalsControllerClass.new(_scene, _execute_command)
	_views_controller = ViewsControllerClass.new(_scene)
	_ui_components_binder = UiComponentsBinderClass.new(self)

func connect_signals(action_panel, action_flow_controls, turn_order_track, hand_area, company_structure) -> void:
	UiSignalHelpersClass.safe_connect(action_panel, "action_requested", on_action_requested)
	UiSignalHelpersClass.safe_connect(action_flow_controls, "action_requested", on_action_requested)
	UiSignalHelpersClass.safe_connect(turn_order_track, "position_selected", _on_turn_order_position_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "cards_selected", _on_hand_cards_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "card_dropped", _on_hand_card_dropped)
	UiSignalHelpersClass.safe_connect(hand_area, "card_double_clicked", _on_hand_card_double_clicked)
	UiSignalHelpersClass.safe_connect(company_structure, "structure_changed", _on_company_structure_changed)
	UiSignalHelpersClass.safe_connect(company_structure, "card_dropped", _on_hand_card_dropped)
	UiSignalHelpersClass.safe_connect(company_structure, "card_double_clicked", _on_company_structure_card_double_clicked)

	# 查看玩家（view_player）
	if _scene != null:
		UiSignalHelpersClass.safe_connect(_scene.player_panel, "player_selected", _on_view_player_selected)
		UiSignalHelpersClass.safe_connect(_scene.left_panel, "milestones_requested", show_milestone_panel)

func reset_bank_break_tracking(state: GameState) -> void:
	if _end_panels != null:
		_end_panels.reset_bank_break_tracking(state)

func show_milestone_panel() -> void:
	if _scene == null:
		return
	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return
	var state: GameState = engine.get_state()
	if state == null:
		return
	if _views_controller != null:
		_views_controller.show_milestone_full_screen_view(state, _get_current_map_skin())

func show_reserve_area_panel() -> void:
	if _scene == null:
		return
	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return
	var state: GameState = engine.get_state()
	if state == null:
		return
	if _views_controller != null:
		_views_controller.show_reserve_area_full_screen_view(state, _get_current_map_skin())

func show_reserve_cards_overview(focus_player_id: int = -1) -> void:
	if _scene == null:
		return
	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return
	var state: GameState = engine.get_state()
	if state == null:
		return
	if not can_open_reserve_cards_overview(state):
		return
	if _views_controller != null:
		_views_controller.show_reserve_cards_full_screen_view(state, focus_player_id)

func can_open_reserve_cards_overview(state: GameState = null) -> bool:
	var live_state := state
	if live_state == null:
		if _scene == null:
			return false
		var engine = _scene.get("game_engine")
		if engine == null or not (engine is GameEngine):
			return false
		live_state = engine.get_state()
	if live_state == null:
		return false
	return ReserveCardsViewDataClass.viewer_has_overview_access(live_state)

func show_payday_panel() -> void:
	if _end_panels != null:
		_end_panels.show_payday_panel()

func toggle_employee_tree() -> void:
	if _scene == null:
		return
	if _views_controller == null:
		return
	if _views_controller.is_employee_tree_visible():
		_views_controller.hide_employee_tree()
		if _refresh_ui.is_valid():
			_refresh_ui.call()
		return

	_hide_all_phase_panels(true, true)
	_views_controller.show_employee_tree()
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func get_view_player_id() -> int:
	return _view_player_id

func _get_effective_view_player_id(state: GameState, requested_view_id: int) -> int:
	if state == null:
		return requested_view_id
	if requested_view_id >= 0 and requested_view_id < state.players.size():
		return requested_view_id
	return state.get_current_player_id()

func _on_view_player_selected(player_id: int) -> void:
	# Restructuring 隐私规则：
	# - Online：禁止查看其他玩家（仅显示提交进度）
	# - Hotseat：已提交玩家不可再查看
	if _scene != null and _scene.game_engine != null:
		var state: GameState = _scene.game_engine.get_state()
		if state != null and str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
			if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
				var local_pid := int(NetContext.local_player_id)
				if local_pid < 0 or player_id != local_pid:
					return
			else:
				if _restructuring_controller != null and _restructuring_controller.is_player_submitted(state, player_id):
					return

	_view_player_id = player_id
	if _refresh_ui.is_valid():
		_refresh_ui.call()

func hide_all() -> void:
	_hide_all_phase_panels()

func hide_all_keep_selection() -> void:
	_hide_all_phase_panels(true)

func get_active_context_overlay():
	if _placement_overlays == null:
		return null
	if _placement_overlays.has_method("get_active_context_overlay"):
		return _placement_overlays.call("get_active_context_overlay")
	if is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
		return _placement_overlays.restaurant_placement_overlay
	if is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
		return _placement_overlays.house_placement_overlay
	if is_instance_valid(_placement_overlays.piece_placement_overlay) and _placement_overlays.piece_placement_overlay.visible:
		return _placement_overlays.piece_placement_overlay
	return null

func hide_non_modal_action_ui_for_waiting() -> void:
	# 联机等待他人操作：仅清理“本地动作相关 UI/选点高亮”，不关闭等待类模态。
	if _working_panels != null:
		_working_panels.hide()
	if _end_panels != null:
		_end_panels.hide()
	if _marketing_panels != null:
		_marketing_panels.hide()
	if _placement_overlays != null:
		_placement_overlays.hide()

	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()
		_overlay_controller.hide_marketing_range_overlay()
	if _map_controller != null:
		_map_controller.clear_selection()

	_sync_action_panel_context()
	if _scene != null and _scene.has_method("_sync_right_panel_docked_view"):
		_scene.call_deferred("_sync_right_panel_docked_view")

func dispose() -> void:
	_execute_command = Callable()
	_refresh_ui = Callable()

	_working_panels = null
	_marketing_panels = null
	if _placement_overlays != null and _placement_overlays.has_method("dispose"):
		_placement_overlays.dispose()
	_placement_overlays = null
	if _end_panels != null and _end_panels.has_method("dispose"):
		_end_panels.dispose()
	_end_panels = null

	if _restructuring_controller != null and _restructuring_controller.has_method("dispose"):
		_restructuring_controller.dispose()
	_restructuring_controller = null
	if _modals_controller != null and _modals_controller.has_method("dispose"):
		_modals_controller.dispose()
	_modals_controller = null
	if _views_controller != null and _views_controller.has_method("dispose"):
		_views_controller.dispose()
	_views_controller = null
	if _ui_components_binder != null and _ui_components_binder.has_method("dispose"):
		_ui_components_binder.dispose()
	_ui_components_binder = null
	if _popup_layout_controller != null and _popup_layout_controller.has_method("dispose"):
		_popup_layout_controller.dispose()
	_popup_layout_controller = null
	_action_panel_context_bound = false
	_last_action_panel_context_overlay = null

	_scene = null
	_map_controller = null
	_overlay_controller = null

func has_open_modal_ui() -> bool:
	if has_blocking_modal_ui():
		return true
	if _views_controller != null and _views_controller.has_method("has_open_view_ui"):
		if bool(_views_controller.has_open_view_ui()):
			return true
	return false

func has_blocking_modal_ui() -> bool:
	if _restructuring_controller != null and _restructuring_controller.has_method("has_open_modal_ui"):
		if bool(_restructuring_controller.has_open_modal_ui()):
			return true
	if _modals_controller != null and _modals_controller.has_method("has_open_modal_ui"):
		if bool(_modals_controller.has_open_modal_ui()):
			return true
	return false

func hide_modal_ui() -> void:
	if _modals_controller != null and _modals_controller.has_method("hide"):
		_modals_controller.hide()
	if _restructuring_controller != null and _restructuring_controller.has_method("hide_modal"):
		_restructuring_controller.hide_modal()
	if _views_controller != null and _views_controller.has_method("hide"):
		_views_controller.hide()

func hide_top_overlays_if_open() -> bool:
	# 仅关闭“覆盖全屏的浏览视图”（例如里程碑/保留区），避免 ESC 误触发 hide_all() 影响底层面板状态。
	if _views_controller != null and _views_controller.has_method("hide_top_overlays_if_open"):
		return bool(_views_controller.hide_top_overlays_if_open())
	return false

func has_open_phase_ui() -> bool:
	if has_open_modal_ui():
		return true

	# Working panels
	if _working_panels != null:
		if is_instance_valid(_working_panels.recruit_panel) and _working_panels.recruit_panel.visible:
			return true
		if is_instance_valid(_working_panels.train_panel) and _working_panels.train_panel.visible:
			return true
		if is_instance_valid(_working_panels.price_panel) and _working_panels.price_panel.visible:
			return true
		if is_instance_valid(_working_panels.production_panel) and _working_panels.production_panel.visible:
			return true
		if is_instance_valid(_working_panels.milestone_panel) and _working_panels.milestone_panel.visible:
			return true

	# Marketing
	if _marketing_panels != null:
		if is_instance_valid(_marketing_panels.marketing_panel) and _marketing_panels.marketing_panel.visible:
			return true

	# Placement overlays
	if _placement_overlays != null:
		if is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
			return true
		if is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
			return true

	# Payday panel（不包含银行破产/游戏结束等系统强提示）
	if _end_panels != null:
		if is_instance_valid(_end_panels.payday_panel) and _end_panels.payday_panel.visible:
			return true

	return false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_update_ui_components(state)
	_sync_reserve_cards_overview_access(state)
	if _working_panels != null:
		_working_panels.sync(state, force_full_refresh)
	if _marketing_panels != null:
		_marketing_panels.sync(state, force_full_refresh)
	if _placement_overlays != null:
		_placement_overlays.sync(state, force_full_refresh)
	if _end_panels != null:
		_end_panels.sync(state, force_full_refresh)
	_sync_modals(state)
	_sync_action_panel_context(force_full_refresh)
	_sync_action_flow_controls()
	_hide_open_guided_action_panels_if_not_initiatable(state)
	_auto_open_guided_action_ui(state)

func get_milestone_full_screen_view():
	if _views_controller == null:
		return null
	return _views_controller.get_milestone_full_screen_view()

func get_reserve_area_full_screen_view():
	if _views_controller == null:
		return null
	return _views_controller.get_reserve_area_full_screen_view()

func get_reserve_cards_full_screen_view():
	if _views_controller == null:
		return null
	return _views_controller.get_reserve_cards_full_screen_view()

func get_employee_tree_panel():
	if _views_controller == null:
		return null
	return _views_controller.get_employee_tree_panel()

func peek_employee_tree_panel():
	if _views_controller == null:
		return null
	if _views_controller.has_method("peek_employee_tree_panel"):
		return _views_controller.peek_employee_tree_panel()
	return null

func get_restructuring_modal():
	if _restructuring_controller == null:
		return null
	if _restructuring_controller.has_method("get_modal"):
		return _restructuring_controller.get_modal()
	return null

func get_turn_order_modal():
	if _modals_controller == null:
		return null
	if _modals_controller.has_method("get_turn_order_modal"):
		return _modals_controller.get_turn_order_modal()
	return null

func get_active_docked_panel():
	return _get_active_right_panel_docked_panel()

func _sync_reserve_cards_overview_access(state: GameState) -> void:
	var can_open := can_open_reserve_cards_overview(state)
	if _scene != null:
		var btn = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/ToolBar/ReserveCardsButton")
		if btn is Button:
			var button: Button = btn
			button.visible = true
			button.disabled = not can_open
	if not can_open and _views_controller != null and _views_controller.has_method("hide_reserve_cards_full_screen_view"):
		_views_controller.hide_reserve_cards_full_screen_view()

func _sync_action_panel_context(force_refresh: bool = false) -> void:
	if _scene == null:
		return
	if not is_instance_valid(_scene.action_panel):
		return

	var overlay = null
	if _placement_overlays != null:
		if _placement_overlays.has_method("get_active_context_overlay"):
			overlay = _placement_overlays.call("get_active_context_overlay")
		else:
			if is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
				overlay = _placement_overlays.restaurant_placement_overlay
			elif is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
				overlay = _placement_overlays.house_placement_overlay
			elif is_instance_valid(_placement_overlays.piece_placement_overlay) and _placement_overlays.piece_placement_overlay.visible:
				overlay = _placement_overlays.piece_placement_overlay

	var next_overlay = overlay if (overlay != null and is_instance_valid(overlay)) else null
	if not bool(force_refresh):
		if next_overlay != null and _action_panel_context_bound and next_overlay == _last_action_panel_context_overlay:
			return
		if next_overlay == null and not _action_panel_context_bound:
			return

	if next_overlay != null:
		if _scene.action_panel.has_method("bind_context_overlay"):
			_scene.action_panel.call("bind_context_overlay", next_overlay)
		_action_panel_context_bound = true
		_last_action_panel_context_overlay = next_overlay
	else:
		if _scene.action_panel.has_method("clear_context_overlay"):
			_scene.action_panel.call("clear_context_overlay")
		_action_panel_context_bound = false
		_last_action_panel_context_overlay = null

func _sync_action_flow_controls() -> void:
	if _scene == null:
		return
	if not is_instance_valid(_scene.action_panel):
		return
	if not is_instance_valid(_scene.action_flow_controls):
		return
	if not (_scene.action_panel.has_method("get_flow_controls_config")):
		return
	if not (_scene.action_flow_controls.has_method("apply_flow_config")):
		return

	var cfg_val = _scene.action_panel.call("get_flow_controls_config")
	if cfg_val is Dictionary:
		var cfg := Dictionary(cfg_val)
		if _should_hide_action_flow_controls_skip_step():
			var ss_val = cfg.get("skip_step", null)
			if ss_val is Dictionary:
				var ss := Dictionary(ss_val)
				ss["visible"] = false
				cfg["skip_step"] = ss
		_scene.action_flow_controls.call("apply_flow_config", cfg)

func _should_hide_action_flow_controls_skip_step() -> bool:
	# 当“跳过子阶段”已在动作面板 UI 内展示时，隐藏 ActionFlowControls 的同款按钮，避免重复/层级感。
	# - 右侧 dock 的 guided action 面板：跳过在 FooterRow（左），确认在 FooterRow（右）
	if _is_skip_sub_phase_shown_in_right_panel_footer():
		return true

	var active_docked := _get_active_right_panel_docked_panel()
	if active_docked != null and _is_guided_action_dock_panel(active_docked):
		return true

	return false

func _is_skip_sub_phase_shown_in_right_panel_footer() -> bool:
	if _scene == null:
		return false
	var btn = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/FooterRow/SecondaryButton")
	if btn == null or not (btn is Button):
		return false
	var b: Button = btn
	if not b.visible:
		return false
	if not b.has_meta("action_id"):
		return false
	return str(b.get_meta("action_id")).strip_edges() == "skip_sub_phase"

func _has_active_context_overlay() -> bool:
	var overlay = null
	if _placement_overlays != null:
		if _placement_overlays.has_method("get_active_context_overlay"):
			overlay = _placement_overlays.call("get_active_context_overlay")
		else:
			if is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
				overlay = _placement_overlays.restaurant_placement_overlay
			elif is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
				overlay = _placement_overlays.house_placement_overlay
			elif is_instance_valid(_placement_overlays.piece_placement_overlay) and _placement_overlays.piece_placement_overlay.visible:
				overlay = _placement_overlays.piece_placement_overlay
	return overlay != null and is_instance_valid(overlay)

func _get_active_right_panel_docked_panel() -> Control:
	if _scene == null:
		return null
	var dock_host = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DockHost")
	if dock_host == null or not is_instance_valid(dock_host):
		return null
	for ch in dock_host.get_children():
		if ch is Control and (ch as Control).visible:
			return ch as Control
	return null

func _is_guided_action_dock_panel(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	var scr = panel.get_script()
	if scr == null or not (scr is Script):
		return false
	return _GUIDED_ACTION_DOCK_SCRIPT_PATHS.has(str((scr as Script).resource_path))

func _auto_open_guided_action_ui(state: GameState) -> void:
	if state == null:
		return
	if _scene == null:
		return
	if not is_instance_valid(_scene.action_panel):
		return
	if not _scene.action_panel.has_method("get_guided_action_id"):
		return
	if _scene.action_panel.has_method("is_globally_disabled") and bool(_scene.action_panel.call("is_globally_disabled")):
		return
	# 有阻塞弹窗/浏览视图时不强制弹出动作面板，避免打断玩家
	if has_open_modal_ui():
		return

	var guided := str(_scene.action_panel.call("get_guided_action_id")).strip_edges()
	if guided.is_empty():
		_last_guided_action_id = ""
		return

	# 右侧 dock 里若已有“非日志”的可见面板，不要抢占焦点自动弹出动作 UI。
	# 但日志面板不应阻塞强制动作页（例如 Payday 的 fire），否则联机等待切回本地回合时会软锁在日志里。
	if _has_visible_right_panel_docked_panel(true):
		return

	# 优先：若当前动作 UI 已打开且仍为该动作，不重复 show（避免 hide_all/选点被重置）
	if guided == _last_guided_action_id and _is_action_ui_open_for_action_id(guided):
		return

	_open_action_ui_for_action_id(guided)
	_last_guided_action_id = guided
	# 打开动作 UI 会改变“跳过/确认结束”按钮的承载位置（FooterRow / ContextPanel）；
	# 立即同步一次 ActionFlowControls，避免出现“下面还残留一个跳过按钮”的重复层级感。
	_sync_action_flow_controls()

func _hide_open_guided_action_panels_if_not_initiatable(state: GameState) -> void:
	if _scene == null or state == null:
		return
	if not is_instance_valid(_scene.action_panel):
		return
	if not _scene.action_panel.has_method("get_action_enabled"):
		return

	# Recruit / Train / Marketing：若动作不可启动则隐藏面板（避免“无可用员工/无可选项”时仍占屏）
	if _working_panels != null:
		if is_instance_valid(_working_panels.recruit_panel) and _working_panels.recruit_panel.visible:
			if not bool(_scene.action_panel.call("get_action_enabled", "recruit")):
				_working_panels.recruit_panel.visible = false
		if is_instance_valid(_working_panels.train_panel) and _working_panels.train_panel.visible:
			if not bool(_scene.action_panel.call("get_action_enabled", "train")):
				_working_panels.train_panel.visible = false
		if is_instance_valid(_working_panels.production_panel) and _working_panels.production_panel.visible:
			var aid := ""
			if str(state.sub_phase) == DefsClass.SUB_PHASE_GET_FOOD:
				aid = "produce_food"
			elif str(state.sub_phase) == DefsClass.SUB_PHASE_GET_DRINKS:
				aid = "procure_drinks"
			if not aid.is_empty() and not bool(_scene.action_panel.call("get_action_enabled", aid)):
				_working_panels.production_panel.visible = false

	if _marketing_panels != null:
		if is_instance_valid(_marketing_panels.marketing_panel) and _marketing_panels.marketing_panel.visible:
			if not bool(_scene.action_panel.call("get_action_enabled", "initiate_marketing")):
				_marketing_panels.marketing_panel.visible = false

func _has_visible_right_panel_docked_panel(ignore_game_log: bool = false) -> bool:
	if _scene == null:
		return false
	var dock_host = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DockHost")
	if dock_host == null or not is_instance_valid(dock_host):
		return false
	var game_log_panel = _get_game_log_panel()
	for ch in dock_host.get_children():
		if not (ch is Control):
			continue
		var ctrl: Control = ch
		if ignore_game_log and ctrl == game_log_panel:
			continue
		if ctrl.visible:
			return true
	return false

func _get_game_log_panel() -> Control:
	if _scene == null:
		return null
	var panel = _scene.get("game_log_panel")
	if panel is Control and is_instance_valid(panel):
		return panel
	return null

func _is_action_ui_open_for_action_id(action_id: String) -> bool:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return false

	# Working panels（右侧 dock）
	if _working_panels != null:
		if aid == "recruit" and is_instance_valid(_working_panels.recruit_panel) and _working_panels.recruit_panel.visible:
			return true
		if aid == "train" and is_instance_valid(_working_panels.train_panel) and _working_panels.train_panel.visible:
			return true
		if (aid == "produce_food" or aid == "procure_drinks") and is_instance_valid(_working_panels.production_panel) and _working_panels.production_panel.visible:
			return true
		# Price 类动作不在 ActionPanel 中展示（auto mandatory），但为稳健起见仍保留判断
		if (aid == "set_price" or aid == "set_discount" or aid == "set_luxury_price") and is_instance_valid(_working_panels.price_panel) and _working_panels.price_panel.visible:
			return true

	# Marketing（右侧 dock）
	if _marketing_panels != null:
		if aid == "initiate_marketing" and is_instance_valid(_marketing_panels.marketing_panel) and _marketing_panels.marketing_panel.visible:
			return true

	# Payday（右侧 dock）
	if _end_panels != null:
		if aid == "fire" and is_instance_valid(_end_panels.payday_panel) and _end_panels.payday_panel.visible:
			return true

	# Placement overlays（地图覆盖层 + ActionPanel ContextPanel）
	if _placement_overlays != null:
		if (aid == "place_restaurant" or aid == "move_restaurant") and is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
			if _placement_overlays.restaurant_placement_overlay.has_method("get_mode"):
				return str(_placement_overlays.restaurant_placement_overlay.get_mode()) == aid
			return true
		if (aid == "place_house" or aid == "add_garden") and is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
			if _placement_overlays.house_placement_overlay.has_method("get_mode"):
				return str(_placement_overlays.house_placement_overlay.get_mode()) == aid
			return true
		# piece placement / module overlays：无法精确判断，若有 active context overlay 则认为已打开
		if _placement_overlays.has_method("get_active_context_overlay"):
			var ov = _placement_overlays.get_active_context_overlay()
			if ov != null and is_instance_valid(ov):
				if ov.has_method("get_mode") and str(ov.get_mode()) == aid:
					return true

	return false

func _open_action_ui_for_action_id(action_id: String) -> void:
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return

	# P0/P1：打开 UI（不自动执行命令）
	match aid:
		"choose_turn_order":
			if _scene != null and _scene.game_engine != null and _modals_controller != null:
				var state: GameState = _scene.game_engine.get_state()
				if state != null:
					_modals_controller.show_turn_order_modal_for_state(state)
			return

		"recruit":
			if _working_panels != null:
				_working_panels.show_recruit_panel()
			return
		"train":
			if _working_panels != null:
				_working_panels.show_train_panel()
			return
		"initiate_marketing":
			if _marketing_panels != null:
				_marketing_panels.show_marketing_panel()
			return
		"produce_food":
			if _working_panels != null:
				_working_panels.show_production_panel("food")
			return
		"procure_drinks":
			if _working_panels != null:
				_working_panels.show_production_panel("drinks")
			return
		"fire":
			if _end_panels != null:
				_end_panels.show_payday_panel()
			return
		"place_restaurant", "move_restaurant":
			if _placement_overlays != null:
				_placement_overlays.show_restaurant_placement(aid, {})
				_sync_action_panel_context()
			return
		"place_house", "add_garden":
			if _placement_overlays != null:
				_placement_overlays.show_house_placement(aid, {})
				_sync_action_panel_context()
			return
		_:
			# 模组动作：尝试打开 overlay / piece placement；若无法处理则不自动执行（避免无意中提交命令）。
			if _placement_overlays != null and _placement_overlays.has_method("try_show_module_action_overlay"):
				if bool(_placement_overlays.try_show_module_action_overlay(aid, {})):
					_sync_action_panel_context()
					return
			if _placement_overlays != null and _placement_overlays.has_method("try_show_piece_placement"):
				if bool(_placement_overlays.try_show_piece_placement(aid, {})):
					_sync_action_panel_context()
					return
			return

func _update_ui_components(state: GameState) -> void:
	if _ui_components_binder != null and _ui_components_binder.has_method("sync"):
		_ui_components_binder.sync(state)

func on_action_requested(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var current_player_id := state.get_current_player_id()

	var blocked_by_action_panel := false
	if _scene != null and is_instance_valid(_scene.action_panel) and _scene.action_panel.has_method("is_globally_disabled"):
		blocked_by_action_panel = bool(_scene.action_panel.call("is_globally_disabled"))

	var blocked_by_online_turn := false
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0:
			blocked_by_online_turn = true
		elif not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(state):
			blocked_by_online_turn = true

	if blocked_by_action_panel or blocked_by_online_turn:
		return

	var actor_id := current_player_id
	# 联机模式：所有玩家动作都应以本地玩家为 actor（避免误用 current_player_id 导致无法继续）
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		actor_id = int(OnlinePhaseInteractionClass.get_online_local_player_id(state, current_player_id))

	match action_id:
		# UI 工具：时间线回退
		"rewind_to_turn_start":
			if _scene != null and _scene.has_method("rewind_to_turn_start"):
				_scene.call("rewind_to_turn_start")
			return

		# 系统动作
		ActionIdsClass.ADVANCE_PHASE:
			_execute_command.call(Command.create_system(ActionIdsClass.ADVANCE_PHASE, params))
		ActionIdsClass.SKIP:
			_execute_command.call(Command.create(ActionIdsClass.SKIP, actor_id, params))
		"choose_turn_order":
			if state != null and _modals_controller != null:
				_modals_controller.show_turn_order_modal_for_state(state)

		# P0 动作 - 需要弹出面板
		"recruit":
			if _working_panels != null:
				_working_panels.show_recruit_panel()
			_last_guided_action_id = str(action_id).strip_edges()
		"train":
			if _working_panels != null:
				_working_panels.show_train_panel()
			_last_guided_action_id = str(action_id).strip_edges()
		"fire":
			if _end_panels != null:
				_end_panels.show_payday_panel()
			_last_guided_action_id = str(action_id).strip_edges()

		# P1 动作 - 需要弹出面板
		"initiate_marketing":
			if _marketing_panels != null:
				_marketing_panels.show_marketing_panel()
			_last_guided_action_id = str(action_id).strip_edges()
		ActionIdsClass.SET_PRICE, ActionIdsClass.SET_LUXURY_PRICE, ActionIdsClass.SET_DISCOUNT:
			if _working_panels != null:
				_working_panels.show_price_panel(action_id)
		"produce_food":
			if _working_panels != null:
				_working_panels.show_production_panel("food")
			_last_guided_action_id = str(action_id).strip_edges()
		"procure_drinks":
			if _working_panels != null:
				_working_panels.show_production_panel("drinks")
			_last_guided_action_id = str(action_id).strip_edges()
		"place_restaurant", "move_restaurant":
			if _placement_overlays != null:
				_placement_overlays.show_restaurant_placement(action_id, params)
				_sync_action_panel_context()
			_last_guided_action_id = str(action_id).strip_edges()
		"place_house", "add_garden":
			if _placement_overlays != null:
				_placement_overlays.show_house_placement(action_id, params)
				_sync_action_panel_context()
			_last_guided_action_id = str(action_id).strip_edges()

		# 其他动作直接创建命令
		_:
			if _placement_overlays != null and _placement_overlays.has_method("try_show_module_action_overlay"):
				if bool(_placement_overlays.try_show_module_action_overlay(action_id, params)):
					_sync_action_panel_context()
					_last_guided_action_id = str(action_id).strip_edges()
					return
			if _placement_overlays != null and _placement_overlays.has_method("try_show_piece_placement"):
				if bool(_placement_overlays.try_show_piece_placement(action_id, params)):
					_sync_action_panel_context()
					_last_guided_action_id = str(action_id).strip_edges()
					return
			_execute_command.call(Command.create(action_id, actor_id, params))

func _on_turn_order_position_selected(position: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var actor_id := state.get_current_player_id()
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)
	_execute_command.call(Command.create("choose_turn_order", actor_id, {"position": position}))

func _on_hand_cards_selected(employee_ids: Array[String]) -> void:
	GameLog.info("Game", "选中员工: %s" % str(employee_ids))

func _on_hand_card_dropped(employee_id: String, target: Control) -> void:
	if _restructuring_controller != null and _restructuring_controller.has_method("on_hand_card_dropped"):
		_restructuring_controller.on_hand_card_dropped(employee_id, target)

func _on_hand_card_double_clicked(employee_id: String) -> void:
	if _restructuring_controller != null and _restructuring_controller.has_method("on_hand_card_double_clicked"):
		_restructuring_controller.on_hand_card_double_clicked(employee_id)

func _on_company_structure_card_double_clicked(employee_id: String) -> void:
	if _restructuring_controller != null and _restructuring_controller.has_method("on_company_structure_card_double_clicked"):
		_restructuring_controller.on_company_structure_card_double_clicked(employee_id)

func _on_company_structure_changed(new_structure: Dictionary) -> void:
	GameLog.info("Game", "公司结构变更: %s" % str(new_structure))

func _hide_all_phase_panels(keep_selection: bool = false, suppress_dismissal: bool = false) -> void:
	if _working_panels != null:
		_working_panels.hide()
	if _end_panels != null:
		_end_panels.hide()
	if _marketing_panels != null:
		_marketing_panels.hide()
	if _placement_overlays != null:
		_placement_overlays.hide()

	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()
	if not keep_selection and _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()

	hide_modal_ui()
	_sync_action_panel_context()
	if _scene != null and _scene.has_method("_sync_right_panel_docked_view"):
		_scene.call_deferred("_sync_right_panel_docked_view")

func _sync_modals(state: GameState) -> void:
	if _scene == null or state == null:
		return

	var is_timeline_read_only := false
	if _scene.has_method("is_timeline_read_only_active"):
		var v = _scene.call("is_timeline_read_only_active")
		if v is bool:
			is_timeline_read_only = bool(v)
	elif _scene.has_method("is_replay_mode_active"):
		# Backwards-compat fallback.
		var v2 = _scene.call("is_replay_mode_active")
		if v2 is bool:
			is_timeline_read_only = bool(v2)

	# 回放/复盘（只读时间线）：禁止强制交互弹窗（否则会遮挡并吞掉时间线输入）
	if is_timeline_read_only:
		if _modals_controller != null:
			_modals_controller.hide()
		if _restructuring_controller != null and _restructuring_controller.has_method("hide_modal"):
			_restructuring_controller.hide_modal()
		return

	var covered := Rect2(Vector2.ZERO, Vector2.ZERO)
	if _modals_controller != null and _modals_controller.has_method("get_modal_cover_rect"):
		covered = _modals_controller.get_modal_cover_rect()
	elif _scene != null:
		covered = Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

	if _modals_controller != null and _modals_controller.has_method("sync_for_state"):
		_modals_controller.sync_for_state(state, covered)

	# 重组（Restructuring）
	if _restructuring_controller != null and _restructuring_controller.has_method("sync_modal"):
		_view_player_id = int(_restructuring_controller.sync_modal(state, covered, _view_player_id))

func _get_current_map_skin():
	if _scene == null:
		return null
	var canvas = _scene.get("map_canvas")
	if is_instance_valid(canvas) and canvas.has_method("get_skin"):
		return canvas.call("get_skin")
	return null
