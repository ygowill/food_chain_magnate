extends RefCounted

const LobbyistsPlacementOverlayClass = preload("res://modules/lobbyists/ui/components/lobbyists_placement/lobbyists_placement_overlay.gd")

const ACTION_ROAD := "place_lobbyists_road"
const ACTION_PARK := "place_lobbyists_park"
const PLACE_COUNT_KEY := "lobbyists_place_counts"
const SYNTHETIC_STAFF_ID_BASE := 100000
const PHASE_WORKING := "Working"
const SUB_PHASE_LOBBYISTS := "Lobbyists"
const EMPLOYEE_LOBBYIST := "lobbyist"

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()

var _overlay: Control = null

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func dispose() -> void:
	hide()
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_scene = null
	_map_controller = null
	_overlay_controller = null
	_execute_command = Callable()
	_hide_all = Callable()

func hide() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_clear_action_panel_context()
	if _map_controller != null and _map_controller.has_method("set_piece_placement_overlay"):
		_map_controller.set_piece_placement_overlay(null)
	if _map_controller != null and _map_controller.has_method("get_mode") and str(_map_controller.get_mode()) == "piece_placement":
		_map_controller.clear_selection()

func get_context_overlay():
	if is_instance_valid(_overlay) and _overlay.visible:
		return _overlay
	return null

func try_handle_action_request(action_id: String, params: Dictionary) -> bool:
	var aid := _normalize_action(action_id)
	if aid.is_empty():
		return false
	if _scene == null or _scene.game_engine == null:
		return true
	var state = _scene.game_engine.get_state()
	if state == null:
		return true
	_show_overlay(state, aid, params)
	return true

func sync(state, force_full_refresh: bool = false) -> void:
	if not is_instance_valid(_overlay) or not _overlay.visible:
		return
	if state == null:
		hide()
		return
	var actor_id := _get_actor_id_for_state(state)
	if actor_id < 0 or not _is_overlay_allowed(state):
		hide()
		return
	_sync_overlay_from_state(state, actor_id)
	if force_full_refresh:
		if _overlay.has_method("clear_selection"):
			_overlay.call("clear_selection")
		_refresh_map_selection(true)

func _show_overlay(state, action_id: String, params: Dictionary) -> void:
	if _scene == null or _map_controller == null:
		return

	var actor_id := _get_actor_id_for_state(state)
	if actor_id < 0:
		return
	if not _is_overlay_allowed(state):
		_show_toast("当前不在 Working/Lobbyists，无法使用说客")
		return

	var already_visible := is_instance_valid(_overlay) and _overlay.visible
	if not already_visible and _hide_all.is_valid():
		_hide_all.call()

	_ensure_overlay()
	if not is_instance_valid(_overlay):
		return

	_overlay.visible = true
	if _map_controller.has_method("set_piece_placement_overlay"):
		_map_controller.set_piece_placement_overlay(_overlay)

	_sync_overlay_from_state(state, actor_id)
	if _overlay.has_method("set_mode"):
		_overlay.call("set_mode", action_id)

	var pre_piece := str(params.get("piece_id", "")).strip_edges()
	if not pre_piece.is_empty() and _overlay.has_method("set_selected_piece"):
		_overlay.call("set_selected_piece", pre_piece)
	if params.has("rotation") and _overlay.has_method("set_selected_rotation"):
		_overlay.call("set_selected_rotation", int(params.get("rotation", 0)))
	if params.has("staff_id") and _overlay.has_method("set_selected_employee_key"):
		_overlay.call("set_selected_employee_key", "staff:%d" % int(params.get("staff_id", -1)))
	elif params.has("employee_type") and _overlay.has_method("set_selected_employee"):
		_overlay.call("set_selected_employee", str(params.get("employee_type", "")))

	_bind_action_panel_context(_overlay)
	_refresh_map_selection(true)

func _ensure_overlay() -> void:
	if is_instance_valid(_overlay):
		return
	_overlay = LobbyistsPlacementOverlayClass.new()
	if not is_instance_valid(_overlay):
		return
	if _overlay.has_signal("placement_confirmed"):
		_overlay.placement_confirmed.connect(_on_placement_confirmed)
	if _overlay.has_signal("cancelled"):
		_overlay.cancelled.connect(_on_overlay_cancelled)
	if _overlay.has_signal("preview_requested") and _map_controller != null:
		_overlay.preview_requested.connect(Callable(_map_controller, "on_piece_preview_requested"))
	if _overlay.has_signal("preview_cleared") and _map_controller != null:
		_overlay.preview_cleared.connect(Callable(_map_controller, "on_piece_preview_cleared"))
	if _overlay.has_signal("highlight_requested") and _map_controller != null:
		_overlay.highlight_requested.connect(Callable(_map_controller, "on_piece_highlight_requested"))
	_scene.add_child(_overlay)
	if _overlay is Control:
		(_overlay as Control).z_index = 920

