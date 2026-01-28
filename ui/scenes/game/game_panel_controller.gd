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

const RestructuringModalScene = preload("res://ui/components/modal_panel/restructuring_modal.tscn")
const TurnOrderSelectionModalScene = preload("res://ui/components/modal_panel/turn_order_selection_modal.tscn")
const ReserveCardSelectionModalScene = preload("res://ui/components/modal_panel/reserve_card_selection_modal.tscn")
const FridgeKeepModalScene = preload("res://ui/components/modal_panel/fridge_keep_modal.tscn")
const EmployeeTreeScene = preload("res://ui/components/employee_tree/employee_tree.tscn")
const MilestoneFullScreenViewScene = preload("res://ui/components/milestone_panel/milestone_full_screen_view.tscn")
const ReserveAreaFullScreenViewScene = preload("res://ui/components/reserve_area/reserve_area_full_screen_view.tscn")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const POPUP_LAYOUT_META_KEY := "popup_layout"
const POPUP_LAYOUT_DOCK_RIGHT := "dock_right"

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _refresh_ui: Callable

var _working_panels = null
var _marketing_panels = null
var _placement_overlays = null
var _end_panels = null

var _restructuring_modal = null
var _turn_order_modal = null
var _reserve_card_modal = null
var _fridge_keep_modal = null
var _employee_tree_panel = null
var _milestone_full_screen_view = null
var _reserve_area_full_screen_view = null

var _view_player_id: int = -1
var _pending_reserve_card_open_player_id: int = -1
var _pending_reserve_card_open_attempts: int = 0
var _reserve_card_open_routine_running: bool = false

func _init(scene, map_controller, overlay_controller, execute_command: Callable, refresh_ui: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_refresh_ui = refresh_ui

	var hide_all := Callable(self, "_hide_all_phase_panels")
	var center_popup := Callable(self, "_center_popup")

	_working_panels = WorkingPanelsClass.new(_scene, _map_controller, _execute_command, hide_all, center_popup, _overlay_controller)
	_marketing_panels = MarketingPanelsClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all, center_popup)
	_placement_overlays = PlacementOverlaysClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all)
	_end_panels = EndPanelsClass.new(_scene, _overlay_controller, _execute_command, hide_all, center_popup, _refresh_ui)

func connect_signals(action_panel, turn_order_track, hand_area, company_structure) -> void:
	UiSignalHelpersClass.safe_connect(action_panel, "action_requested", on_action_requested)
	UiSignalHelpersClass.safe_connect(turn_order_track, "position_selected", _on_turn_order_position_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "cards_selected", _on_hand_cards_selected)
	UiSignalHelpersClass.safe_connect(hand_area, "card_dropped", _on_hand_card_dropped)
	UiSignalHelpersClass.safe_connect(company_structure, "structure_changed", _on_company_structure_changed)
	UiSignalHelpersClass.safe_connect(company_structure, "card_dropped", _on_hand_card_dropped)

	# 查看玩家（view_player）
	if _scene != null:
		UiSignalHelpersClass.safe_connect(_scene.player_panel, "player_selected", _on_view_player_selected)
		UiSignalHelpersClass.safe_connect(_scene.left_panel, "player_selected", _on_view_player_selected)
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

	_ensure_milestone_full_screen_view()
	if not is_instance_valid(_milestone_full_screen_view):
		return

	if _milestone_full_screen_view.has_method("open_with_state"):
		_milestone_full_screen_view.call("open_with_state", state, _get_current_map_skin())
	_milestone_full_screen_view.visible = true

func show_reserve_area_panel() -> void:
	if _scene == null:
		return
	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return
	var state: GameState = engine.get_state()
	if state == null:
		return

	_ensure_reserve_area_full_screen_view()
	if not is_instance_valid(_reserve_area_full_screen_view):
		return

	if _reserve_area_full_screen_view.has_method("open_with_state"):
		_reserve_area_full_screen_view.call("open_with_state", state, _get_current_map_skin())
	_reserve_area_full_screen_view.visible = true

func show_payday_panel() -> void:
	if _end_panels != null:
		_end_panels.show_payday_panel()

func toggle_employee_tree() -> void:
	if _scene == null:
		return

	if is_instance_valid(_employee_tree_panel) and _employee_tree_panel.visible:
		_employee_tree_panel.visible = false
		return

	_hide_all_phase_panels(true)
	_ensure_employee_tree_panel()
	if not is_instance_valid(_employee_tree_panel):
		return

	if _employee_tree_panel.has_method("open"):
		_employee_tree_panel.call("open")

	# 覆盖全屏（不使用居中弹窗布局）
	if _employee_tree_panel is Control:
		var p: Control = _employee_tree_panel
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.offset_left = 0.0
		p.offset_top = 0.0
		p.offset_right = 0.0
		p.offset_bottom = 0.0
		p.position = Vector2.ZERO
		p.size = _scene.get_viewport_rect().size
	_employee_tree_panel.visible = true

