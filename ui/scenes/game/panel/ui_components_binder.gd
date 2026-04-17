# GamePanelController：基础 UI 组件数据绑定
# - 玩家面板/左侧信息面板
# - 顺序轨/顺序展示
# - 库存/动作面板
# - 员工手牌区/公司结构（含重组拖拽开关）
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _controller_ref: WeakRef
var _last_action_panel_map_skin = null
var _last_action_panel_registry = null
var _has_action_panel_map_skin: bool = false
var _has_action_panel_registry: bool = false

func _init(controller) -> void:
	_controller_ref = weakref(controller)

func dispose() -> void:
	_controller_ref = null
	_last_action_panel_map_skin = null
	_last_action_panel_registry = null
	_has_action_panel_map_skin = false
	_has_action_panel_registry = false

func _get_controller():
	if _controller_ref == null:
		return null
	return _controller_ref.get_ref()

func sync(state: GameState) -> void:
	var controller = _get_controller()
	if controller == null:
		return
	var scene = controller._scene
	if scene == null or state == null:
		return

	var current_player_id := state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	var is_online := false
	var local_player_id := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_player_id = int(NetContext.local_player_id)

	var requested_view_player_id := int(controller._view_player_id)
	# 联机模式：当未显式选择“查看玩家”时，默认查看自己（避免默认跟随 current_player 造成误导/代操风险）。
	if is_online and requested_view_player_id < 0 and local_player_id >= 0:
		requested_view_player_id = local_player_id
		controller._view_player_id = int(local_player_id)
	var view_player_id := int(controller._get_effective_view_player_id(state, requested_view_player_id))
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
						view_player_id = int(picked)
						controller._view_player_id = int(picked)

			# Restructuring：隐私规则（Online 仅自己；Hotseat 已提交锁定）
			if str(state.phase) == DefsClass.PHASE_RESTRUCTURING and controller._restructuring_controller != null:
				var adjusted = controller._restructuring_controller.apply_view_privacy(state, view_player_id)
				if adjusted != view_player_id:
					view_player_id = int(adjusted)
					controller._view_player_id = int(adjusted)

	var view_player: Dictionary = current_player
	if view_player_id >= 0 and view_player_id < state.players.size():
		var vp_val = state.players[view_player_id]
		if vp_val is Dictionary:
			view_player = Dictionary(vp_val)

	# 玩家面板
	if is_instance_valid(scene.player_panel) and scene.player_panel.has_method("set_game_state"):
		if scene.player_panel.has_method("set_display_context"):
			scene.player_panel.set_display_context(state, current_player_id, view_player_id)
		else:
			scene.player_panel.set_game_state(state)
			if scene.player_panel.has_method("set_current_player"):
				scene.player_panel.set_current_player(current_player_id)
			if scene.player_panel.has_method("set_view_player"):
				scene.player_panel.set_view_player(view_player_id)

	# 左侧信息面板（P3：骨架）
	if is_instance_valid(scene.left_panel):
		if scene.left_panel.has_method("set_display_context"):
			scene.left_panel.set_display_context(state, current_player_id, view_player_id)
		else:
			if scene.left_panel.has_method("set_game_state"):
				scene.left_panel.set_game_state(state)
			if scene.left_panel.has_method("set_current_player"):
				scene.left_panel.set_current_player(current_player_id)

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

		if is_instance_valid(scene.turn_order_track):
			if scene.turn_order_track.has_method("set_player_count"):
				scene.turn_order_track.set_player_count(state.players.size())
			if scene.turn_order_track.has_method("set_current_selections"):
				scene.turn_order_track.set_current_selections(selections)
			if scene.turn_order_track.has_method("set_selectable"):
				# 新布局(v2)：顺序选择使用遮罩面板；右侧 TurnOrderTrack 不再承担交互入口。
				scene.turn_order_track.set_selectable(false, current_player_id)
				if scene.turn_order_track is Control:
					(scene.turn_order_track as Control).visible = false

	# 顶部顺序显示（展示用）
	if is_instance_valid(scene.turn_order_display):
		if scene.turn_order_display.has_method("set_display_context"):
			scene.turn_order_display.set_player_count(state.players.size())
			scene.turn_order_display.set_display_context(state, selections, current_player_id)
		else:
			if scene.turn_order_display.has_method("set_game_state"):
				scene.turn_order_display.set_game_state(state)
			if scene.turn_order_display.has_method("set_player_count"):
				scene.turn_order_display.set_player_count(state.players.size())
			if scene.turn_order_display.has_method("set_current_selections"):
				scene.turn_order_display.set_current_selections(selections)
			if scene.turn_order_display.has_method("set_current_player"):
				scene.turn_order_display.set_current_player(current_player_id)

	# 库存面板
	if is_instance_valid(scene.inventory_panel) and scene.inventory_panel.has_method("set_inventory"):
		var inventory: Dictionary = view_player.get("inventory", {})
		if scene.inventory_panel.has_method("set_visual_modules") and (state.modules is Array):
			scene.inventory_panel.set_visual_modules(Array(state.modules, TYPE_STRING, "", null))
		scene.inventory_panel.set_inventory(inventory)
		if scene.inventory_panel.has_method("set_fridge_capacity"):
			scene.inventory_panel.set_fridge_capacity(_get_fridge_capacity_for_player(view_player))

	# 动作面板
	if is_instance_valid(scene.action_panel):
		var action_player_id := current_player_id
		if is_online and local_player_id >= 0:
			action_player_id = local_player_id
		if scene.action_panel.has_method("set_display_context"):
			scene.action_panel.set_display_context(state, action_player_id)
		else:
			if scene.action_panel.has_method("set_game_state"):
				scene.action_panel.set_game_state(state)
			if scene.action_panel.has_method("set_current_player"):
				scene.action_panel.set_current_player(action_player_id)
		var current_map_skin = controller._get_current_map_skin()
		if scene.action_panel.has_method("set_map_skin") and ((not _has_action_panel_map_skin) or current_map_skin != _last_action_panel_map_skin):
			_has_action_panel_map_skin = true
			_last_action_panel_map_skin = current_map_skin
			scene.action_panel.set_map_skin(current_map_skin)
		if scene.action_panel.has_method("set_action_registry"):
			var registry = scene.game_engine.get_action_registry() if scene.game_engine != null and scene.game_engine.has_method("get_action_registry") else null
			if (not _has_action_panel_registry) or registry != _last_action_panel_registry:
				_has_action_panel_registry = true
				_last_action_panel_registry = registry
				scene.action_panel.set_action_registry(registry)

	# 员工手牌区
	if is_instance_valid(scene.hand_area) and scene.hand_area.has_method("set_employees"):
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

		scene.hand_area.set_employees(employees, reserve, busy)

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

		if scene.hand_area.has_method("set_drag_enabled"):
			scene.hand_area.set_drag_enabled(enable_drag)
		if is_instance_valid(scene.company_structure) and scene.company_structure.has_method("set_drag_enabled"):
			scene.company_structure.set_drag_enabled(enable_drag)

	# 公司结构面板
	if is_instance_valid(scene.company_structure) and scene.company_structure.has_method("set_player_data"):
		scene.company_structure.set_player_data(view_player)

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