func _sync_overlay_from_state(state, actor_id: int) -> void:
	if not is_instance_valid(_overlay):
		return

	var piece_sets := {
		ACTION_ROAD: _get_executor_piece_ids(ACTION_ROAD),
		ACTION_PARK: _get_executor_piece_ids(ACTION_PARK),
	}
	if _overlay.has_method("set_available_piece_sets"):
		_overlay.call("set_available_piece_sets", piece_sets)
	if _overlay.has_method("set_mode_availability"):
		_overlay.call("set_mode_availability", {
			ACTION_ROAD: _is_action_allowed_by_phase(state, ACTION_ROAD),
			ACTION_PARK: _is_action_allowed_by_phase(state, ACTION_PARK),
		})
	if _overlay.has_method("set_available_employee_items"):
		_overlay.call("set_available_employee_items", _build_lobbyist_employee_items(state, actor_id))
	_select_first_enabled_lobbyist_if_needed()

func _refresh_map_selection(force_begin: bool = false) -> void:
	if _map_controller == null or not is_instance_valid(_overlay):
		return
	var action_id := ACTION_ROAD
	if _overlay.has_method("get_mode"):
		action_id = str(_overlay.call("get_mode")).strip_edges()
	if action_id.is_empty():
		action_id = ACTION_ROAD

	var should_begin := force_begin
	if _map_controller.has_method("get_mode") and str(_map_controller.get_mode()) != "piece_placement":
		should_begin = true
	if should_begin:
		_map_controller.begin_selection("piece_placement", {"action_id": action_id})

	var rotation := 0
	if _overlay.has_method("get_selected_rotation"):
		rotation = int(_overlay.call("get_selected_rotation"))
	var piece_id := ""
	if _overlay.has_method("get_selected_piece"):
		piece_id = str(_overlay.call("get_selected_piece")).strip_edges()
	if _map_controller.has_method("on_piece_highlight_requested"):
		_map_controller.on_piece_highlight_requested(action_id, rotation, piece_id)

	var position := Vector2i(-1, -1)
	if _overlay.has_method("get_selected_position"):
		var pos_val = _overlay.call("get_selected_position")
		if pos_val is Vector2i:
			position = Vector2i(pos_val)
	if position == Vector2i(-1, -1):
		if _map_controller.has_method("on_piece_preview_cleared"):
			_map_controller.on_piece_preview_cleared()
	elif _map_controller.has_method("on_piece_preview_requested"):
		_map_controller.on_piece_preview_requested(action_id, position, rotation, piece_id)