func get_view_player_id() -> int:
	return _view_player_id

func _get_effective_view_player_id(state: GameState, requested_view_id: int) -> int:
	if state == null:
		return requested_view_id
	if requested_view_id >= 0 and requested_view_id < state.players.size():
		return requested_view_id
	return state.get_current_player_id()

func _on_view_player_selected(player_id: int) -> void:
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

	if is_instance_valid(_restructuring_modal):
		_restructuring_modal.queue_free()
	_restructuring_modal = null

	if is_instance_valid(_turn_order_modal):
		_turn_order_modal.queue_free()
	_turn_order_modal = null

	if is_instance_valid(_reserve_card_modal):
		_reserve_card_modal.queue_free()
	_reserve_card_modal = null

	if is_instance_valid(_fridge_keep_modal):
		_fridge_keep_modal.queue_free()
	_fridge_keep_modal = null

	if is_instance_valid(_employee_tree_panel):
		_employee_tree_panel.queue_free()
		_employee_tree_panel = null

	if is_instance_valid(_milestone_full_screen_view):
		_milestone_full_screen_view.queue_free()
		_milestone_full_screen_view = null

	if is_instance_valid(_reserve_area_full_screen_view):
		_reserve_area_full_screen_view.queue_free()
		_reserve_area_full_screen_view = null

	_scene = null
	_map_controller = null
	_overlay_controller = null

func has_open_modal_ui() -> bool:
	if is_instance_valid(_restructuring_modal) and _restructuring_modal.visible:
		return true
	if is_instance_valid(_turn_order_modal) and _turn_order_modal.visible:
		return true
	if is_instance_valid(_reserve_card_modal) and _reserve_card_modal.visible:
		return true
	if is_instance_valid(_fridge_keep_modal) and _fridge_keep_modal.visible:
		return true
	if is_instance_valid(_employee_tree_panel) and _employee_tree_panel.visible:
		return true
	if is_instance_valid(_milestone_full_screen_view) and _milestone_full_screen_view.visible:
		return true
	if is_instance_valid(_reserve_area_full_screen_view) and _reserve_area_full_screen_view.visible:
		return true
	return false

func hide_modal_ui() -> void:
	_hide_turn_order_modal()
	_hide_restructuring_modal()
	_hide_reserve_card_modal()
	_hide_fridge_keep_modal()
	_hide_employee_tree()
	_hide_milestone_full_screen_view()
	_hide_reserve_area_full_screen_view()

func hide_top_overlays_if_open() -> bool:
	# 仅关闭“覆盖全屏的浏览视图”（例如里程碑/保留区），避免 ESC 误触发 hide_all() 影响底层面板状态。
	if is_instance_valid(_reserve_area_full_screen_view) and _reserve_area_full_screen_view.visible:
		_hide_reserve_area_full_screen_view()
		return true
	if is_instance_valid(_milestone_full_screen_view) and _milestone_full_screen_view.visible:
		_hide_milestone_full_screen_view()
		return true
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

func get_milestone_full_screen_view():
	_ensure_milestone_full_screen_view()
	return _milestone_full_screen_view

func get_reserve_area_full_screen_view():
	_ensure_reserve_area_full_screen_view()
	return _reserve_area_full_screen_view

func get_employee_tree_panel():
	_ensure_employee_tree_panel()
	return _employee_tree_panel

func _sync_action_panel_context() -> void:
	if _scene == null:
		return
	if not is_instance_valid(_scene.action_panel):
		return

	var overlay = null
	if _placement_overlays != null:
		if is_instance_valid(_placement_overlays.restaurant_placement_overlay) and _placement_overlays.restaurant_placement_overlay.visible:
			overlay = _placement_overlays.restaurant_placement_overlay
		elif is_instance_valid(_placement_overlays.house_placement_overlay) and _placement_overlays.house_placement_overlay.visible:
			overlay = _placement_overlays.house_placement_overlay

	if overlay != null:
		if _scene.action_panel.has_method("bind_context_overlay"):
			_scene.action_panel.call("bind_context_overlay", overlay)
	else:
		if _scene.action_panel.has_method("clear_context_overlay"):
			_scene.action_panel.call("clear_context_overlay")

