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

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _refresh_ui: Callable

var _working_panels = null
var _marketing_panels = null
var _placement_overlays = null
var _end_panels = null

func _init(scene, map_controller, overlay_controller, execute_command: Callable, refresh_ui: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_refresh_ui = refresh_ui

	var hide_all := Callable(self, "_hide_all_phase_panels")
	var center_popup := Callable(self, "_center_popup")

	_working_panels = WorkingPanelsClass.new(_scene, _execute_command, hide_all, center_popup, _overlay_controller)
	_marketing_panels = MarketingPanelsClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all, center_popup)
	_placement_overlays = PlacementOverlaysClass.new(_scene, _map_controller, _overlay_controller, _execute_command, hide_all)
	_end_panels = EndPanelsClass.new(_scene, _overlay_controller, _execute_command, hide_all, center_popup, _refresh_ui)

func connect_signals(action_panel, turn_order_track, hand_area, company_structure) -> void:
	if is_instance_valid(action_panel) and action_panel.has_signal("action_requested"):
		if not action_panel.action_requested.is_connected(on_action_requested):
			action_panel.action_requested.connect(on_action_requested)

	if is_instance_valid(turn_order_track) and turn_order_track.has_signal("position_selected"):
		if not turn_order_track.position_selected.is_connected(_on_turn_order_position_selected):
			turn_order_track.position_selected.connect(_on_turn_order_position_selected)

	if is_instance_valid(hand_area) and hand_area.has_signal("cards_selected"):
		if not hand_area.cards_selected.is_connected(_on_hand_cards_selected):
			hand_area.cards_selected.connect(_on_hand_cards_selected)
	if is_instance_valid(hand_area) and hand_area.has_signal("card_dropped"):
		if not hand_area.card_dropped.is_connected(_on_hand_card_dropped):
			hand_area.card_dropped.connect(_on_hand_card_dropped)

	if is_instance_valid(company_structure) and company_structure.has_signal("structure_changed"):
		if not company_structure.structure_changed.is_connected(_on_company_structure_changed):
			company_structure.structure_changed.connect(_on_company_structure_changed)

func reset_bank_break_tracking(state: GameState) -> void:
	if _end_panels != null:
		_end_panels.reset_bank_break_tracking(state)

func show_milestone_panel() -> void:
	if _working_panels != null:
		_working_panels.show_milestone_panel()

func sync(state: GameState) -> void:
	_update_ui_components(state)
	if _working_panels != null:
		_working_panels.sync(state)
	if _marketing_panels != null:
		_marketing_panels.sync(state)
	if _placement_overlays != null:
		_placement_overlays.sync(state)
	if _end_panels != null:
		_end_panels.sync(state)

