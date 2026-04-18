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
var _last_refresh_token: String = ""

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
	_reset_refresh_token()

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(marketing_panel) or not marketing_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_MARKETING:
		marketing_panel.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		_reset_refresh_token()
		return

	var refresh_ctx := _build_refresh_context(state)
	if not bool(refresh_ctx.get("has_marketer", false)) or not bool(refresh_ctx.get("has_board", false)):
		marketing_panel.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		_reset_refresh_token()
		return

	var token := str(refresh_ctx.get("token", ""))
	if force_full_refresh or token != _last_refresh_token:
		_apply_refresh_context(state, refresh_ctx)

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
	var refresh_ctx := _build_refresh_context(state)
	if not bool(refresh_ctx.get("has_marketer", false)) or not bool(refresh_ctx.get("has_board", false)):
		_reset_refresh_token()
		return
	_apply_refresh_context(state, refresh_ctx)

	if _center_popup.is_valid():
		_center_popup.call(marketing_panel)
	marketing_panel.visible = true

func _reset_refresh_token() -> void:
	_last_refresh_token = ""

func _build_refresh_context(state: GameState) -> Dictionary:
	var marketer_entries: Array[Dictionary] = []
	var boards_by_type: Dictionary = {}
	if state == null:
		return {
			"marketer_entries": marketer_entries,
			"boards_by_type": boards_by_type,
			"has_marketer": false,
			"has_board": false,
			"token": "",
		}

	marketer_entries = _build_marketing_marketer_entries(state, state.get_current_player_id(), state.get_current_player())
	boards_by_type = _build_available_marketing_boards_by_type(state)

	var has_marketer := false
	var has_board := false
	var marketer_tokens: Array[String] = []
	for entry_val in marketer_entries:
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var remaining := int(entry.get("remaining", 0))
		if remaining > 0:
			has_marketer = true
		marketer_tokens.append("%d|%s|%s|%d|%d" % [
			int(entry.get("staff_id", -1)),
			str(entry.get("employee_type", entry.get("id", ""))).strip_edges(),
			str(entry.get("type", "")).strip_edges(),
			int(entry.get("max_duration", 0)),
			remaining,
		])
	marketer_tokens.sort()

	var board_tokens: Array[String] = []
	for tid_val in boards_by_type.keys():
		var tid := str(tid_val).strip_edges()
		if tid.is_empty():
			continue
		var nums: Array[String] = []
		var arr_val = boards_by_type.get(tid, null)
		if arr_val is Array:
			for bn_val in arr_val:
				var bn := -1
				if bn_val is int:
					bn = int(bn_val)
				elif bn_val is float:
					var f: float = float(bn_val)
					if f == floor(f):
						bn = int(f)
				if bn <= 0:
					continue
				nums.append(str(bn))
			nums.sort()
			if not nums.is_empty():
				has_board = true
		board_tokens.append("%s:%s" % [tid, ",".join(nums)])
	board_tokens.sort()

	return {
		"marketer_entries": marketer_entries,
		"boards_by_type": boards_by_type,
		"has_marketer": has_marketer,
		"has_board": has_board,
		"token": "%d|%d|%s|%s|%s|%s" % [
			int(state.get_current_player_id()),
			int(state.round_number),
			str(state.phase),
			str(state.sub_phase),
			";".join(marketer_tokens),
			";".join(board_tokens),
		],
	}

func _apply_refresh_context(state: GameState, refresh_ctx: Dictionary) -> void:
	if not is_instance_valid(marketing_panel) or state == null:
		return

	if marketing_panel.has_method("set_visual_modules") and (state.modules is Array):
		marketing_panel.set_visual_modules(Array(state.modules, TYPE_STRING, "", null))

	if _map_controller != null:
		_map_controller.clear_selection()
	if marketing_panel.has_method("clear_selection"):
		marketing_panel.clear_selection()
	if marketing_panel.has_method("set_map_selection_callback") and _map_controller != null:
		marketing_panel.set_map_selection_callback(Callable(_map_controller, "on_marketing_map_selection_requested"))
	if marketing_panel.has_method("set_available_boards"):
		marketing_panel.set_available_boards(refresh_ctx.get("boards_by_type", {}))
	if marketing_panel.has_method("set_available_marketers"):
		marketing_panel.set_available_marketers(refresh_ctx.get("marketer_entries", []))
	if marketing_panel.has_method("set_error"):
		marketing_panel.set_error("")

	_last_refresh_token = str(refresh_ctx.get("token", ""))

func _build_marketing_marketer_entries(state: GameState, current_player_id: int, current_player: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or current_player.is_empty():
		return out
	for provider_val in EmployeeRulesClass.get_marketers_for_working(state, current_player_id):
		if not (provider_val is Dictionary):
			continue
		var provider: Dictionary = provider_val
		var marketing_types_val = provider.get("marketing_types", [])
		if not (marketing_types_val is Array):
			continue
		for type_val in Array(marketing_types_val):
			var type_id := str(type_val).strip_edges()
			if type_id.is_empty():
				continue
			if int(provider.get("remaining", 0)) <= 0:
				continue
			var entry := provider.duplicate(true)
			entry["type"] = type_id
			out.append(entry)
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

func _on_marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int, rotation: int, axis: String, staff_id: int = -1) -> void:
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
	if staff_id > 0:
		params["staff_id"] = staff_id
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

		if is_instance_valid(marketing_panel) and marketing_panel.visible:
			sync(state_after, false)
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
				"staff_id": staff_id,
				"board_number": board_number,
				"product": product,
				"position": [position.x, position.y],
			})

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