func _update_ui_components(state: GameState) -> void:
	if _scene == null or state == null:
		return

	var current_player_id := state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	var requested_view_player_id := _view_player_id
	var view_player_id := _get_effective_view_player_id(state, requested_view_player_id)
	var using_default_view := view_player_id != requested_view_player_id

	# Restructuring：若当前默认视图玩家已提交，自动切到第一位未提交玩家（避免“看起来无法拖拽”）。
	if using_default_view and state.phase == DefsClass.PHASE_RESTRUCTURING and (state.round_state is Dictionary):
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
		if _scene.left_panel.has_method("set_view_player"):
			_scene.left_panel.set_view_player(view_player_id)

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
			_scene.action_panel.set_current_player(current_player_id)
		if _scene.action_panel.has_method("set_action_registry") and _scene.game_engine != null:
			var registry = _scene.game_engine.get_action_registry() if _scene.game_engine.has_method("get_action_registry") else null
			if registry != null:
				_scene.action_panel.set_action_registry(registry)

	# 员工手牌区
	if is_instance_valid(_scene.hand_area) and _scene.hand_area.has_method("set_employees"):
		var employees: Array[String] = []
		var reserve: Array[String] = []
		var busy: Array[String] = []

		for e in Array(view_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(view_player.get("reserve_employees", [])):
			reserve.append(str(e))
		for e in Array(view_player.get("busy_marketers", [])):
			busy.append(str(e))

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

	var current_player_id = _scene.game_engine.get_state().get_current_player_id()

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
			_execute_command.call(Command.create(ActionIdsClass.SKIP, current_player_id, params))
		"choose_turn_order":
			var state: GameState = _scene.game_engine.get_state()
			if state != null:
				_show_turn_order_modal_for_state(state)

		# P0 动作 - 需要弹出面板
		"recruit":
			if _working_panels != null:
				_working_panels.show_recruit_panel()
		"train":
			if _working_panels != null:
				_working_panels.show_train_panel()
		"fire":
			if _end_panels != null:
				_end_panels.show_payday_panel()

		# P1 动作 - 需要弹出面板
		"initiate_marketing":
			if _marketing_panels != null:
				_marketing_panels.show_marketing_panel()
		ActionIdsClass.SET_PRICE, ActionIdsClass.SET_LUXURY_PRICE, ActionIdsClass.SET_DISCOUNT:
			if _working_panels != null:
				_working_panels.show_price_panel(action_id)
		"produce_food":
			if _working_panels != null:
				_working_panels.show_production_panel("food")
		"procure_drinks":
			if _working_panels != null:
				_working_panels.show_production_panel("drinks")
		"place_restaurant", "move_restaurant":
			if _placement_overlays != null:
				_placement_overlays.show_restaurant_placement(action_id, params)
				_sync_action_panel_context()
		"place_house", "add_garden":
			if _placement_overlays != null:
				_placement_overlays.show_house_placement(action_id, params)
				_sync_action_panel_context()

		# 其他动作直接创建命令
		_:
			_execute_command.call(Command.create(action_id, current_player_id, params))

func _on_turn_order_position_selected(position: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	_execute_command.call(Command.create("choose_turn_order", current_player_id, {"position": position}))

func _on_hand_cards_selected(employee_ids: Array[String]) -> void:
	GameLog.info("Game", "选中员工: %s" % str(employee_ids))

func _on_hand_card_dropped(employee_id: String, target: Control) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if employee_id.is_empty():
		return
	if not is_instance_valid(target):
		return

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	if state.phase != DefsClass.PHASE_RESTRUCTURING:
		return

	var actor_id := _get_effective_view_player_id(state, _view_player_id)
	if actor_id < 0:
		return
	if state.round_state is Dictionary:
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			var submitted_val = r.get("submitted", null)
			if submitted_val is Dictionary:
				var submitted: Dictionary = submitted_val
				var submitted_flag = submitted.get(actor_id, null)
				if submitted_flag == null and submitted.has(str(actor_id)):
					submitted_flag = submitted.get(str(actor_id), null)
				if bool(submitted_flag):
					return

	# 放到公司结构（经理下属区）
	if target.is_in_group("company_structure_reports_drop_target"):
		var manager_slot_index := -1
		if target.has_meta("manager_slot_index"):
			var mv = target.get_meta("manager_slot_index")
			if mv is int:
				manager_slot_index = int(mv)
			elif mv is float:
				var mf: float = float(mv)
				if mf == floor(mf):
					manager_slot_index = int(mf)
		if manager_slot_index < 0:
			GameLog.warn("Game", "无法获取经理槽位索引")
			return

		var manager_employee_id := ""
		if target.has_meta("manager_employee_id"):
			var m_id_val = target.get_meta("manager_employee_id")
			if m_id_val is String:
				manager_employee_id = str(m_id_val)
		if manager_employee_id.is_empty():
			GameLog.warn("Game", "无法获取该经理槽位的员工 id（manager_employee_id），无法分配下属")
			return

		var player := state.get_player(actor_id)
		var needs_direct_sync := true
		if not player.is_empty():
			var cs_val = player.get("company_structure", null)
			if cs_val is Dictionary:
				var cs: Dictionary = cs_val
				var struct_val = cs.get("structure", null)
				if struct_val is Array:
					var structure: Array = struct_val
					if manager_slot_index < structure.size():
						var entry_val = structure[manager_slot_index]
						if entry_val is Dictionary:
							var entry: Dictionary = entry_val
							var stored_id := str(entry.get("employee_id", ""))
							if stored_id == manager_employee_id and not stored_id.is_empty():
								needs_direct_sync = false

		# 当 UI 显示的“经理”与 state.company_structure.structure 不一致（或未初始化）时，
		# 先同步一次直属槽，避免 set_company_structure_report 直接失败/看起来“拖拽无效”。
		if needs_direct_sync:
			var init_r: Result = _execute_command.call(Command.create("set_company_structure_direct", actor_id, {
				"slot_index": manager_slot_index,
				"employee_id": manager_employee_id
			}))
			if not init_r.ok:
				GameLog.warn("Game", "初始化 CEO 直属槽失败: %s" % init_r.error)
				return

		var set_r: Result = _execute_command.call(Command.create("set_company_structure_report", actor_id, {
			"manager_slot_index": manager_slot_index,
			"employee_id": employee_id
		}))
		if not set_r.ok:
			GameLog.warn("Game", "设置经理下属失败: %s" % set_r.error)
		return

	# 放到公司结构（CEO 直属槽）
	if target.is_in_group("company_structure_direct_slot"):
		var slot_index := -1
		if target.has_method("get_slot_index"):
			var v = target.call("get_slot_index")
			if v is int:
				slot_index = int(v)
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					slot_index = int(f)
		if slot_index < 0:
			GameLog.warn("Game", "无法获取公司结构槽位索引")
			return

		var direct_r: Result = _execute_command.call(Command.create("set_company_structure_direct", actor_id, {
			"slot_index": slot_index,
			"employee_id": employee_id
		}))
		if not direct_r.ok:
			GameLog.warn("Game", "设置 CEO 直属槽失败: %s" % direct_r.error)
		return

	var to_reserve := false
	if is_instance_valid(_scene.hand_area):
		var ha: HandArea = _scene.hand_area
		var mode := ""
		if ha.has_method("get_display_mode"):
			mode = str(ha.call("get_display_mode"))

		# In restructuring, allow dropping anywhere within the reserve scroll area (issue_tracker #46).
		if mode == "restructuring":
			if target.is_in_group("hand_area_reserve_drop_target"):
				to_reserve = true
			elif is_instance_valid(ha.reserve_container):
				to_reserve = (target == ha.reserve_container) or ha.reserve_container.is_ancestor_of(target) or target.is_ancestor_of(ha.reserve_container)
		else:
			if is_instance_valid(ha.reserve_container):
				to_reserve = (target == ha.reserve_container) or ha.reserve_container.is_ancestor_of(target) or target.is_ancestor_of(ha.reserve_container)
			if is_instance_valid(ha.active_container):
				if (target == ha.active_container) or ha.active_container.is_ancestor_of(target) or target.is_ancestor_of(ha.active_container):
					to_reserve = false

	var move_r: Result = _execute_command.call(Command.create("restructure_employee", actor_id, {
		"employee_id": employee_id,
		"to_reserve": to_reserve
	}))
	if not move_r.ok:
		GameLog.warn("Game", "移动员工失败: %s" % move_r.error)

func _on_company_structure_changed(new_structure: Dictionary) -> void:
	GameLog.info("Game", "公司结构变更: %s" % str(new_structure))

func _hide_all_phase_panels(keep_selection: bool = false) -> void:
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

	if layout == POPUP_LAYOUT_DOCK_RIGHT and anim_manager.has_method("animate_slide_in"):
		anim_manager.call("animate_slide_in", panel, "right")
	elif anim_manager.has_method("animate_scale_bounce"):
		anim_manager.call("animate_scale_bounce", panel)

func _center_popup_in_viewport(panel: Control) -> void:
	if panel == null or _scene == null:
		return
	var viewport_size: Vector2 = _scene.get_viewport_rect().size
	var panel_size := _get_panel_size(panel)
	panel.position = (viewport_size - panel_size) / 2.0

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
		_hide_reserve_card_modal()
		_hide_turn_order_modal()
		_hide_restructuring_modal()
		_hide_fridge_keep_modal()
		return

	var current_player_id := state.get_current_player_id()
	var covered := _get_modal_cover_rect()

	# 储备卡选择（Setup/ReserveCards）
	if state.phase == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS and current_player_id >= 0:
		_show_reserve_card_modal(state, current_player_id, covered)
	else:
		_hide_reserve_card_modal()

	# 冰箱保留选择（Cleanup）
	var should_show_fridge_keep := false
	if state.phase == DefsClass.PHASE_CLEANUP and (state.round_state is Dictionary) and current_player_id >= 0:
		var rs: Dictionary = state.round_state
		var ppa_val = rs.get("pending_phase_actions", null)
		if ppa_val is Dictionary:
			var ppa: Dictionary = ppa_val
			var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
			if list_val is Array:
				var list: Array = list_val
				if not list.is_empty() and int(list[0]) == current_player_id:
					should_show_fridge_keep = true

	if should_show_fridge_keep:
		_show_fridge_keep_modal(state, current_player_id, covered)
	else:
		_hide_fridge_keep_modal()

	# 顺序选择（OrderOfBusiness）
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

	var should_show_turn_order := false
	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS and current_player_id >= 0:
		should_show_turn_order = not selections.values().has(current_player_id)

	if should_show_turn_order:
		_show_turn_order_modal(state, current_player_id, selections, covered)
	else:
		_hide_turn_order_modal()

	# 重组（Restructuring）
	var should_show_restructuring := false
	if state.phase == DefsClass.PHASE_RESTRUCTURING and state.players.size() > 0:
		var all_submitted := false
		if state.round_state is Dictionary:
			var r_val = state.round_state.get("restructuring", null)
			if r_val is Dictionary:
				var r: Dictionary = r_val
				var finalized_val = r.get("finalized", null)
				if finalized_val is bool and bool(finalized_val):
					all_submitted = true
				elif r.has("submitted") and (r["submitted"] is Dictionary):
					var submitted: Dictionary = r["submitted"]
					all_submitted = true
					for pid in range(state.players.size()):
						var v = submitted.get(pid, null)
						if v == null and submitted.has(str(pid)):
							v = submitted.get(str(pid), null)
						if not bool(v):
							all_submitted = false
							break
		should_show_restructuring = not all_submitted

	if should_show_restructuring:
		_show_restructuring_modal(covered)
		var view_player_id := _get_effective_view_player_id(state, _view_player_id)
		_sync_restructuring_modal_ui(state, view_player_id)
	else:
		_hide_restructuring_modal()

func _get_modal_cover_rect() -> Rect2:
	if _scene == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var center_split = _scene.get_node_or_null("UIRoot/MainContent/CenterSplit")
	if center_split is Control:
		var c: Control = center_split
		var gr := c.get_global_rect()
		var scene_global := Vector2.ZERO
		if _scene is Control:
			scene_global = (_scene as Control).global_position
		return Rect2(gr.position - scene_global, gr.size)

	return Rect2(Vector2.ZERO, _scene.get_viewport_rect().size)

func _initialize_modal(modal_ref, scene: PackedScene, signal_map: Dictionary):
	if _scene == null:
		return modal_ref
	if is_instance_valid(modal_ref):
		return modal_ref

	var inst = scene.instantiate()
	if not is_instance_valid(inst):
		return inst

	_scene.add_child(inst)
	if inst is Control:
		(inst as Control).z_index = 900

	for sig_name in signal_map.keys():
		var cb = signal_map.get(sig_name, null)
		if cb is Callable:
			UiSignalHelpersClass.safe_connect(inst, sig_name, cb)

	return inst

func _show_turn_order_modal_for_state(state: GameState) -> void:
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
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

	_show_turn_order_modal(state, current_player_id, selections, _get_modal_cover_rect())

func _show_turn_order_modal(state: GameState, current_player_id: int, selections: Dictionary, covered: Rect2) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_turn_order_modal = _initialize_modal(_turn_order_modal, TurnOrderSelectionModalScene, {
		"completed": _on_turn_order_modal_completed,
		"cancelled": _on_turn_order_modal_cancelled,
	})

	if not is_instance_valid(_turn_order_modal):
		return

	if _turn_order_modal.has_method("setup"):
		_turn_order_modal.call("setup", state, current_player_id, selections)
	if _turn_order_modal.has_method("open"):
		_turn_order_modal.call("open", covered)
	elif _turn_order_modal is Control:
		var c: Control = _turn_order_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _hide_turn_order_modal() -> void:
	if not is_instance_valid(_turn_order_modal):
		return
	if _turn_order_modal.has_method("close"):
		_turn_order_modal.call("close")
	elif _turn_order_modal is Control:
		(_turn_order_modal as Control).visible = false

func _on_turn_order_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_turn_order_modal):
		return

	var pos_val = result.get("position", null)
	var position := -1
	if pos_val is int:
		position = int(pos_val)
	elif pos_val is float:
		var f: float = float(pos_val)
		if f == floor(f):
			position = int(f)
	if position < 0:
		return

	if _turn_order_modal.has_method("set_confirm_enabled"):
		_turn_order_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return

	_execute_command.call(Command.create("choose_turn_order", current_player_id, {"position": position}))

func _on_turn_order_modal_cancelled() -> void:
	_hide_turn_order_modal()

func _show_reserve_card_modal(state: GameState, current_player_id: int, covered: Rect2) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_reserve_card_modal = _initialize_modal(_reserve_card_modal, ReserveCardSelectionModalScene, {
		"completed": _on_reserve_card_modal_completed,
	})

	if not is_instance_valid(_reserve_card_modal):
		return

	if _reserve_card_modal.has_method("setup"):
		_reserve_card_modal.call("setup", state, current_player_id)
	if _reserve_card_modal.has_method("open"):
		# 首次打开时 UI 布局可能尚未完成，CenterSplit 的 rect 会错误导致遮罩落在左上角；
		# 延迟一帧再重新计算覆盖区域并打开，确保首位玩家显示正常。
		if not _reserve_card_modal.visible:
			if _pending_reserve_card_open_player_id != current_player_id:
				_pending_reserve_card_open_player_id = current_player_id
				_pending_reserve_card_open_attempts = 0
			if not _reserve_card_open_routine_running:
				_reserve_card_open_routine_running = true
				call_deferred("_deferred_open_reserve_card_modal")
			return

		_reserve_card_modal.call("open", covered)
	elif _reserve_card_modal is Control:
		var c: Control = _reserve_card_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _deferred_open_reserve_card_modal() -> void:
	# 注意：call_deferred 只保证“当前调用栈之后”，不保证已完成容器布局；
	# 因此这里按帧等待并重算覆盖区域，避免首位玩家第一次弹窗落在左上角。
	while true:
		var expected_player_id := _pending_reserve_card_open_player_id
		if expected_player_id < 0:
			_reserve_card_open_routine_running = false
			return
		if _scene == null or _scene.game_engine == null:
			_reserve_card_open_routine_running = false
			return
		if not is_instance_valid(_reserve_card_modal):
			_reserve_card_open_routine_running = false
			return

		# 等待至少一帧，让 VBox/SplitContainer 等容器完成布局（位置/尺寸）。
		await _scene.get_tree().process_frame

		# 过程中可能发生状态变化，重新校验
		if _pending_reserve_card_open_player_id != expected_player_id:
			_pending_reserve_card_open_attempts = 0
			continue

		var state: GameState = _scene.game_engine.get_state()
		if state == null:
			_reserve_card_open_routine_running = false
			return
		if str(state.phase) != DefsClass.PHASE_SETUP or str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
			_pending_reserve_card_open_player_id = -1
			_pending_reserve_card_open_attempts = 0
			_reserve_card_open_routine_running = false
			return

		var current_player_id := state.get_current_player_id()
		if current_player_id != expected_player_id:
			_reserve_card_open_routine_running = false
			return

		var covered := _get_modal_cover_rect()

		# UI 布局刚完成前的一两帧，CenterSplit 的 rect 可能异常偏小（但非 0），导致遮罩落在左上角；
		# 这里最多等待几帧，直到覆盖区域尺寸接近 viewport（再打开）。
		var viewport_size = _scene.get_viewport_rect().size
		var should_retry := false
		if viewport_size.x > 1.0 and viewport_size.y > 1.0:
			if covered.size.x < viewport_size.x * 0.4 or covered.size.y < viewport_size.y * 0.4:
				should_retry = true
		else:
			should_retry = covered.size.x <= 1.0 or covered.size.y <= 1.0

		if should_retry and _pending_reserve_card_open_attempts < 8:
			_pending_reserve_card_open_attempts += 1
			continue

		_pending_reserve_card_open_player_id = -1
		_pending_reserve_card_open_attempts = 0
		_reserve_card_open_routine_running = false

		# 进入储备卡选择时再隐藏加载遮罩，避免“先闪一帧游戏 UI 再弹窗”的体验。
		if SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()

		if _reserve_card_modal.has_method("setup"):
			_reserve_card_modal.call("setup", state, current_player_id)
		if _reserve_card_modal.has_method("open"):
			_reserve_card_modal.call("open", covered)
		elif _reserve_card_modal is Control:
			var c: Control = _reserve_card_modal
			c.position = covered.position
			c.size = covered.size
			c.visible = true
		return

func _hide_reserve_card_modal() -> void:
	_pending_reserve_card_open_player_id = -1
	_pending_reserve_card_open_attempts = 0
	if not is_instance_valid(_reserve_card_modal):
		return
	if _reserve_card_modal.has_method("close"):
		_reserve_card_modal.call("close")
	elif _reserve_card_modal is Control:
		(_reserve_card_modal as Control).visible = false

func _on_reserve_card_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_reserve_card_modal):
		return

	var idx_val = result.get("selected_index", null)
	var selected_index := -1
	if idx_val is int:
		selected_index = int(idx_val)
	elif idx_val is float:
		var f: float = float(idx_val)
		if f == floor(f):
			selected_index = int(f)
	if selected_index < 0:
		return

	if _reserve_card_modal.has_method("set_confirm_enabled"):
		_reserve_card_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return

	_execute_command.call(Command.create("select_reserve_card", current_player_id, {"selected_index": selected_index}))

