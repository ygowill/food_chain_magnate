# Game scene：放置覆盖层（餐厅/住宅/花园/板块）
extends RefCounted

const RestaurantPlacementScene = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.tscn")
const HousePlacementScene = preload("res://ui/components/house_placement/house_placement_overlay.tscn")
const PiecePlacementScene = preload("res://ui/components/piece_placement/piece_placement_overlay.tscn")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _hide_all: Callable

var restaurant_placement_overlay = null
var house_placement_overlay = null
var piece_placement_overlay = null

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func hide() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if is_instance_valid(piece_placement_overlay):
		piece_placement_overlay.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_sync_restaurant_placement_overlay(state, force_full_refresh)
	_sync_house_placement_overlay(state, force_full_refresh)
	_sync_piece_placement_overlay(state, force_full_refresh)

func _sync_restaurant_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return

	var allowed := false
	if state.phase == DefsClass.PHASE_SETUP:
		allowed = true
	elif state.phase == DefsClass.PHASE_WORKING and state.sub_phase == DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		allowed = true

	if not allowed:
		restaurant_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	# 时间线变化：保持覆盖层打开，但从 state 强制刷新可用员工/地图数据，避免残留旧 UI/选点缓存。
	if force_full_refresh:
		var current_player_id := state.get_current_player_id()
		var current_player: Dictionary = state.get_current_player()

		var action_id := "place_restaurant"
		if restaurant_placement_overlay.has_method("get_mode"):
			action_id = str(restaurant_placement_overlay.get_mode())

		var prev_employee := ""
		if restaurant_placement_overlay.has_method("get_selected_employee"):
			prev_employee = str(restaurant_placement_overlay.get_selected_employee()).strip_edges()
		var prev_restaurant := ""
		if restaurant_placement_overlay.has_method("get_selected_restaurant"):
			prev_restaurant = str(restaurant_placement_overlay.get_selected_restaurant()).strip_edges()

		if _map_controller != null:
			_map_controller.begin_selection("restaurant_placement", {"action_id": action_id})
			if _map_controller.has_method("on_restaurant_preview_cleared"):
				_map_controller.on_restaurant_preview_cleared()

		if restaurant_placement_overlay.has_method("set_map_data"):
			restaurant_placement_overlay.set_map_data(state.map)

		if action_id == "move_restaurant":
			if restaurant_placement_overlay.has_method("set_available_restaurants"):
				var ids: Array[String] = []
				for rid in Array(current_player.get("restaurants", [])):
					ids.append(str(rid))
				restaurant_placement_overlay.set_available_restaurants(ids)
			if restaurant_placement_overlay.has_method("set_selected_restaurant") and not prev_restaurant.is_empty():
				restaurant_placement_overlay.set_selected_restaurant(prev_restaurant)

		if restaurant_placement_overlay.has_method("set_available_employees"):
			var usage_tag := ""
			if state.phase == DefsClass.PHASE_WORKING:
				usage_tag = "use:move_restaurant" if action_id == "move_restaurant" else "use:place_restaurant"
			restaurant_placement_overlay.set_available_employees(
				_get_active_employee_types_with_usage_tag(state, current_player_id, usage_tag)
			)
			if restaurant_placement_overlay.has_method("set_selected_employee") and not prev_employee.is_empty():
				restaurant_placement_overlay.set_selected_employee(prev_employee)

		if restaurant_placement_overlay.has_method("get_selected_rotation") and restaurant_placement_overlay.has_method("set_selected_rotation"):
			var r := int(restaurant_placement_overlay.get_selected_rotation())
			restaurant_placement_overlay.set_selected_rotation(r)