func _update_ui_components(state: GameState) -> void:
	if _scene == null or state == null:
		return

	var current_player_id := state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	# 玩家面板
	if is_instance_valid(_scene.player_panel) and _scene.player_panel.has_method("set_game_state"):
		_scene.player_panel.set_game_state(state)
		if _scene.player_panel.has_method("set_current_player"):
			_scene.player_panel.set_current_player(current_player_id)

	# 顺序轨
	if is_instance_valid(_scene.turn_order_track):
		if _scene.turn_order_track.has_method("set_player_count"):
			_scene.turn_order_track.set_player_count(state.players.size())
		if _scene.turn_order_track.has_method("set_current_selections"):
			# 构建选择映射：position -> player_id
			# - OrderOfBusiness 阶段：使用 round_state.order_of_business.picks（position -> player_id/-1）
			# - 其他阶段：使用 state.turn_order（position -> player_id）
			var selections := {}
			if state.phase == "OrderOfBusiness" and (state.round_state is Dictionary):
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
			_scene.turn_order_track.set_current_selections(selections)
		if _scene.turn_order_track.has_method("set_selectable"):
			var can_select := state.phase == "OrderOfBusiness"
			_scene.turn_order_track.set_selectable(can_select, current_player_id)
			if can_select and _scene.turn_order_track.has_method("highlight_available_positions"):
				_scene.turn_order_track.highlight_available_positions()

	# 库存面板
	if is_instance_valid(_scene.inventory_panel) and _scene.inventory_panel.has_method("set_inventory"):
		var inventory: Dictionary = current_player.get("inventory", {})
		_scene.inventory_panel.set_inventory(inventory)
		if _scene.inventory_panel.has_method("set_fridge_capacity"):
			_scene.inventory_panel.set_fridge_capacity(_get_fridge_capacity_for_player(current_player))

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

		for e in Array(current_player.get("employees", [])):
			employees.append(str(e))
		for e in Array(current_player.get("reserve_employees", [])):
			reserve.append(str(e))
		for e in Array(current_player.get("busy_marketers", [])):
			busy.append(str(e))

		_scene.hand_area.set_employees(employees, reserve, busy)
		if _scene.hand_area.has_method("set_drag_enabled"):
			var enable_drag := (state.phase == "Restructuring" and int(state.round_number) > 1)
			if enable_drag and (state.round_state is Dictionary):
				var r_val = state.round_state.get("restructuring", null)
				if r_val is Dictionary:
					var r: Dictionary = r_val
					var submitted_val = r.get("submitted", null)
					if submitted_val is Dictionary:
						var submitted: Dictionary = submitted_val
						if bool(submitted.get(current_player_id, false)):
							enable_drag = false
			_scene.hand_area.set_drag_enabled(enable_drag)

	# 公司结构面板
	if is_instance_valid(_scene.company_structure) and _scene.company_structure.has_method("set_player_data"):
		_scene.company_structure.set_player_data(current_player)

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
		# 系统动作
		"advance_phase":
			_execute_command.call(Command.create_system("advance_phase", params))
		"skip":
			_execute_command.call(Command.create("skip", current_player_id, params))
		"choose_turn_order":
			if is_instance_valid(_scene.turn_order_track) and _scene.turn_order_track.has_method("highlight_available_positions"):
				_scene.turn_order_track.highlight_available_positions()

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
		"set_price", "set_luxury_price", "set_discount":
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
		"place_house", "add_garden":
			if _placement_overlays != null:
				_placement_overlays.show_house_placement(action_id, params)

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
	if state.phase != "Restructuring":
		return

	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
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
		_execute_command.call(Command.create("set_company_structure_report", current_player_id, {
			"manager_slot_index": manager_slot_index,
			"employee_id": employee_id
		}))
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
		_execute_command.call(Command.create("set_company_structure_direct", current_player_id, {
			"slot_index": slot_index,
			"employee_id": employee_id
		}))
		return

	var to_reserve := false
	if is_instance_valid(_scene.hand_area):
		if target == _scene.hand_area.reserve_container:
			to_reserve = true
		elif target == _scene.hand_area.active_container:
			to_reserve = false

	_execute_command.call(Command.create("restructure_employee", current_player_id, {
		"employee_id": employee_id,
		"to_reserve": to_reserve
	}))

func _on_company_structure_changed(new_structure: Dictionary) -> void:
	GameLog.info("Game", "公司结构变更: %s" % str(new_structure))

func _hide_all_phase_panels() -> void:
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
	if _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()

func _center_popup(panel: Control) -> void:
	if panel == null:
		return
	if _scene == null:
		return
	await _scene.get_tree().process_frame
	var viewport_size = _scene.get_viewport_rect().size
	var panel_size := panel.size
	panel.position = (viewport_size - panel_size) / 2

	# P2：弹窗动画（避免 headless 影响测试/资源回收）
	if OS.has_feature("headless"):
		return
	if not (_scene.has_method("get_ui_animation_manager")):
		return
	var anim_manager = _scene.call("get_ui_animation_manager")
	if anim_manager != null and anim_manager.has_method("animate_scale_bounce"):
		anim_manager.call("animate_scale_bounce", panel)