func _show_fridge_keep_modal(state: GameState, current_player_id: int, covered: Rect2) -> void:
	if _scene == null:
		return
	if state == null:
		return

	_fridge_keep_modal = _initialize_modal(_fridge_keep_modal, FridgeKeepModalScene, {
		"completed": _on_fridge_keep_modal_completed,
	})
	if not is_instance_valid(_fridge_keep_modal):
		return

	if _fridge_keep_modal.has_method("setup"):
		_fridge_keep_modal.call("setup", state, current_player_id)
	if _fridge_keep_modal.has_method("open"):
		_fridge_keep_modal.call("open", covered)
	elif _fridge_keep_modal is Control:
		var c: Control = _fridge_keep_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _hide_fridge_keep_modal() -> void:
	if not is_instance_valid(_fridge_keep_modal):
		return
	if _fridge_keep_modal.has_method("close"):
		_fridge_keep_modal.call("close")
	elif _fridge_keep_modal is Control:
		(_fridge_keep_modal as Control).visible = false

func _on_fridge_keep_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_fridge_keep_modal):
		return

	var keep_val = result.get("keep", {})
	var keep: Dictionary = keep_val if keep_val is Dictionary else {}

	if _fridge_keep_modal.has_method("set_confirm_enabled"):
		_fridge_keep_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		return
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return

	_execute_command.call(Command.create("choose_fridge_keep", current_player_id, {"keep": keep}))