func _sync_house_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(house_placement_overlay) or not house_placement_overlay.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_HOUSES:
		house_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	# 时间线变化：保持覆盖层打开，但从 state 强制刷新可用员工/地图数据，避免残留旧 UI/选点缓存。
	if force_full_refresh:
		var current_player_id := state.get_current_player_id()

		var action_id := "place_house"
		if house_placement_overlay.has_method("get_mode"):
			action_id = str(house_placement_overlay.get_mode())

		var prev_employee := ""
		if house_placement_overlay.has_method("get_selected_employee"):
			prev_employee = str(house_placement_overlay.get_selected_employee()).strip_edges()

		if _map_controller != null:
			_map_controller.begin_selection("house_placement", {"action_id": action_id})
			if _map_controller.has_method("on_house_preview_cleared"):
				_map_controller.on_house_preview_cleared()

		if house_placement_overlay.has_method("set_map_data"):
			house_placement_overlay.set_map_data(state.map)

		if house_placement_overlay.has_method("set_available_employees"):
			var usage_tag := ""
			if state.phase == DefsClass.PHASE_WORKING:
				usage_tag = "use:add_garden" if action_id == "add_garden" else "use:place_house"
			house_placement_overlay.set_available_employees(
				_get_active_employee_types_with_usage_tag(state, current_player_id, usage_tag)
			)
			if house_placement_overlay.has_method("set_selected_employee") and not prev_employee.is_empty():
				house_placement_overlay.set_selected_employee(prev_employee)

		if house_placement_overlay.has_method("get_selected_rotation") and house_placement_overlay.has_method("set_selected_rotation"):
			var r := int(house_placement_overlay.get_selected_rotation())
			house_placement_overlay.set_selected_rotation(r)

func _sync_piece_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(piece_placement_overlay) or not piece_placement_overlay.visible:
		return
	if _scene == null or _scene.game_engine == null:
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	var engine: GameEngine = _scene.game_engine
	var action_id := ""
	if piece_placement_overlay.has_method("get_mode"):
		action_id = str(piece_placement_overlay.get_mode()).strip_edges()
	if action_id.is_empty():
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	var executor = engine.get_action_registry().get_executor(action_id)
	var allowed := executor != null
	if allowed and (executor.allowed_phases is Array) and not executor.allowed_phases.is_empty():
		allowed = executor.allowed_phases.has(state.phase)
	if allowed and (executor.allowed_sub_phases is Array) and not executor.allowed_sub_phases.is_empty() and not str(state.sub_phase).is_empty():
		allowed = executor.allowed_sub_phases.has(state.sub_phase)

	if not allowed:
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	if not force_full_refresh:
		return

	# 时间线变化：保持覆盖层打开，重新同步选点模式与高亮/预览（避免残留旧 state 缓存）。
	var selected_pos: Vector2i = Vector2i(-1, -1)
	var selected_rot := 0
	var selected_piece := ""
	if piece_placement_overlay.has_method("get_selected_position"):
		selected_pos = piece_placement_overlay.get_selected_position()
	if piece_placement_overlay.has_method("get_selected_rotation"):
		selected_rot = int(piece_placement_overlay.get_selected_rotation())
	if piece_placement_overlay.has_method("get_selected_piece"):
		selected_piece = str(piece_placement_overlay.get_selected_piece()).strip_edges()

	if _map_controller != null:
		_map_controller.begin_selection("piece_placement", {"action_id": action_id})
		if _map_controller.has_method("on_piece_highlight_requested"):
			_map_controller.on_piece_highlight_requested(action_id, selected_rot, selected_piece)
		if selected_pos != Vector2i(-1, -1) and _map_controller.has_method("on_piece_preview_requested"):
			_map_controller.on_piece_preview_requested(action_id, selected_pos, selected_rot, selected_piece)
		elif _map_controller.has_method("on_piece_preview_cleared"):
			_map_controller.on_piece_preview_cleared()

func try_show_piece_placement(action_id: String, params: Dictionary) -> bool:
	if _scene == null or _scene.game_engine == null:
		return false

	var ex = _scene.game_engine.get_action_registry().get_executor(action_id)
	if ex == null:
		return false

	var piece_ids: Array[String] = []
	var ids_val = ex.ui_piece_ids
	if ids_val is Array:
		for v in Array(ids_val):
			var s := str(v).strip_edges()
			if not s.is_empty():
				piece_ids.append(s)
	if piece_ids.is_empty():
		return false

	show_piece_placement(action_id, piece_ids, params)
	return true

