# Game scene：阶段面板/交互协调器
# 负责：
# - ActionPanel -> 行为分派（执行命令 / 打开面板）
# - 基础 UI 组件数据绑定（玩家面板/顺序轨/库存/手牌/公司结构）
# - 阶段面板/覆盖层生命周期委托（见 game_panel_*）
class_name GamePanelController
extends RefCounted

const WorkingPanelsClass = preload("res://ui/scenes/game/game_panel_working_panels.gd")
const MarketingPanelsClass = preload("res://ui/scenes/game/game_panel_marketing_panels.gd")
const PlacementOverlaysClass = preload("res://ui/scenes/game/game_panel_placement_overlays.gd")
const EndPanelsClass = preload("res://ui/scenes/game/game_panel_end_panels.gd")
const RestructuringControllerClass = preload("res://ui/scenes/game/game_panel_restructuring_controller.gd")
const ModalsControllerClass = preload("res://ui/scenes/game/game_panel_modals_controller.gd")
const ViewsControllerClass = preload("res://ui/scenes/game/game_panel_views_controller.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const POPUP_LAYOUT_META_KEY := "popup_layout"
const POPUP_LAYOUT_DOCK_RIGHT := "dock_right"

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

var _view_player_id: int = -1
var _last_guided_action_id: String = ""

func _init(scene, map_controller, overlay_controller, execute_command: Callable, refresh_ui: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_refresh_ui = refresh_ui
	# 联机模式：默认视角锁定到本地玩家（避免默认跟随 current_player 导致“重组拖拽不了自己”的体验）
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and NetContext.local_player_id >= 0:
		_view_player_id = int(NetContext.local_player_id)

	var hide_all := Callable(self, "_hide_all_phase_panels")
	var center_popup := Callable(self, "_center_popup")

	_working_panels = WorkingPanelsClass.new(_scene, _map_controller, _execute_command, hide_all, center_popup, _overlay_controller)
	_marketing_panels = MarketingPanelsClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all, center_popup)
	_placement_overlays = PlacementOverlaysClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all)
	_end_panels = EndPanelsClass.new(_scene, _overlay_controller, _execute_command, hide_all, center_popup, _refresh_ui)
	_restructuring_controller = RestructuringControllerClass.new(
		_scene,
		_execute_command,
		Callable(self, "get_view_player_id"),
		Callable(self, "_on_view_player_selected")
	)
	_modals_controller = ModalsControllerClass.new(_scene, _execute_command)
	_views_controller = ViewsControllerClass.new(_scene)

func connect_signals(action_panel, action_flow_controls, turn_order_track, hand_area, company_structure) -> void:
	UiSignalHelpersClass.safe_connect(action_panel, "action_requested", on_action_requested)
	UiSignalHelpersClass.safe_connect(action_flow_controls, "action_requested", on_action_requested)
	UiSignalHelpersClass.safe_connect(turn_order_track, "position_selected", _on_turn_order_position_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "cards_selected", _on_hand_cards_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "card_dropped", _on_hand_card_dropped)
	UiSignalHelpersClass.safe_connect(company_structure, "structure_changed", _on_company_structure_changed)
	UiSignalHelpersClass.safe_connect(company_structure, "card_dropped", _on_hand_card_dropped)

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

func dispose() -> void:
	_execute_command = Callable()
	_refresh_ui = Callable()

	_working_panels = null
	_marketing_panels = null
	_placement_overlays = null
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
	if _working_panels != null:
		_working_panels.sync(state, force_full_refresh)
	if _marketing_panels != null:
		_marketing_panels.sync(state, force_full_refresh)
	if _placement_overlays != null:
		_placement_overlays.sync(state, force_full_refresh)
	if _end_panels != null:
		_end_panels.sync(state, force_full_refresh)
	_sync_modals(state)
	_sync_action_panel_context()
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

func get_employee_tree_panel():
	if _views_controller == null:
		return null
	return _views_controller.get_employee_tree_panel()