func _show_restructuring_modal(covered: Rect2) -> void:
	if _scene == null:
		return

	_restructuring_modal = _initialize_modal(_restructuring_modal, RestructuringModalScene, {
		"completed": _on_restructuring_modal_completed,
		"cancelled": _on_restructuring_modal_cancelled,
		"player_selected": _on_view_player_selected,
	})
	if not is_instance_valid(_restructuring_modal):
		return

	var hand_area = _scene.get("hand_area")
	if is_instance_valid(hand_area) and _restructuring_modal.has_method("attach_hand_area"):
		_restructuring_modal.call("attach_hand_area", hand_area)
	var company_structure = _scene.get("company_structure")
	if is_instance_valid(company_structure) and _restructuring_modal.has_method("attach_company_structure"):
		_restructuring_modal.call("attach_company_structure", company_structure)

	if _restructuring_modal.has_method("open"):
		_restructuring_modal.call("open", covered)
	elif _restructuring_modal is Control:
		var c: Control = _restructuring_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _hide_restructuring_modal() -> void:
	if not is_instance_valid(_restructuring_modal):
		return

	if _restructuring_modal.has_method("close"):
		_restructuring_modal.call("close")
	elif _restructuring_modal is Control:
		(_restructuring_modal as Control).visible = false

	_restore_info_panels_after_restructuring()

