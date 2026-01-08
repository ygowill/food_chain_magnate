# Game scene：Working 阶段营销面板（地图选点/可用营销员/可用板件）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

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

func sync(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(marketing_panel) or not marketing_panel.visible:
		return
	if state.phase != "Working" or state.sub_phase != "Marketing":
		marketing_panel.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

func show_marketing_panel() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if marketing_panel == null:
		marketing_panel = MarketingPanelScene.instantiate()
		if marketing_panel.has_signal("marketing_requested"):
			marketing_panel.marketing_requested.connect(_on_marketing_requested)
		if marketing_panel.has_signal("cancelled"):
			marketing_panel.cancelled.connect(_on_cancelled)
		_scene.add_child(marketing_panel)
		if _map_controller != null:
			_map_controller.set_marketing_panel(marketing_panel)

	var state = _scene.game_engine.get_state()
	var current_player: Dictionary = state.get_current_player()

	if _map_controller != null:
		_map_controller.clear_selection()

	if marketing_panel.has_method("clear_selection"):
		marketing_panel.clear_selection()

	if marketing_panel.has_method("set_map_selection_callback") and _map_controller != null:
		marketing_panel.set_map_selection_callback(Callable(_map_controller, "on_marketing_map_selection_requested"))

	if marketing_panel.has_method("set_available_marketers"):
		marketing_panel.set_available_marketers(_build_marketing_marketer_entries(current_player))

	if marketing_panel.has_method("set_available_boards"):
		marketing_panel.set_available_boards(_build_available_marketing_boards_by_type(state))

	marketing_panel.visible = true
	if _center_popup.is_valid():
		_center_popup.call(marketing_panel)

func _build_marketing_marketer_entries(current_player: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current_player.is_empty():
		return out
	if not EmployeeRegistryClass.is_loaded():
		return out

	var employees_val = current_player.get("employees", null)
	if not (employees_val is Array):
		return out
	var employees: Array = employees_val

	var busy_val = current_player.get("busy_marketers", [])
	var busy: Array = busy_val if busy_val is Array else []

	var employee_counts: Dictionary = {}
	for e in employees:
		if not (e is String):
			continue
		var emp_id := str(e)
		if emp_id.is_empty():
			continue
		employee_counts[emp_id] = int(employee_counts.get(emp_id, 0)) + 1

	var busy_counts: Dictionary = {}
	for b in busy:
		if not (b is String):
			continue
		var emp_id2 := str(b)
		if emp_id2.is_empty():
			continue
		busy_counts[emp_id2] = int(busy_counts.get(emp_id2, 0)) + 1

	for emp_id3_val in employee_counts.keys():
		var emp_id3 := str(emp_id3_val)
		if emp_id3.is_empty():
			continue
		var total_count := int(employee_counts.get(emp_id3, 0))
		var busy_count := int(busy_counts.get(emp_id3, 0))
		var available_count := maxi(0, total_count - busy_count)
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

func _on_marketing_requested(employee_type: String, board_number: int, position: Vector2i, product: String, duration: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("initiate_marketing", current_player_id, {
		"employee_type": employee_type,
		"board_number": board_number,
		"position": [position.x, position.y],
		"product": product,
		"duration": duration
	}))

	if result.ok:
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		if _hide_all.is_valid():
			_hide_all.call()

func _on_cancelled() -> void:
	if _hide_all.is_valid():
		_hide_all.call()