func _sync_action_panel_context() -> void:
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

	if overlay != null and is_instance_valid(overlay):
		if _scene.action_panel.has_method("bind_context_overlay"):
			_scene.action_panel.call("bind_context_overlay", overlay)
	else:
		if _scene.action_panel.has_method("clear_context_overlay"):
			_scene.action_panel.call("clear_context_overlay")

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
	# - 放置类 overlay：跳过在 ActionPanel ContextPanel（左），确认在 ContextPanel（右）
	if _is_skip_sub_phase_shown_in_right_panel_footer():
		return true
	if _has_active_context_overlay():
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

	# 右侧 dock 里已有可见面板（例如日志）：不要抢占焦点自动弹出动作 UI。
	# 关闭 dock 后（例如关闭日志）会触发一次 UI refresh，从而恢复自动打开。
	if _has_visible_right_panel_docked_panel():
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

func _has_visible_right_panel_docked_panel() -> bool:
	if _scene == null:
		return false
	var dock_host = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DockHost")
	if dock_host == null or not is_instance_valid(dock_host):
		return false
	for ch in dock_host.get_children():
		if ch is Control and (ch as Control).visible:
			return true
	return false

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
	if _scene == null or state == null:
		return

	var current_player_id := state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)

	var requested_view_player_id := _view_player_id
	# 联机模式：当未显式选择“查看玩家”时，默认查看自己（避免默认跟随 current_player 造成误导/代操风险）。
	if is_online and requested_view_player_id < 0 and local_player_id >= 0:
		requested_view_player_id = local_player_id
		_view_player_id = local_player_id
	var view_player_id := _get_effective_view_player_id(state, requested_view_player_id)
	var using_default_view := view_player_id != requested_view_player_id

	# Restructuring：若当前默认视图玩家已提交，自动切到第一位未提交玩家（避免“看起来无法拖拽”）。
	if using_default_view and not is_online and state.phase == DefsClass.PHASE_RESTRUCTURING and (state.round_state is Dictionary):
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			var submitted_val = r.get("submitted", null)
			if submitted_val is Dictionary:
				var submitted: Dictionary = submitted_val
				var view_flag = submitted.get(view_player_id, null)
				if view_flag == null and submitted.has(str(view_player_id)):
					view_flag = submitted.get(str(view_player_id), null)

				if bool(view_flag):
					var picked := -1
					for i in range(state.turn_order.size()):
						var pid_val = state.turn_order[i]
						if not (pid_val is int):
							continue
						var pid: int = int(pid_val)
						if pid < 0 or pid >= state.players.size():
							continue
						var flag = submitted.get(pid, null)
						if flag == null and submitted.has(str(pid)):
							flag = submitted.get(str(pid), null)
						if not bool(flag):
							picked = pid
							break

					if picked >= 0:
						view_player_id = picked
						_view_player_id = picked

			# Restructuring：隐私规则（Online 仅自己；Hotseat 已提交锁定）
			if str(state.phase) == DefsClass.PHASE_RESTRUCTURING and _restructuring_controller != null:
				var adjusted = _restructuring_controller.apply_view_privacy(state, view_player_id)
				if adjusted != view_player_id:
					view_player_id = adjusted
					_view_player_id = adjusted

	var view_player: Dictionary = current_player
	if view_player_id >= 0 and view_player_id < state.players.size():
		var vp_val = state.players[view_player_id]
		if vp_val is Dictionary:
			view_player = Dictionary(vp_val)

	# 玩家面板
	if is_instance_valid(_scene.player_panel) and _scene.player_panel.has_method("set_game_state"):
		_scene.player_panel.set_game_state(state)
		if _scene.player_panel.has_method("set_current_player"):
			_scene.player_panel.set_current_player(current_player_id)
		if _scene.player_panel.has_method("set_view_player"):
			_scene.player_panel.set_view_player(view_player_id)

	# 左侧信息面板（P3：骨架）
	if is_instance_valid(_scene.left_panel):
		if _scene.left_panel.has_method("set_game_state"):
			_scene.left_panel.set_game_state(state)
		if _scene.left_panel.has_method("set_current_player"):
			_scene.left_panel.set_current_player(current_player_id)

	# 顺序轨
	# selections: position -> player_id
	var selections := {}
	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS and (state.round_state is Dictionary):
		var rs: Dictionary = state.round_state
		var oob_val = rs.get("order_of_business", null)
		if oob_val is Dictionary:
			var oob: Dictionary = oob_val
			var picks_val = oob.get("picks", null)
			if picks_val is Array:
				var picks: Array = picks_val
				for pos in range(min(picks.size(), state.players.size())):
					var pid: int = int(picks[pos])
					if pid >= 0:
						selections[pos] = pid
	else:
		for i in range(state.turn_order.size()):
			if i < state.players.size():
				selections[i] = state.turn_order[i]

		if is_instance_valid(_scene.turn_order_track):
			if _scene.turn_order_track.has_method("set_player_count"):
				_scene.turn_order_track.set_player_count(state.players.size())
			if _scene.turn_order_track.has_method("set_current_selections"):
				_scene.turn_order_track.set_current_selections(selections)
			if _scene.turn_order_track.has_method("set_selectable"):
				# 新布局(v2)：顺序选择使用遮罩面板；右侧 TurnOrderTrack 不再承担交互入口。
				_scene.turn_order_track.set_selectable(false, current_player_id)
				if _scene.turn_order_track is Control:
					(_scene.turn_order_track as Control).visible = false

		# 顶部顺序显示（展示用）
	if is_instance_valid(_scene.turn_order_display):
		if _scene.turn_order_display.has_method("set_game_state"):
			_scene.turn_order_display.set_game_state(state)
		if _scene.turn_order_display.has_method("set_player_count"):
			_scene.turn_order_display.set_player_count(state.players.size())
		if _scene.turn_order_display.has_method("set_current_selections"):
			_scene.turn_order_display.set_current_selections(selections)
		if _scene.turn_order_display.has_method("set_current_player"):
			_scene.turn_order_display.set_current_player(current_player_id)

	# 库存面板
	if is_instance_valid(_scene.inventory_panel) and _scene.inventory_panel.has_method("set_inventory"):
		var inventory: Dictionary = view_player.get("inventory", {})
		if _scene.inventory_panel.has_method("set_visual_modules") and (state.modules is Array):
			_scene.inventory_panel.set_visual_modules(Array(state.modules, TYPE_STRING, "", null))
		_scene.inventory_panel.set_inventory(inventory)
		if _scene.inventory_panel.has_method("set_fridge_capacity"):
			_scene.inventory_panel.set_fridge_capacity(_get_fridge_capacity_for_player(view_player))

	# 动作面板
	if is_instance_valid(_scene.action_panel):
		if _scene.action_panel.has_method("set_game_state"):
			_scene.action_panel.set_game_state(state)
		if _scene.action_panel.has_method("set_current_player"):
			var action_player_id := current_player_id
			if is_online and local_player_id >= 0:
				action_player_id = local_player_id
			_scene.action_panel.set_current_player(action_player_id)
		if _scene.action_panel.has_method("set_map_skin"):
			_scene.action_panel.set_map_skin(_get_current_map_skin())
		if _scene.action_panel.has_method("set_action_registry") and _scene.game_engine != null:
			var registry = _scene.game_engine.get_action_registry() if _scene.game_engine.has_method("get_action_registry") else null
			if registry != null:
				_scene.action_panel.set_action_registry(registry)

	# 员工手牌区
	if is_instance_valid(_scene.hand_area) and _scene.hand_area.has_method("set_employees"):
		var employees_raw: Array[String] = []
		var reserve: Array[String] = []
		var busy: Array[String] = []

		for e in Array(view_player.get("employees", [])):
			var eid := str(e).strip_edges()
			if not eid.is_empty():
				employees_raw.append(eid)
		for e in Array(view_player.get("reserve_employees", [])):
			var rid := str(e).strip_edges()
			if not rid.is_empty():
				reserve.append(rid)
		for e in Array(view_player.get("busy_marketers", [])):
			var bid := str(e).strip_edges()
			if not bid.is_empty():
				busy.append(bid)

		# UI 展示规则：
		# - CEO 不显示在手牌区（避免重复信息；CEO 始终可在公司结构视图中看到）
		# - 忙碌营销员仅在 busy 区域展示，避免在 employees 与 busy 两处重复出现
		# - 已放入 company_structure 的员工不在“在岗员工”区重复展示（他们属于公司结构而非待分配手牌）
		var busy_remaining: Dictionary = {}
		for bid2 in busy:
			busy_remaining[bid2] = int(busy_remaining.get(bid2, 0)) + 1

		var assigned_remaining: Dictionary = {}
		var cs_val = view_player.get("company_structure", null)
		if cs_val is Dictionary:
			var cs: Dictionary = cs_val
			var struct_val = cs.get("structure", null)
			if struct_val is Array:
				for entry_val in struct_val:
					if not (entry_val is Dictionary):
						continue
					var entry: Dictionary = entry_val
					var mid := str(entry.get("employee_id", "")).strip_edges()
					if not mid.is_empty():
						assigned_remaining[mid] = int(assigned_remaining.get(mid, 0)) + 1
					var reps_val = entry.get("reports", null)
					if reps_val is Array:
						for rep_val in reps_val:
							if not (rep_val is String):
								continue
							var rid2 := str(rep_val).strip_edges()
							if rid2.is_empty():
								continue
							assigned_remaining[rid2] = int(assigned_remaining.get(rid2, 0)) + 1

		var employees: Array[String] = []
		for eid2 in employees_raw:
			if eid2 == "ceo":
				continue

			var remain_busy := int(busy_remaining.get(eid2, 0))
			if remain_busy > 0:
				busy_remaining[eid2] = remain_busy - 1
				continue

			var remain_assigned := int(assigned_remaining.get(eid2, 0))
			if remain_assigned > 0:
				assigned_remaining[eid2] = remain_assigned - 1
				continue

			employees.append(eid2)

		_scene.hand_area.set_employees(employees, reserve, busy)

		var enable_drag := (state.phase == DefsClass.PHASE_RESTRUCTURING)
		if enable_drag and (state.round_state is Dictionary):
			var r_val = state.round_state.get("restructuring", null)
			if r_val is Dictionary:
					var r: Dictionary = r_val
					var submitted_val = r.get("submitted", null)
					if submitted_val is Dictionary:
						var submitted: Dictionary = submitted_val
						var submitted_flag = submitted.get(view_player_id, null)
						if submitted_flag == null and submitted.has(str(view_player_id)):
							submitted_flag = submitted.get(str(view_player_id), null)
						if bool(submitted_flag):
							enable_drag = false
		# 联机模式：禁止代操公司结构重组（只能拖拽本地玩家的数据）
		if enable_drag and NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
			var local_pid := int(NetContext.local_player_id)
			if local_pid < 0 or view_player_id != local_pid:
				enable_drag = false

		if _scene.hand_area.has_method("set_drag_enabled"):
			_scene.hand_area.set_drag_enabled(enable_drag)
		if is_instance_valid(_scene.company_structure) and _scene.company_structure.has_method("set_drag_enabled"):
			_scene.company_structure.set_drag_enabled(enable_drag)

	# 公司结构面板
	if is_instance_valid(_scene.company_structure) and _scene.company_structure.has_method("set_player_data"):
		_scene.company_structure.set_player_data(view_player)

