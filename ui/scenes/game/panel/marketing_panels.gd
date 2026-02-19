# Game scene：Working 阶段营销面板（地图选点/可用营销员/可用板件）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const MarketingPanelScene = preload("res://ui/components/marketing_panel/marketing_panel.tscn")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _hide_all: Callable
var _center_popup: Callable

var marketing_panel = null

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup

func hide() -> void:
	if is_instance_valid(marketing_panel):
		marketing_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(marketing_panel) or not marketing_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_MARKETING:
		marketing_panel.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	# 时间线变化：保持面板打开，但强制从 state 全量刷新，避免残留旧 UI/选点缓存。
	if force_full_refresh:
		var current_player: Dictionary = state.get_current_player()

		if marketing_panel.has_method("set_visual_modules") and (state.modules is Array):
			marketing_panel.set_visual_modules(Array(state.modules, TYPE_STRING, "", null))

		if _map_controller != null:
			_map_controller.clear_selection()
		if marketing_panel.has_method("clear_selection"):
			marketing_panel.clear_selection()
		if marketing_panel.has_method("set_map_selection_callback") and _map_controller != null:
			marketing_panel.set_map_selection_callback(Callable(_map_controller, "on_marketing_map_selection_requested"))

		if marketing_panel.has_method("set_available_marketers"):
			marketing_panel.set_available_marketers(_build_marketing_marketer_entries(state, state.get_current_player_id(), current_player))

		if marketing_panel.has_method("set_available_boards"):
			marketing_panel.set_available_boards(_build_available_marketing_boards_by_type(state))

