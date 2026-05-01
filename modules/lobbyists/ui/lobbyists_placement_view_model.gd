extends RefCounted

const LobbyistsStaffUsageClass = preload("res://modules/lobbyists/actions/lobbyists_staff_usage.gd")

const ACTION_ROAD := "place_lobbyists_road"
const ACTION_PARK := "place_lobbyists_park"
const PHASE_WORKING := "Working"
const SUB_PHASE_LOBBYISTS := "Lobbyists"
const EMPLOYEE_LOBBYIST := "lobbyist"

static func is_overlay_allowed(state) -> bool:
	if state == null:
		return false
	return str(state.phase) == PHASE_WORKING and str(state.sub_phase) == SUB_PHASE_LOBBYISTS

static func build(state, game_engine, player_id: int) -> Dictionary:
	return {
		"piece_sets": {
			ACTION_ROAD: get_executor_piece_ids(game_engine, ACTION_ROAD),
			ACTION_PARK: get_executor_piece_ids(game_engine, ACTION_PARK),
		},
		"mode_availability": {
			ACTION_ROAD: is_action_allowed_by_phase(state, game_engine, ACTION_ROAD),
			ACTION_PARK: is_action_allowed_by_phase(state, game_engine, ACTION_PARK),
		},
		"employee_items": build_lobbyist_employee_items(state, player_id),
	}

static func is_action_allowed_by_phase(state, game_engine, action_id: String) -> bool:
	if state == null or game_engine == null:
		return false
	var ex = game_engine.get_action_registry().get_executor(action_id)
	if ex == null:
		return false
	if ex.allowed_phases is Array and not Array(ex.allowed_phases).is_empty() and not Array(ex.allowed_phases).has(state.phase):
		return false
	if ex.allowed_sub_phases is Array and not Array(ex.allowed_sub_phases).is_empty() and not Array(ex.allowed_sub_phases).has(state.sub_phase):
		return false
	return true

static func get_executor_piece_ids(game_engine, action_id: String) -> Array[String]:
	var out: Array[String] = []
	if game_engine == null:
		return out
	var ex = game_engine.get_action_registry().get_executor(action_id)
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

static func build_lobbyist_employee_items(state, player_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out

	var providers_read := LobbyistsStaffUsageClass.try_get_lobbyists_for_working(state, player_id)
	if not providers_read.ok:
		return out
	for provider_val in Array(providers_read.value):
		if not (provider_val is Dictionary):
			continue
		var provider: Dictionary = provider_val
		var employee_type := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
		if employee_type.is_empty():
			continue
		out.append({
			"staff_id": int(provider.get("staff_id", -1)),
			"id": employee_type,
			"employee_type": employee_type,
			"employee_def": get_lobbyist_employee_def(employee_type),
			"capacity": int(provider.get("capacity", 0)),
			"used": int(provider.get("used", 0)),
			"remaining": int(provider.get("remaining", 0)),
			"can_place_lobbyists_road": true,
			"can_place_lobbyists_park": true,
		})

	return out

static func get_lobbyist_employee_def(employee_type: String) -> Dictionary:
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