func _ensure_employee_tree_panel() -> void:
	if _scene == null:
		return
	if is_instance_valid(_employee_tree_panel):
		return

	_employee_tree_panel = EmployeeTreeScene.instantiate()
	if not is_instance_valid(_employee_tree_panel):
		return
	_employee_tree_panel.visible = false
	_scene.add_child(_employee_tree_panel)
	if _employee_tree_panel is Control:
		(_employee_tree_panel as Control).z_index = 900
	if _employee_tree_panel.has_signal("closed"):
		if not _employee_tree_panel.closed.is_connected(_hide_employee_tree):
			_employee_tree_panel.closed.connect(_hide_employee_tree)

func _hide_employee_tree() -> void:
	if is_instance_valid(_employee_tree_panel):
		_employee_tree_panel.visible = false

func _get_current_map_skin():
	if _scene == null:
		return null
	var canvas = _scene.get("map_canvas")
	if is_instance_valid(canvas) and canvas.has_method("get_skin"):
		return canvas.call("get_skin")
	return null

func _ensure_milestone_full_screen_view() -> void:
	if _scene == null:
		return
	if is_instance_valid(_milestone_full_screen_view):
		return

	_milestone_full_screen_view = MilestoneFullScreenViewScene.instantiate()
	if not is_instance_valid(_milestone_full_screen_view):
		return
	_milestone_full_screen_view.visible = false
	_scene.add_child(_milestone_full_screen_view)

	if _milestone_full_screen_view is Control:
		var c: Control = _milestone_full_screen_view
		c.z_index = 900
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.offset_left = 0.0
		c.offset_top = 0.0
		c.offset_right = 0.0
		c.offset_bottom = 0.0

	UiSignalHelpersClass.safe_connect(_milestone_full_screen_view, "close_requested", _hide_milestone_full_screen_view)