func show_marketing_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if marketing_panel == null:
		marketing_panel = MarketingPanelScene.instantiate()
		marketing_panel.visible = false
		marketing_panel.set_meta("popup_layout", "dock_right")
		marketing_panel.set_meta("popup_title", "营销")
		if marketing_panel.has_signal("marketing_requested"):
			marketing_panel.marketing_requested.connect(_on_marketing_requested)
		if marketing_panel.has_signal("cancelled"):
			marketing_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(marketing_panel)
		if _map_controller != null:
			_map_controller.set_marketing_panel(marketing_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if marketing_panel.has_method("set_visual_modules") and (state.modules is Array):
		marketing_panel.set_visual_modules(Array(state.modules, TYPE_STRING, "", null))

	if _map_controller != null:
		_map_controller.clear_selection()

	if marketing_panel.has_method("clear_selection"):
		marketing_panel.clear_selection()

	if marketing_panel.has_method("set_map_selection_callback") and _map_controller != null:
		marketing_panel.set_map_selection_callback(Callable(_map_controller, "on_marketing_map_selection_requested"))

	if marketing_panel.has_method("set_available_marketers"):
		marketing_panel.set_available_marketers(_build_marketing_marketer_entries(state, state.get_current_player_id(), current_player))

	if marketing_panel.has_method("set_available_boards"):
		marketing_panel.set_available_boards(_build_available_marketing_boards_by_type(state))

	if _center_popup.is_valid():
		_center_popup.call(marketing_panel)
	marketing_panel.visible = true

func _build_marketing_marketer_entries(state: GameState, current_player_id: int, current_player: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or current_player.is_empty():
		return out
	if not EmployeeRegistryClass.is_loaded():
		return out

	var employees_val = current_player.get("employees", null)
	if not (employees_val is Array):
		return out
	var employees: Array = employees_val

	var active_counts: Dictionary = {}
	for e in employees:
		if not (e is String):
			continue
		var emp_id := str(e)
		if emp_id.is_empty():
			continue
		active_counts[emp_id] = int(active_counts.get(emp_id, 0)) + 1

	# 额外次数：某些效果（如夜班经理）允许“本回合刚变忙碌”的营销员再发起一次营销。
	# 约束：仅统计 created_round == state.round_number 的营销实例，避免把跨回合的忙碌营销员误判为可用。
	var extra_uses_by_employee: Dictionary = {}
	if state.marketing_instances is Array:
		var groups_by_emp: Dictionary = {}  # employee_type -> { link_id -> count }
		for inst_val in state.marketing_instances:
			if not (inst_val is Dictionary):
				continue
			var inst: Dictionary = inst_val
			if int(inst.get("owner", -1)) != current_player_id:
				continue
			if int(inst.get("created_round", -1)) != state.round_number:
				continue
			var emp_id2 := str(inst.get("employee_type", "")).strip_edges()
			if emp_id2.is_empty():
				continue
			var link_id := str(inst.get("link_id", "")).strip_edges()
			if link_id.is_empty():
				continue
			if not groups_by_emp.has(emp_id2):
				groups_by_emp[emp_id2] = {}
			var per: Dictionary = groups_by_emp[emp_id2]
			per[link_id] = int(per.get(link_id, 0)) + 1
			groups_by_emp[emp_id2] = per

		for emp_id3_val in groups_by_emp.keys():
			var emp_id3 := str(emp_id3_val)
			if emp_id3.is_empty():
				continue
			var mult := maxi(1, EmployeeRulesClass.get_working_employee_multiplier(state, current_player_id, emp_id3))
			if mult <= 1:
				continue
			var per2: Dictionary = groups_by_emp[emp_id3]
			var extra := 0
			for k in per2.keys():
				extra += maxi(0, mult - int(per2.get(k, 0)))
			if extra > 0:
				extra_uses_by_employee[emp_id3] = extra

	var all_ids: Dictionary = {}
	for k in active_counts.keys():
		all_ids[str(k)] = true
	for k2 in extra_uses_by_employee.keys():
		all_ids[str(k2)] = true

	var ids: Array[String] = []
	for k3 in all_ids.keys():
		ids.append(str(k3))
	ids.sort()

	for emp_id4 in ids:
		var emp_id3 := str(emp_id4)
		var available_count := int(active_counts.get(emp_id3, 0)) + int(extra_uses_by_employee.get(emp_id3, 0))
		if available_count <= 0:
			continue

		var def_val = EmployeeRegistryClass.get_def(emp_id3)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		var max_duration := int(def.marketing_max_duration)
		if max_duration <= 0:
			continue

		var marketing_types: Array[String] = []
		var type_set: Dictionary = {}
		for tag in def.usage_tags:
			var t := str(tag)
			if not t.begins_with("use:marketing:"):
				continue
			var type_id := t.substr("use:marketing:".length())
			if type_id.is_empty():
				continue
			type_set[type_id] = true
		for k in type_set.keys():
			marketing_types.append(str(k))
		marketing_types.sort()

		for mt in marketing_types:
			for i in range(available_count):
				out.append({
					"id": emp_id3,
					"type": mt,
					"max_duration": max_duration,
				})

	return out

func _build_available_marketing_boards_by_type(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	if not MarketingRegistryClass.is_loaded():
		return out

	var used: Dictionary = {}

	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		var bn_val = inst.get("board_number", null)
		if bn_val is int:
			used[int(bn_val)] = true
		elif bn_val is float:
			var f: float = float(bn_val)
			if f == floor(f):
				used[int(f)] = true

	if state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			if not (k is String):
				continue
			var s := str(k)
			if not s.is_valid_int():
				continue
			var bn := int(s)
			if bn > 0:
				used[bn] = true

	var player_count := state.players.size()
	for bn2 in MarketingRegistryClass.get_all_board_numbers():
		if used.has(bn2):
			continue
		var def_val2 = MarketingRegistryClass.get_def(bn2)
		if def_val2 == null or not def_val2.has_method("is_available_for_player_count"):
			continue
		if not def_val2.is_available_for_player_count(player_count):
			continue
		var type_id2 := str(def_val2.type)
		if type_id2.is_empty():
			continue
		if not out.has(type_id2):
			out[type_id2] = []
		var arr: Array = out[type_id2]
		arr.append(bn2)
		out[type_id2] = arr

	for tid in out.keys():
		var arr2: Array = out[tid]
		arr2.sort()
		out[tid] = arr2

	return out

func _on_marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int, rotation: int, axis: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var params := {
		"employee_type": employee_type,
		"board_number": board_number,
		"position": [position.x, position.y],
		"product": product,
		"duration": duration
	}
	if rotation != 0:
		params["rotation"] = rotation
	if not axis.is_empty():
		params["axis"] = axis
	var result: Result = _execute_command.call(Command.create("initiate_marketing", current_player_id, params))

	if result.ok:
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		var state_after: GameState = _scene.game_engine.get_state()
		if state_after == null:
			if _hide_all.is_valid():
				_hide_all.call()
			return

		# 营销成功后优先保持面板打开并刷新（若仍可继续发起），避免出现“动作面板瞬时空白”。
		if is_instance_valid(marketing_panel) and marketing_panel.visible:
			if state_after.phase != DefsClass.PHASE_WORKING or state_after.sub_phase != DefsClass.SUB_PHASE_MARKETING:
				if _hide_all.is_valid():
					_hide_all.call()
				return

			var current_player_after: Dictionary = state_after.get_current_player()
			var marketer_entries := _build_marketing_marketer_entries(state_after, state_after.get_current_player_id(), current_player_after)
			var boards_by_type := _build_available_marketing_boards_by_type(state_after)
			var has_marketer := not marketer_entries.is_empty()
			var has_board := false
			for tid in boards_by_type.keys():
				var arr_val = boards_by_type.get(tid, null)
				if arr_val is Array and not (arr_val as Array).is_empty():
					has_board = true
					break

			if not (has_marketer and has_board):
				if _hide_all.is_valid():
					_hide_all.call()
				return

			if marketing_panel.has_method("clear_selection"):
				marketing_panel.clear_selection()
			if marketing_panel.has_method("set_available_marketers"):
				marketing_panel.set_available_marketers(marketer_entries)
			if marketing_panel.has_method("set_available_boards"):
				marketing_panel.set_available_boards(boards_by_type)
			if marketing_panel.has_method("set_map_selection_callback") and _map_controller != null:
				marketing_panel.set_map_selection_callback(Callable(_map_controller, "on_marketing_map_selection_requested"))
			if marketing_panel.has_method("set_error"):
				marketing_panel.set_error("")
		else:
			if _hide_all.is_valid():
				_hide_all.call()
	else:
		if is_instance_valid(marketing_panel) and marketing_panel.visible:
			if marketing_panel.has_method("set_error"):
				marketing_panel.set_error(str(result.error))

		var log_panel = _scene.get("game_log_panel") if _scene != null else null
		if is_instance_valid(log_panel) and log_panel.has_method("add_event_log"):
			log_panel.add_event_log("营销放置失败：%s" % str(result.error), {
				"action_id": "initiate_marketing",
				"player_id": current_player_id,
				"employee_type": employee_type,
				"board_number": board_number,
				"product": product,
				"position": [position.x, position.y],
			})

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
