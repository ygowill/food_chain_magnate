# Game scene：放置覆盖层（餐厅/住宅/花园）
extends RefCounted

const RestaurantPlacementScene = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.tscn")
const HousePlacementScene = preload("res://ui/components/house_placement/house_placement_overlay.tscn")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _hide_all: Callable

var restaurant_placement_overlay = null
var house_placement_overlay = null

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

func sync(state: GameState) -> void:
	_sync_restaurant_placement_overlay(state)
	_sync_house_placement_overlay(state)

func _sync_restaurant_placement_overlay(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return

	var allowed := false
	if state.phase == "Setup":
		allowed = true
	elif state.phase == "Working" and state.sub_phase == "PlaceRestaurants":
		allowed = true

	if not allowed:
		restaurant_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

func _sync_house_placement_overlay(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(house_placement_overlay) or not house_placement_overlay.visible:
		return
	if state.phase != "Working" or state.sub_phase != "PlaceHouses":
		house_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

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
		if state.phase == "Working":
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
		if state.phase == "Working":
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

func _on_overlay_cancelled() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
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