func _hide_milestone_full_screen_view() -> void:
	if is_instance_valid(_milestone_full_screen_view):
		_milestone_full_screen_view.visible = false

func _ensure_reserve_area_full_screen_view() -> void:
	if _scene == null:
		return
	if is_instance_valid(_reserve_area_full_screen_view):
		return

	_reserve_area_full_screen_view = ReserveAreaFullScreenViewScene.instantiate()
	if not is_instance_valid(_reserve_area_full_screen_view):
		return
	_reserve_area_full_screen_view.visible = false
	_scene.add_child(_reserve_area_full_screen_view)

	if _reserve_area_full_screen_view is Control:
		var c: Control = _reserve_area_full_screen_view
		c.z_index = 900
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.offset_left = 0.0
		c.offset_top = 0.0
		c.offset_right = 0.0
		c.offset_bottom = 0.0

	UiSignalHelpersClass.safe_connect(_reserve_area_full_screen_view, "close_requested", _hide_reserve_area_full_screen_view)

func _hide_reserve_area_full_screen_view() -> void:
	if is_instance_valid(_reserve_area_full_screen_view):
		_reserve_area_full_screen_view.visible = false

func _restore_info_panels_after_restructuring() -> void:
	if _scene == null:
		return

	var hand_area = _scene.get("hand_area")
	var company_structure = _scene.get("company_structure")
	if not is_instance_valid(hand_area) and not is_instance_valid(company_structure):
		return

	var bottom_panel = _scene.get("bottom_panel")
	if not is_instance_valid(bottom_panel):
		return

	if is_instance_valid(hand_area):
		_reparent_control(hand_area, bottom_panel)
	if is_instance_valid(company_structure):
		_reparent_control(company_structure, bottom_panel)