func _on_placement_confirmed(action_id: String, position: Vector2i, rotation: int, piece_id: String, employee_type: String, staff_id: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var aid := _normalize_action(action_id)
	if aid.is_empty() or piece_id.is_empty() or position == Vector2i(-1, -1):
		return

	var state = _scene.game_engine.get_state()
	if state == null:
		return
	var actor_id := _get_actor_id_for_state(state)
	if actor_id < 0:
		return

	var command_params := {
		"piece_id": piece_id,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	}
	var emp_type := str(employee_type).strip_edges()
	if not emp_type.is_empty():
		command_params["employee_type"] = emp_type
	if int(staff_id) > 0 and int(staff_id) < SYNTHETIC_STAFF_ID_BASE:
		command_params["staff_id"] = int(staff_id)

	var command = _create_command(aid, actor_id, command_params)
	if command == null:
		if is_instance_valid(_overlay) and _overlay.has_method("set_validation"):
			_overlay.call("set_validation", false, "无法创建说客动作命令")
		return

	var result = _execute_command.call(command)
	if not result.ok:
		if is_instance_valid(_overlay) and _overlay.has_method("set_validation"):
			_overlay.call("set_validation", false, result.error)
		return

	_after_command_success(actor_id)

func _after_command_success(actor_id: int) -> void:
	var state_after = _scene.game_engine.get_state() if (_scene != null and _scene.game_engine != null) else null
	if state_after == null:
		_close_overlay_and_refresh()
		return

	var same_lobbyists_turn := (
		str(state_after.phase) == PHASE_WORKING
		and str(state_after.sub_phase) == SUB_PHASE_LOBBYISTS
		and int(state_after.get_current_player_id()) == int(actor_id)
	)
	if same_lobbyists_turn and is_instance_valid(_overlay):
		_sync_overlay_from_state(state_after, actor_id)
		if _overlay.has_method("clear_selection"):
			_overlay.call("clear_selection")
		_select_first_enabled_lobbyist_if_needed()
		_refresh_map_selection(true)
		_request_scene_ui_refresh_deferred()
		return

	_close_overlay_and_refresh()

func _close_overlay_and_refresh() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_clear_action_panel_context()
	if _map_controller != null:
		if _map_controller.has_method("set_piece_placement_overlay"):
			_map_controller.set_piece_placement_overlay(null)
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()
	_request_scene_ui_refresh_deferred()

func _on_overlay_cancelled() -> void:
	_close_overlay_and_refresh()

func _bind_action_panel_context(overlay: Node) -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	var action_panel = _scene.get("action_panel")
	if action_panel != null and is_instance_valid(action_panel) and action_panel.has_method("bind_context_overlay"):
		action_panel.call("bind_context_overlay", overlay)

func _clear_action_panel_context() -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	var action_panel = _scene.get("action_panel")
	if action_panel != null and is_instance_valid(action_panel) and action_panel.has_method("clear_context_overlay"):
		action_panel.call("clear_context_overlay")

func _request_scene_ui_refresh_deferred() -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	if _scene.has_method("_update_ui"):
		_scene.call_deferred("_update_ui")

func _show_toast(message: String) -> void:
	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.show_toast(message)

func _normalize_action(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid == ACTION_ROAD or aid == ACTION_PARK:
		return aid
	return ""

func _is_overlay_allowed(state) -> bool:
	if state == null:
		return false
	return str(state.phase) == PHASE_WORKING and str(state.sub_phase) == SUB_PHASE_LOBBYISTS

func _is_action_allowed_by_phase(state, action_id: String) -> bool:
	if state == null or _scene == null or _scene.game_engine == null:
		return false
	var ex = _scene.game_engine.get_action_registry().get_executor(action_id)
	if ex == null:
		return false
	if ex.allowed_phases is Array and not Array(ex.allowed_phases).is_empty() and not Array(ex.allowed_phases).has(state.phase):
		return false
	if ex.allowed_sub_phases is Array and not Array(ex.allowed_sub_phases).is_empty() and not Array(ex.allowed_sub_phases).has(state.sub_phase):
		return false
	return true

func _get_actor_id_for_state(state) -> int:
	if state == null:
		return -1
	var current_player_id := int(state.get_current_player_id())
	var net_context = _get_net_context()
	if net_context != null and net_context.mode == net_context.Mode.ONLINE_CLIENT:
		var local_player_id := int(net_context.local_player_id)
		if local_player_id < 0 or current_player_id != local_player_id:
			return -1
		return local_player_id
	return current_player_id

func _get_net_context():
	if _scene == null or not is_instance_valid(_scene) or not (_scene is Node):
		return null
	return (_scene as Node).get_node_or_null("/root/NetContext")

func _get_executor_piece_ids(action_id: String) -> Array[String]:
	var out: Array[String] = []
	if _scene == null or _scene.game_engine == null:
		return out
	var ex = _scene.game_engine.get_action_registry().get_executor(action_id)
	if ex == null:
		return out
	var ids_val = ex.ui_piece_ids
	if ids_val is Array:
		var seen := {}
		for v in Array(ids_val):
			var s := str(v).strip_edges()
			if s.is_empty() or seen.has(s):
				continue
			seen[s] = true
			out.append(s)
	return out

func _create_command(action_id: String, actor_id: int, params: Dictionary):
	var command_script = load("res://core/types/command.gd")
	if command_script == null:
		return null
	var command = command_script.new()
	command.action_id = action_id
	command.actor = int(actor_id)
	command.params = params.duplicate(true)
	if _scene != null and _scene.game_engine != null:
		var state = _scene.game_engine.get_state()
		if state != null:
			command.phase = str(state.phase)
			command.sub_phase = str(state.sub_phase)
	return command

func _build_lobbyist_employee_items(state, player_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out

	var player = state.get_player(player_id)
	if player.is_empty():
		return out
	var employees_val = player.get("employees", [])
	if not (employees_val is Array):
		return out
	var registry_val = player.get("staff_registry", {})
	var registry: Dictionary = registry_val if registry_val is Dictionary else {}
	var active_staff_ids_val = player.get("employees_staff_ids", [])
	var active_staff_ids: Array = active_staff_ids_val if active_staff_ids_val is Array else []
	var used_staff_ids := {}
	var used_remaining := _get_player_round_count(state, player_id)

	for i in range(Array(employees_val).size()):
		var employee_type := str(Array(employees_val)[i]).strip_edges()
		if employee_type.is_empty():
			continue
		if not _is_lobbyist_employee(employee_type):
			continue

		var capacity := 1
		var used_for_staff := mini(used_remaining, capacity)
		used_remaining = maxi(0, used_remaining - used_for_staff)
		var staff_id := _resolve_active_staff_id_for_employee(employee_type, i, active_staff_ids, registry, used_staff_ids)
		used_staff_ids[staff_id] = true
		out.append({
			"staff_id": staff_id,
			"id": employee_type,
			"employee_type": employee_type,
			"employee_def": _get_lobbyist_employee_def(employee_type),
			"capacity": capacity,
			"used": used_for_staff,
			"remaining": maxi(0, capacity - used_for_staff),
			"can_place_lobbyists_road": true,
			"can_place_lobbyists_park": true,
		})

	return out

func _is_lobbyist_employee(employee_type: String) -> bool:
	return str(employee_type).strip_edges() == EMPLOYEE_LOBBYIST

func _get_lobbyist_employee_def(employee_type: String) -> Dictionary:
	var emp_id := str(employee_type).strip_edges()
	if emp_id != EMPLOYEE_LOBBYIST:
		return {"id": emp_id, "name": emp_id}
	return {
		"id": EMPLOYEE_LOBBYIST,
		"name": "提案人",
		"description": "在工作时间放置一块道路（建设中）或一块公园",
		"salary": true,
		"unique": false,
		"role": "special",
		"manager_slots": 0,
		"range": {
			"type": "road",
			"value": 2,
		},
		"train_to": [],
		"train_capacity": 0,
		"tags": ["entry_level"],
	}

func _resolve_active_staff_id_for_employee(employee_type: String, employee_index: int, active_staff_ids: Array, registry: Dictionary, used_staff_ids: Dictionary) -> int:
	if employee_index >= 0 and employee_index < active_staff_ids.size():
		var direct_id := int(active_staff_ids[employee_index])
		if direct_id > 0 and not used_staff_ids.has(direct_id):
			var direct_record_val = registry.get(direct_id, null)
			if direct_record_val is Dictionary:
				var direct_record: Dictionary = direct_record_val
				if str(direct_record.get("employee_type", "")).strip_edges() == employee_type:
					return direct_id

	for sid_val in active_staff_ids:
		var staff_id := int(sid_val)
		if staff_id <= 0 or used_staff_ids.has(staff_id):
			continue
		var record_val = registry.get(staff_id, null)
		if not (record_val is Dictionary):
			continue
		var record: Dictionary = record_val
		if str(record.get("employee_type", "")).strip_edges() == employee_type:
			return staff_id

	return SYNTHETIC_STAFF_ID_BASE + employee_index + 1

func _get_player_round_count(state, player_id: int) -> int:
	if state == null or not (state.round_state is Dictionary):
		return 0
	var round_state: Dictionary = state.round_state
	var counts_val = round_state.get(PLACE_COUNT_KEY, {})
	if not (counts_val is Dictionary):
		return 0
	var counts: Dictionary = counts_val
	var value = counts.get(player_id, null)
	if value == null and counts.has(str(player_id)):
		value = counts.get(str(player_id), null)
	return maxi(0, int(value)) if value != null else 0

func _select_first_enabled_lobbyist_if_needed() -> void:
	if not is_instance_valid(_overlay):
		return
	if not _overlay.has_method("get_selected_employee_key") or not _overlay.has_method("set_selected_employee_key"):
		return

	var current_key := str(_overlay.call("get_selected_employee_key")).strip_edges()
	if not current_key.is_empty() and _employee_item_key_enabled(current_key):
		return

	var fallback_key := _find_first_enabled_employee_key()
	if fallback_key.is_empty():
		return
	_overlay.call("set_selected_employee_key", fallback_key)

func _employee_item_key_enabled(employee_key: String) -> bool:
	if not is_instance_valid(_overlay) or not _overlay.has_method("get_available_employee_items"):
		return false
	var key := str(employee_key).strip_edges()
	if key.is_empty():
		return false
	var items_val = _overlay.call("get_available_employee_items")
	if not (items_val is Array):
		return false
	for item_val in Array(items_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("key", "")).strip_edges() != key:
			continue
		return bool(item.get("enabled", true))
	return false

func _find_first_enabled_employee_key() -> String:
	if not is_instance_valid(_overlay) or not _overlay.has_method("get_available_employee_items"):
		return ""
	var items_val = _overlay.call("get_available_employee_items")
	if not (items_val is Array):
		return ""
	for item_val in Array(items_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if not bool(item.get("enabled", true)):
			continue
		var key := str(item.get("key", "")).strip_edges()
		if not key.is_empty():
			return key
	return ""