func show_piece_placement(action_id: String, piece_ids: Array[String], params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if piece_placement_overlay == null:
		piece_placement_overlay = PiecePlacementScene.instantiate()
		if piece_placement_overlay.has_signal("placement_confirmed"):
			piece_placement_overlay.placement_confirmed.connect(_on_piece_placement_confirmed)
		if piece_placement_overlay.has_signal("cancelled"):
			piece_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if piece_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			piece_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_piece_preview_requested"))
		if piece_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			piece_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_piece_preview_cleared"))
		if piece_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			piece_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_piece_highlight_requested"))
		_scene.add_child(piece_placement_overlay)
		if _map_controller != null and _map_controller.has_method("set_piece_placement_overlay"):
			_map_controller.set_piece_placement_overlay(piece_placement_overlay)

	if _map_controller != null:
		_map_controller.begin_selection("piece_placement", {"action_id": action_id})
	piece_placement_overlay.visible = true

	if piece_placement_overlay.has_method("set_mode"):
		piece_placement_overlay.set_mode(action_id)
	if piece_placement_overlay.has_method("set_available_pieces"):
		piece_placement_overlay.set_available_pieces(piece_ids)

	if params.has("piece_id") and piece_placement_overlay.has_method("set_selected_piece"):
		piece_placement_overlay.set_selected_piece(str(params.piece_id))
	if params.has("rotation") and piece_placement_overlay.has_method("set_selected_rotation"):
		piece_placement_overlay.set_selected_rotation(int(params.rotation))

	if _map_controller != null and _map_controller.has_method("on_piece_preview_cleared"):
		_map_controller.on_piece_preview_cleared()

func show_restaurant_placement(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if restaurant_placement_overlay == null:
		restaurant_placement_overlay = RestaurantPlacementScene.instantiate()
		if restaurant_placement_overlay.has_signal("placement_confirmed"):
			restaurant_placement_overlay.placement_confirmed.connect(_on_restaurant_placement_confirmed)
		if restaurant_placement_overlay.has_signal("cancelled"):
			restaurant_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if restaurant_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			restaurant_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_restaurant_preview_requested"))
		if restaurant_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			restaurant_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_restaurant_preview_cleared"))
		if restaurant_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			restaurant_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_restaurant_highlight_requested"))
		_scene.add_child(restaurant_placement_overlay)
		if _map_controller != null:
			_map_controller.set_restaurant_placement_overlay(restaurant_placement_overlay)

	var state = _scene.game_engine.get_state()
	var current_player_id = state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	if _map_controller != null:
		_map_controller.begin_selection("restaurant_placement", {"action_id": action_id})
	restaurant_placement_overlay.visible = true

	if restaurant_placement_overlay.has_method("set_mode"):
		restaurant_placement_overlay.set_mode(action_id)
	if restaurant_placement_overlay.has_method("set_map_data"):
		restaurant_placement_overlay.set_map_data(state.map)

	if action_id == "move_restaurant":
		if restaurant_placement_overlay.has_method("set_available_restaurants"):
			var ids: Array[String] = []
			for rid in Array(current_player.get("restaurants", [])):
				ids.append(str(rid))
			restaurant_placement_overlay.set_available_restaurants(ids)

		if params.has("restaurant_id") and restaurant_placement_overlay.has_method("set_selected_restaurant"):
			restaurant_placement_overlay.set_selected_restaurant(str(params.restaurant_id))

	if restaurant_placement_overlay.has_method("set_available_employees"):
		var usage_tag := ""
		if state.phase == DefsClass.PHASE_WORKING:
			usage_tag = "use:move_restaurant" if action_id == "move_restaurant" else "use:place_restaurant"
		restaurant_placement_overlay.set_available_employees(
			_get_active_employee_types_with_usage_tag(state, current_player_id, usage_tag)
		)
		if params.has("employee_type") and restaurant_placement_overlay.has_method("set_selected_employee"):
			restaurant_placement_overlay.set_selected_employee(str(params.employee_type))

	if _map_controller != null:
		_map_controller.on_restaurant_preview_cleared()

func show_house_placement(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if house_placement_overlay == null:
		house_placement_overlay = HousePlacementScene.instantiate()
		if house_placement_overlay.has_signal("house_placement_confirmed"):
			house_placement_overlay.house_placement_confirmed.connect(_on_house_placement_confirmed)
		if house_placement_overlay.has_signal("garden_confirmed"):
			house_placement_overlay.garden_confirmed.connect(_on_garden_confirmed)
		if house_placement_overlay.has_signal("cancelled"):
			house_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if house_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			house_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_house_preview_requested"))
		if house_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			house_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_house_preview_cleared"))
		if house_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			house_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_house_highlight_requested"))
		_scene.add_child(house_placement_overlay)
		if _map_controller != null:
			_map_controller.set_house_placement_overlay(house_placement_overlay)

	var state = _scene.game_engine.get_state()

	if _map_controller != null:
		_map_controller.begin_selection("house_placement", {"action_id": action_id})

	house_placement_overlay.visible = true

	if house_placement_overlay.has_method("set_mode"):
		house_placement_overlay.set_mode(action_id)
	if house_placement_overlay.has_method("set_map_data"):
		house_placement_overlay.set_map_data(state.map)
	if house_placement_overlay.has_method("set_available_employees"):
		var usage_tag := ""
		if state.phase == DefsClass.PHASE_WORKING:
			usage_tag = "use:add_garden" if action_id == "add_garden" else "use:place_house"
		house_placement_overlay.set_available_employees(
			_get_active_employee_types_with_usage_tag(state, state.get_current_player_id(), usage_tag)
		)
		if params.has("employee_type") and house_placement_overlay.has_method("set_selected_employee"):
			house_placement_overlay.set_selected_employee(str(params.employee_type))
	if _map_controller != null:
		_map_controller.on_house_preview_cleared()

func _on_restaurant_placement_confirmed(position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var command_params := {
		"position": [position.x, position.y],
		"rotation": rotation
	}
	var action_id := "place_restaurant"
	if not restaurant_id.is_empty():
		action_id = "move_restaurant"
		command_params["restaurant_id"] = restaurant_id
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(restaurant_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type

	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, command_params))
	if result.ok:
		if is_instance_valid(restaurant_placement_overlay):
			restaurant_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
			restaurant_placement_overlay.set_validation(false, result.error)

func _on_house_placement_confirmed(position: Vector2i, rotation: int, house_number: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()

	var command_params := {
		"position": [position.x, position.y],
		"rotation": rotation,
		"house_number": int(house_number)
	}
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type
	var result: Result = _execute_command.call(Command.create("place_house", current_player_id, command_params))
	if result.ok:
		if is_instance_valid(house_placement_overlay):
			house_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()

func _on_garden_confirmed(house_id: String, direction: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	if house_id.is_empty() or direction.is_empty():
		return

	var command_params := {
		"house_id": house_id,
		"direction": direction
	}
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type
	var result: Result = _execute_command.call(Command.create("add_garden", current_player_id, command_params))
	if result.ok:
		if is_instance_valid(house_placement_overlay):
			house_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()

func _on_piece_placement_confirmed(position: Vector2i, rotation: int, piece_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	if piece_id.is_empty():
		return

	var action_id := ""
	if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("get_mode"):
		action_id = str(piece_placement_overlay.get_mode()).strip_edges()
	if action_id.is_empty():
		return

	var current_player_id := _scene.game_engine.get_state().get_current_player_id()
	var command_params := {
		"piece_id": piece_id,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	}
	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, command_params))
	if result.ok:
		if is_instance_valid(piece_placement_overlay):
			piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("set_validation"):
			piece_placement_overlay.set_validation(false, result.error)

func _on_overlay_cancelled() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if is_instance_valid(piece_placement_overlay):
		piece_placement_overlay.visible = false
	if _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()

func _get_active_employee_types_with_usage_tag(state: GameState, player_id: int, usage_tag: String) -> Array[String]:
	if state == null or usage_tag.is_empty():
		return []
	if not EmployeeRegistryClass.is_loaded():
		return []
	var player := state.get_player(player_id)
	if player.is_empty():
		return []
	var employees_val = player.get("employees", [])
	if not (employees_val is Array):
		return []
	var seen := {}
	for emp_val in employees_val:
		if not (emp_val is String):
			continue
		var emp_id := str(emp_val).strip_edges()
		if emp_id.is_empty():
			continue
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not def.has_usage_tag(usage_tag):
			continue
		seen[emp_id] = true
	var ids: Array[String] = []
	for key in seen.keys():
		ids.append(str(key))
	ids.sort()
	return ids