func _reparent_control(node: Node, target_parent: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if target_parent == null or not is_instance_valid(target_parent):
		return
	if node.get_parent() == target_parent:
		return
	var old_parent := node.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(node)
	target_parent.add_child(node)

func _on_restructuring_modal_completed(result: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not is_instance_valid(_restructuring_modal):
		return

	if _restructuring_modal.has_method("set_confirm_enabled"):
		_restructuring_modal.call("set_confirm_enabled", false)

	var state: GameState = _scene.game_engine.get_state()
	if state == null:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return

	var actor_id := _get_effective_view_player_id(state, _view_player_id)
	if actor_id < 0:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return

	var exec_result = _execute_command.call(Command.create("submit_restructuring", actor_id, {}))
	if not (exec_result is Result):
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return
	if not (exec_result as Result).ok:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)

func _on_restructuring_modal_cancelled() -> void:
	_hide_restructuring_modal()

func _sync_restructuring_modal_ui(state: GameState, view_player_id: int) -> void:
	if not is_instance_valid(_restructuring_modal):
		return
	if state == null:
		return

	var submitted_count := 0
	var total := state.players.size()
	var view_submitted := false
	var submitted: Dictionary = {}

	if state.round_state is Dictionary:
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			var submitted_val = r.get("submitted", null)
			if submitted_val is Dictionary:
				submitted = submitted_val
				for pid in range(total):
					var v = submitted.get(pid, null)
					if v == null and submitted.has(str(pid)):
						v = submitted.get(str(pid), null)
					if bool(v):
						submitted_count += 1

				var v2 = submitted.get(view_player_id, null)
				if v2 == null and submitted.has(str(view_player_id)):
					v2 = submitted.get(str(view_player_id), null)
				view_submitted = bool(v2)

	if _restructuring_modal.has_method("set_player_switcher"):
		_restructuring_modal.call("set_player_switcher", total, view_player_id, submitted)

	var view_name = Globals.get_player_name(view_player_id) if Globals != null else ("玩家%d" % (view_player_id + 1))
	if _restructuring_modal.has_method("set_title_text"):
		_restructuring_modal.call("set_title_text", "公司结构重组（同时）｜查看: %s" % view_name)

	if _restructuring_modal.has_method("set_confirm_text"):
		_restructuring_modal.call("set_confirm_text", "已提交" if view_submitted else ("确认重组（%s）" % view_name))
	if _restructuring_modal.has_method("set_confirm_enabled"):
		_restructuring_modal.call("set_confirm_enabled", not view_submitted)

	if _restructuring_modal.has_method("set_status_text"):
		var view_status := "已提交" if view_submitted else "未提交"
		_restructuring_modal.call("set_status_text", "当前查看: %s（%s）｜提交进度: %d/%d｜可在上方切换玩家分别调整并提交" % [view_name, view_status, submitted_count, total])