func _get_fridge_capacity_for_player(player: Dictionary) -> int:
	if player == null:
		return -1
	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return -1
	if not MilestoneRegistry.is_loaded():
		return -1

	var milestones: Array = milestones_val
	var has_fridge := false
	var capacity := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			continue
		var mid: String = str(mid_val)
		if mid.is_empty():
			continue
		var def_val = MilestoneRegistry.get_def(mid)
		if def_val == null:
			continue
		if not (def_val is MilestoneDef):
			continue
		var def: MilestoneDef = def_val
		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				continue
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				continue
			if str(type_val) != "gain_fridge":
				continue
			var value_val = eff.get("value", null)
			if value_val is int:
				has_fridge = true
				capacity = maxi(capacity, int(value_val))
			elif value_val is float:
				var f: float = float(value_val)
				if f == int(f):
					has_fridge = true
					capacity = maxi(capacity, int(f))

	return capacity if has_fridge else -1

func on_action_requested(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return

	var current_player_id := state.get_current_player_id()
	var actor_id := current_player_id
	# 联机模式：所有玩家动作都应以本地玩家为 actor（避免误用 current_player_id 导致无法继续）
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and int(NetContext.local_player_id) >= 0:
		actor_id = int(NetContext.local_player_id)

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

func _center_popup(panel: Control) -> void:
	if panel == null:
		return
	if _scene == null:
		return
	var layout := ""
	if panel.has_meta(POPUP_LAYOUT_META_KEY):
		layout = str(panel.get_meta(POPUP_LAYOUT_META_KEY))

	panel.z_index = 500

	if layout == POPUP_LAYOUT_DOCK_RIGHT:
		_dock_popup_right(panel)
	else:
		await _scene.get_tree().process_frame
		_center_popup_in_viewport(panel)

	# P2：弹窗动画（避免 headless 影响测试/资源回收）
	if OS.has_feature("headless"):
		return
	if not (_scene.has_method("get_ui_animation_manager")):
		return
	var anim_manager = _scene.call("get_ui_animation_manager")
	if anim_manager == null:
		return

	if layout != POPUP_LAYOUT_DOCK_RIGHT and anim_manager.has_method("animate_scale_bounce"):
		anim_manager.call("animate_scale_bounce", panel)

func _center_popup_in_viewport(panel: Control) -> void:
	if panel == null or _scene == null:
		return
	var safe_rect := _get_map_area_rect_in_scene()
	var panel_size := _get_panel_size(panel)

	var x := safe_rect.position.x + (safe_rect.size.x - panel_size.x) / 2.0
	var y := safe_rect.position.y + (safe_rect.size.y - panel_size.y) / 2.0

	var margin := 8.0
	var min_x := safe_rect.position.x + margin
	var max_x := safe_rect.position.x + safe_rect.size.x - panel_size.x - margin
	if max_x < min_x:
		max_x = min_x
	var min_y := safe_rect.position.y + margin
	var max_y := safe_rect.position.y + safe_rect.size.y - panel_size.y - margin
	if max_y < min_y:
		max_y = min_y

	panel.position = Vector2(
		clampf(x, min_x, max_x),
		clampf(y, min_y, max_y)
	)

func _dock_popup_right(panel: Control) -> void:
	if panel == null or _scene == null:
		return

	# v2：优先嵌入到 RightPanel（抽屉式），而不是覆盖在视口右侧
	if _scene.has_method("dock_popup_into_right_panel"):
		var r = _scene.call("dock_popup_into_right_panel", panel)
		if r is bool and bool(r):
			return

	var safe := _get_popup_safe_rect()
	var panel_size := _get_panel_size(panel)

	var margin := 12.0
	var x := safe.position.x + safe.size.x - panel_size.x - margin
	var y := safe.position.y + (safe.size.y - panel_size.y) / 2.0

	# Clamp
	x = maxf(margin, x)
	var min_y := safe.position.y + margin
	var max_y := safe.position.y + safe.size.y - panel_size.y - margin
	if max_y < min_y:
		max_y = min_y
	y = clampf(y, min_y, max_y)

	panel.position = Vector2(x, y)

func _get_panel_size(panel: Control) -> Vector2:
	var s := panel.size
	if s == Vector2.ZERO:
		s = panel.get_combined_minimum_size()
	if s == Vector2.ZERO:
		s = panel.custom_minimum_size
	if s == Vector2.ZERO:
		s = Vector2(420, 260)
	return s

func _get_map_area_rect_in_scene() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var map_area = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit/GameArea")
	if map_area is Control:
		var c: Control = map_area
		var gr := c.get_global_rect()
		var scene_global := Vector2.ZERO
		if _scene is Control:
			scene_global = (_scene as Control).global_position
		var rect := Rect2(gr.position - scene_global, gr.size)
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			return rect

	return Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

func _get_popup_safe_rect() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var viewport_size: Vector2 = _scene.get_viewport_rect().size
	var top := 0.0
	var bottom := viewport_size.y

	var top_bar = _scene.get_node_or_null("UIRoot/TopBar")
	if top_bar is Control:
		var c: Control = top_bar
		top = maxf(top, c.position.y + c.size.y)

	var bottom_panel = _scene.get_node_or_null("UIRoot/BottomPanel")
	if bottom_panel is Control:
		var c2: Control = bottom_panel
		bottom = minf(bottom, c2.position.y)

	# 预留一点间距（避免贴边）
	top += 5.0
	bottom -= 5.0

	if bottom < top:
		bottom = top

	return Rect2(Vector2(0, top), Vector2(viewport_size.x, bottom - top))

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
