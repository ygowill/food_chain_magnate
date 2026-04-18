class_name StaffState
extends RefCounted

const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const STAFF_REGISTRY_KEY := "staff_registry"
const ACTIVE_STAFF_IDS_KEY := "employees_staff_ids"
const RESERVE_STAFF_IDS_KEY := "reserve_staff_ids"
const BUSY_STAFF_IDS_KEY := "busy_staff_ids"

const STAFF_USAGE_KEY := "staff_usage"
const STAFF_TRAIN_EVENT_COUNTS_KEY := "staff_train_event_counts"

const ZONE_ACTIVE := "employees"
const ZONE_RESERVE := "reserve_employees"
const ZONE_BUSY := "busy_marketers"

static func ensure_state_staff_support(state: GameState) -> Result:
	if state == null:
		return Result.failure("StaffState.ensure_state_staff_support: state 为空")
	if not (state.players is Array):
		return Result.failure("StaffState.ensure_state_staff_support: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("StaffState.ensure_state_staff_support: state.round_state 类型错误（期望 Dictionary）")

	var used_global_ids := {}
	var next_staff_id := maxi(1, int(state.next_staff_id))
	var max_staff_id := 0

	for player_id in range(state.players.size()):
		var sync_read := _ensure_player_staff_support(state, player_id, used_global_ids, next_staff_id)
		if not sync_read.ok:
			return sync_read
		var sync_info: Dictionary = sync_read.value
		next_staff_id = int(sync_info.get("next_staff_id", next_staff_id))
		max_staff_id = maxi(max_staff_id, int(sync_info.get("max_staff_id", 0)))

	var round_state_read := _ensure_round_state_staff_fields(state.round_state)
	if not round_state_read.ok:
		return round_state_read
	var round_state_info: Dictionary = round_state_read.value
	max_staff_id = maxi(max_staff_id, int(round_state_info.get("max_staff_id", 0)))

	state.next_staff_id = maxi(next_staff_id, max_staff_id + 1)
	if state.next_staff_id <= 0:
		state.next_staff_id = 1

	return Result.success({
		"next_staff_id": state.next_staff_id,
		"max_staff_id": max_staff_id,
	})

static func ensure_player_staff_support(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("StaffState.ensure_player_staff_support: state 为空")
	if not (state.players is Array):
		return Result.failure("StaffState.ensure_player_staff_support: state.players 类型错误（期望 Array）")
	var used_global_ids := {}
	var next_staff_id := maxi(1, int(state.next_staff_id))
	for pid in range(state.players.size()):
		var sync_read := _ensure_player_staff_support(state, pid, used_global_ids, next_staff_id)
		if not sync_read.ok:
			return sync_read
		var sync_info: Dictionary = sync_read.value
		next_staff_id = int(sync_info.get("next_staff_id", next_staff_id))
		if pid == player_id:
			state.next_staff_id = next_staff_id
			return Result.success(sync_info)
	return Result.failure("StaffState.ensure_player_staff_support: player_id 越界: %d" % player_id)

static func allocate_next_staff_id(state: GameState) -> int:
	var next_staff_id := maxi(1, int(state.next_staff_id))
	state.next_staff_id = next_staff_id + 1
	return next_staff_id

static func add_staff_for_employee(state: GameState, player_id: int, employee_type: String, zone_key: String) -> Result:
	if state == null:
		return Result.failure("StaffState.add_staff_for_employee: state 为空")
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.add_staff_for_employee")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return Result.failure("StaffState.add_staff_for_employee: employee_type 不能为空")

	var staff_zone_key := _staff_zone_key(zone_key)
	if staff_zone_key.is_empty():
		return Result.failure("StaffState.add_staff_for_employee: 未知 zone_key: %s" % zone_key)

	var zone_ids_read := _require_staff_id_array(player.get(staff_zone_key, []), "player.%s" % staff_zone_key)
	if not zone_ids_read.ok:
		return zone_ids_read
	var zone_ids: Array = zone_ids_read.value

	var legacy_read := _require_legacy_zone_array(player, zone_key, "StaffState.add_staff_for_employee")
	if not legacy_read.ok:
		return legacy_read
	var legacy_arr: Array = legacy_read.value

	var registry_read := _require_staff_registry(player, "StaffState.add_staff_for_employee")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var staff_id := allocate_next_staff_id(state)
	registry[staff_id] = {
		"staff_id": staff_id,
		"employee_type": emp_id,
		"created_round": int(state.round_number),
	}
	zone_ids.append(staff_id)
	legacy_arr.append(emp_id)

	player[STAFF_REGISTRY_KEY] = registry
	player[staff_zone_key] = zone_ids
	player[zone_key] = legacy_arr
	state.players[player_id] = player

	return Result.success({
		"staff_id": staff_id,
		"employee_type": emp_id,
		"zone_key": zone_key,
	})

static func find_staff_ids_by_employee_type(
	state: GameState,
	player_id: int,
	employee_type: String,
	zone_keys: Array[String] = []
) -> Result:
	if state == null:
		return Result.failure("StaffState.find_staff_ids_by_employee_type: state 为空")
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.find_staff_ids_by_employee_type")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var registry_read := _require_staff_registry(player, "StaffState.find_staff_ids_by_employee_type")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value

	var target_type := str(employee_type).strip_edges()
	if target_type.is_empty():
		return Result.failure("StaffState.find_staff_ids_by_employee_type: employee_type 不能为空")

	var zones := zone_keys
	if zones.is_empty():
		zones = [ZONE_ACTIVE, ZONE_RESERVE, ZONE_BUSY]

	var out: Array[int] = []
	for zone_key in zones:
		var staff_zone_key := _staff_zone_key(str(zone_key))
		if staff_zone_key.is_empty():
			continue
		var ids_read := _require_staff_id_array(player.get(staff_zone_key, []), "player.%s" % staff_zone_key)
		if not ids_read.ok:
			return ids_read
		var ids: Array = ids_read.value
		for staff_id_val in ids:
			var staff_id := int(staff_id_val)
			if not registry.has(staff_id):
				continue
			var record_val = registry.get(staff_id, null)
			if not (record_val is Dictionary):
				continue
			var record: Dictionary = record_val
			if str(record.get("employee_type", "")).strip_edges() != target_type:
				continue
			out.append(staff_id)
		out.sort()
	return Result.success(out)

static func get_staff_record(state: GameState, player_id: int, staff_id: int) -> Result:
	if staff_id <= 0:
		return Result.failure("StaffState.get_staff_record: staff_id 必须 > 0，实际: %d" % staff_id)
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.get_staff_record")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var registry_read := _require_staff_registry(player, "StaffState.get_staff_record")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value
	if not registry.has(staff_id):
		return Result.failure("StaffState.get_staff_record: 玩家 %d 不存在 staff_id=%d" % [player_id, staff_id])
	var record_val = registry.get(staff_id, null)
	if not (record_val is Dictionary):
		return Result.failure("StaffState.get_staff_record: player.staff_registry[%d] 类型错误（期望 Dictionary）" % staff_id)
	return Result.success(Dictionary(record_val).duplicate(true))

static func get_staff_employee_type(state: GameState, player_id: int, staff_id: int) -> Result:
	var record_read := get_staff_record(state, player_id, staff_id)
	if not record_read.ok:
		return record_read
	var record: Dictionary = record_read.value
	var employee_type := str(record.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("StaffState.get_staff_employee_type: staff_id=%d 缺少 employee_type" % staff_id)
	return Result.success(employee_type)

static func get_staff_zone(state: GameState, player_id: int, staff_id: int) -> Result:
	if state == null:
		return Result.failure("StaffState.get_staff_zone: state 为空")
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.get_staff_zone")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	for zone_key in [ZONE_ACTIVE, ZONE_RESERVE, ZONE_BUSY]:
		var staff_zone_key := _staff_zone_key(zone_key)
		var ids_read := _require_staff_id_array(player.get(staff_zone_key, []), "player.%s" % staff_zone_key)
		if not ids_read.ok:
			return ids_read
		var ids: Array = ids_read.value
		if ids.find(staff_id) >= 0:
			return Result.success(zone_key)
	return Result.success("")

static func remove_staff_from_player(state: GameState, player_id: int, staff_id: int, zone_key: String = "") -> Result:
	if state == null:
		return Result.failure("StaffState.remove_staff_from_player: state 为空")
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.remove_staff_from_player")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var registry_read := _require_staff_registry(player, "StaffState.remove_staff_from_player")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value
	if not registry.has(staff_id):
		return Result.failure("StaffState.remove_staff_from_player: staff_id 不存在: %d" % staff_id)

	var record_val = registry.get(staff_id, null)
	if not (record_val is Dictionary):
		return Result.failure("StaffState.remove_staff_from_player: player.staff_registry[%d] 类型错误（期望 Dictionary）" % staff_id)
	var record: Dictionary = record_val
	var employee_type := str(record.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("StaffState.remove_staff_from_player: staff_id=%d 缺少 employee_type" % staff_id)

	var actual_zone := str(zone_key).strip_edges()
	if actual_zone.is_empty():
		var zone_read := get_staff_zone(state, player_id, staff_id)
		if not zone_read.ok:
			return zone_read
		actual_zone = str(zone_read.value).strip_edges()
	if actual_zone.is_empty():
		return Result.failure("StaffState.remove_staff_from_player: 无法定位 staff_id=%d 所在区域" % staff_id)

	var staff_zone_key := _staff_zone_key(actual_zone)
	if staff_zone_key.is_empty():
		return Result.failure("StaffState.remove_staff_from_player: 未知 zone_key: %s" % actual_zone)

	var zone_ids_read := _require_staff_id_array(player.get(staff_zone_key, []), "player.%s" % staff_zone_key)
	if not zone_ids_read.ok:
		return zone_ids_read
	var zone_ids: Array = zone_ids_read.value
	var zone_index := zone_ids.find(staff_id)
	if zone_index < 0:
		return Result.failure("StaffState.remove_staff_from_player: %s 中不存在 staff_id=%d" % [staff_zone_key, staff_id])

	var legacy_read := _require_legacy_zone_array(player, actual_zone, "StaffState.remove_staff_from_player")
	if not legacy_read.ok:
		return legacy_read
	var legacy_arr: Array = legacy_read.value

	zone_ids.remove_at(zone_index)
	if zone_index >= 0 and zone_index < legacy_arr.size():
		legacy_arr.remove_at(zone_index)
	else:
		var fallback_index := legacy_arr.find(employee_type)
		if fallback_index >= 0:
			legacy_arr.remove_at(fallback_index)
		else:
			return Result.failure("StaffState.remove_staff_from_player: %s 中找不到对应员工类型: %s" % [actual_zone, employee_type])

	registry.erase(staff_id)
	player[STAFF_REGISTRY_KEY] = registry
	player[staff_zone_key] = zone_ids
	player[actual_zone] = legacy_arr
	state.players[player_id] = player

	return Result.success({
		"staff_id": staff_id,
		"employee_type": employee_type,
		"zone_key": actual_zone,
	})

static func change_staff_employee_type(state: GameState, player_id: int, staff_id: int, new_employee_type: String) -> Result:
	if state == null:
		return Result.failure("StaffState.change_staff_employee_type: state 为空")
	var sync_read := ensure_state_staff_support(state)
	if not sync_read.ok:
		return sync_read
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState.change_staff_employee_type")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var registry_read := _require_staff_registry(player, "StaffState.change_staff_employee_type")
	if not registry_read.ok:
		return registry_read
	var registry: Dictionary = registry_read.value
	if not registry.has(staff_id):
		return Result.failure("StaffState.change_staff_employee_type: staff_id 不存在: %d" % staff_id)

	var target_type := str(new_employee_type).strip_edges()
	if target_type.is_empty():
		return Result.failure("StaffState.change_staff_employee_type: new_employee_type 不能为空")

	var record_val = registry.get(staff_id, null)
	if not (record_val is Dictionary):
		return Result.failure("StaffState.change_staff_employee_type: player.staff_registry[%d] 类型错误（期望 Dictionary）" % staff_id)
	var record: Dictionary = record_val
	var old_type := str(record.get("employee_type", "")).strip_edges()
	record["staff_id"] = staff_id
	record["employee_type"] = target_type
	if not record.has("created_round") or not (record.get("created_round", null) is int):
		record["created_round"] = int(state.round_number)
	registry[staff_id] = record

	var zone_read := get_staff_zone(state, player_id, staff_id)
	if not zone_read.ok:
		return zone_read
	var actual_zone := str(zone_read.value).strip_edges()
	if not actual_zone.is_empty():
		var staff_zone_key := _staff_zone_key(actual_zone)
		var ids_read := _require_staff_id_array(player.get(staff_zone_key, []), "player.%s" % staff_zone_key)
		if not ids_read.ok:
			return ids_read
		var ids: Array = ids_read.value
		var legacy_read := _require_legacy_zone_array(player, actual_zone, "StaffState.change_staff_employee_type")
		if not legacy_read.ok:
			return legacy_read
		var legacy_arr: Array = legacy_read.value
		var idx := ids.find(staff_id)
		if idx >= 0 and idx < legacy_arr.size():
			legacy_arr[idx] = target_type
			player[actual_zone] = legacy_arr
	else:
		for zone_key2 in [ZONE_ACTIVE, ZONE_RESERVE, ZONE_BUSY]:
			var legacy_read2 := _require_legacy_zone_array(player, zone_key2, "StaffState.change_staff_employee_type")
			if not legacy_read2.ok:
				return legacy_read2
			var legacy_arr2: Array = legacy_read2.value
			var fallback_index := legacy_arr2.find(old_type)
			if fallback_index >= 0:
				legacy_arr2[fallback_index] = target_type
				player[zone_key2] = legacy_arr2
				break

	player[STAFF_REGISTRY_KEY] = registry
	state.players[player_id] = player
	return Result.success({
		"staff_id": staff_id,
		"old_employee_type": old_type,
		"new_employee_type": target_type,
	})

static func _ensure_player_staff_support(
	state: GameState,
	player_id: int,
	used_global_ids: Dictionary,
	next_staff_id: int
) -> Result:
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "StaffState")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value

	var active_read := _require_legacy_zone_array(player, ZONE_ACTIVE, "StaffState")
	if not active_read.ok:
		return active_read
	var reserve_read := _require_legacy_zone_array(player, ZONE_RESERVE, "StaffState")
	if not reserve_read.ok:
		return reserve_read
	var busy_read := _require_legacy_zone_array(player, ZONE_BUSY, "StaffState")
	if not busy_read.ok:
		return busy_read

	var registry_info_read := _normalize_staff_registry(player.get(STAFF_REGISTRY_KEY, {}), "players[%d].%s" % [player_id, STAFF_REGISTRY_KEY])
	if not registry_info_read.ok:
		return registry_info_read
	var registry_info: Dictionary = registry_info_read.value
	var registry: Dictionary = registry_info.get("registry", {})
	var max_staff_id := int(registry_info.get("max_staff_id", 0))

	var active_ids_read := _require_staff_id_array(player.get(ACTIVE_STAFF_IDS_KEY, []), "players[%d].%s" % [player_id, ACTIVE_STAFF_IDS_KEY])
	if not active_ids_read.ok:
		return active_ids_read
	var reserve_ids_read := _require_staff_id_array(player.get(RESERVE_STAFF_IDS_KEY, []), "players[%d].%s" % [player_id, RESERVE_STAFF_IDS_KEY])
	if not reserve_ids_read.ok:
		return reserve_ids_read
	var busy_ids_read := _require_staff_id_array(player.get(BUSY_STAFF_IDS_KEY, []), "players[%d].%s" % [player_id, BUSY_STAFF_IDS_KEY])
	if not busy_ids_read.ok:
		return busy_ids_read

	var candidate_ids_by_type := {}
	var seen_candidates := {}
	for ids in [active_ids_read.value, reserve_ids_read.value, busy_ids_read.value]:
		for staff_id_val in ids:
			var staff_id := int(staff_id_val)
			if seen_candidates.has(staff_id) or used_global_ids.has(staff_id):
				continue
			if not registry.has(staff_id):
				continue
			var record: Dictionary = registry[staff_id]
			_append_candidate(candidate_ids_by_type, str(record.get("employee_type", "")), staff_id)
			seen_candidates[staff_id] = true

	var remaining_ids: Array[int] = []
	for staff_id_key in registry.keys():
		var staff_id := int(staff_id_key)
		if seen_candidates.has(staff_id) or used_global_ids.has(staff_id):
			continue
		remaining_ids.append(staff_id)
	remaining_ids.sort()
	for staff_id in remaining_ids:
		var record: Dictionary = registry[staff_id]
		_append_candidate(candidate_ids_by_type, str(record.get("employee_type", "")), staff_id)

	var assigned_ids := {}
	var new_active_ids: Array[int] = []
	var new_reserve_ids: Array[int] = []
	var new_busy_ids: Array[int] = []
	var zone_targets := {
		ZONE_ACTIVE: {
			"legacy": active_read.value,
			"ids": new_active_ids,
		},
		ZONE_RESERVE: {
			"legacy": reserve_read.value,
			"ids": new_reserve_ids,
		},
		ZONE_BUSY: {
			"legacy": busy_read.value,
			"ids": new_busy_ids,
		},
	}

	var next_id_cursor := maxi(1, next_staff_id)
	for zone_key in [ZONE_ACTIVE, ZONE_RESERVE, ZONE_BUSY]:
		var zone_info: Dictionary = zone_targets[zone_key]
		var legacy_arr: Array = zone_info.get("legacy", [])
		var ids_out: Array = zone_info.get("ids", [])
		for emp_val in legacy_arr:
			var emp_id := str(emp_val).strip_edges()
			if emp_id.is_empty():
				return Result.failure("players[%d].%s 不应包含空字符串" % [player_id, zone_key])
			var reused_staff_id := _take_candidate_id(candidate_ids_by_type, emp_id, assigned_ids, used_global_ids)
			if reused_staff_id <= 0:
				reused_staff_id = next_id_cursor
				while reused_staff_id <= 0 or used_global_ids.has(reused_staff_id) or assigned_ids.has(reused_staff_id):
					reused_staff_id += 1
				next_id_cursor = reused_staff_id + 1
				registry[reused_staff_id] = {
					"staff_id": reused_staff_id,
					"employee_type": emp_id,
					"created_round": int(state.round_number),
				}
			else:
				var record: Dictionary = registry.get(reused_staff_id, {}).duplicate(true)
				record["staff_id"] = reused_staff_id
				record["employee_type"] = emp_id
				if not record.has("created_round") or not (record.get("created_round", null) is int):
					record["created_round"] = int(state.round_number)
				registry[reused_staff_id] = record

			max_staff_id = maxi(max_staff_id, reused_staff_id)
			assigned_ids[reused_staff_id] = true
			ids_out.append(reused_staff_id)

	var pruned_registry := {}
	for ids in [new_active_ids, new_reserve_ids, new_busy_ids]:
		for staff_id in ids:
			if not registry.has(staff_id):
				continue
			pruned_registry[staff_id] = registry[staff_id]
			used_global_ids[staff_id] = true

	player[STAFF_REGISTRY_KEY] = pruned_registry
	player[ACTIVE_STAFF_IDS_KEY] = new_active_ids
	player[RESERVE_STAFF_IDS_KEY] = new_reserve_ids
	player[BUSY_STAFF_IDS_KEY] = new_busy_ids
	state.players[player_id] = player

	return Result.success({
		"player_id": player_id,
		"max_staff_id": max_staff_id,
		"next_staff_id": maxi(next_id_cursor, max_staff_id + 1),
	})

static func _ensure_round_state_staff_fields(round_state: Dictionary) -> Result:
	if round_state == null:
		return Result.failure("StaffState: round_state 为空")

	var max_staff_id := 0

	var usage_val = round_state.get(STAFF_USAGE_KEY, null)
	if usage_val == null:
		round_state[STAFF_USAGE_KEY] = {}
	else:
		if not (usage_val is Dictionary):
			return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % STAFF_USAGE_KEY)
		var usage_norm := {}
		var usage_all: Dictionary = usage_val
		for staff_id_key in usage_all.keys():
			var staff_id_read := _parse_staff_id_key(staff_id_key, "round_state.%s" % STAFF_USAGE_KEY)
			if not staff_id_read.ok:
				return staff_id_read
			var staff_id: int = int(staff_id_read.value)
			max_staff_id = maxi(max_staff_id, staff_id)
			var per_val = usage_all.get(staff_id_key, null)
			if not (per_val is Dictionary):
				return Result.failure("round_state.%s[%s] 类型错误（期望 Dictionary）" % [STAFF_USAGE_KEY, str(staff_id_key)])
			var per: Dictionary = per_val
			var per_norm := {}
			for track_key in per.keys():
				if not (track_key is String):
					return Result.failure("round_state.%s[%s] key 类型错误（期望 String）" % [STAFF_USAGE_KEY, str(staff_id_key)])
				var track_id := str(track_key).strip_edges()
				if track_id.is_empty():
					return Result.failure("round_state.%s[%s] 不应包含空字符串 key" % [STAFF_USAGE_KEY, str(staff_id_key)])
				var used_read := _parse_non_negative_int(per.get(track_key, null), "round_state.%s[%s].%s" % [STAFF_USAGE_KEY, str(staff_id_key), track_id])
				if not used_read.ok:
					return used_read
				per_norm[track_id] = int(used_read.value)
			usage_norm[staff_id] = per_norm
		round_state[STAFF_USAGE_KEY] = usage_norm

	var train_counts_val = round_state.get(STAFF_TRAIN_EVENT_COUNTS_KEY, null)
	if train_counts_val == null:
		round_state[STAFF_TRAIN_EVENT_COUNTS_KEY] = {}
	else:
		if not (train_counts_val is Dictionary):
			return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % STAFF_TRAIN_EVENT_COUNTS_KEY)
		var counts_norm := {}
		var counts_all: Dictionary = train_counts_val
		for staff_id_key in counts_all.keys():
			var staff_id_read := _parse_staff_id_key(staff_id_key, "round_state.%s" % STAFF_TRAIN_EVENT_COUNTS_KEY)
			if not staff_id_read.ok:
				return staff_id_read
			var staff_id: int = int(staff_id_read.value)
			max_staff_id = maxi(max_staff_id, staff_id)
			var count_read := _parse_non_negative_int(counts_all.get(staff_id_key, null), "round_state.%s[%s]" % [STAFF_TRAIN_EVENT_COUNTS_KEY, str(staff_id_key)])
			if not count_read.ok:
				return count_read
			counts_norm[staff_id] = int(count_read.value)
		round_state[STAFF_TRAIN_EVENT_COUNTS_KEY] = counts_norm

	return Result.success({
		"max_staff_id": max_staff_id,
	})

static func _require_legacy_zone_array(player: Dictionary, zone_key: String, prefix_label: String) -> Result:
	match zone_key:
		ZONE_ACTIVE:
			return PlayerStateAccessClass.require_employees(player, "player", prefix_label)
		ZONE_RESERVE:
			return PlayerStateAccessClass.require_reserve_employees(player, "player", prefix_label)
		ZONE_BUSY:
			return PlayerStateAccessClass.require_busy_marketers(player, "player", prefix_label)
		_:
			return Result.failure("%s: 未知 zone_key: %s" % [prefix_label, zone_key])

static func _staff_zone_key(zone_key: String) -> String:
	match str(zone_key).strip_edges():
		ZONE_ACTIVE:
			return ACTIVE_STAFF_IDS_KEY
		ZONE_RESERVE:
			return RESERVE_STAFF_IDS_KEY
		ZONE_BUSY:
			return BUSY_STAFF_IDS_KEY
		_:
			return ""

static func _normalize_staff_registry(value, path: String) -> Result:
	if value == null:
		return Result.success({
			"registry": {},
			"max_staff_id": 0,
		})
	if not (value is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var registry_in: Dictionary = value
	var registry_out := {}
	var max_staff_id := 0
	for staff_id_key in registry_in.keys():
		var staff_id_read := _parse_staff_id_key(staff_id_key, path)
		if not staff_id_read.ok:
			return staff_id_read
		var staff_id: int = int(staff_id_read.value)
		max_staff_id = maxi(max_staff_id, staff_id)
		var record_val = registry_in.get(staff_id_key, null)
		if not (record_val is Dictionary):
			return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [path, str(staff_id_key)])
		var record_in: Dictionary = record_val
		var employee_type := str(record_in.get("employee_type", "")).strip_edges()
		if employee_type.is_empty():
			return Result.failure("%s[%s].employee_type 不能为空" % [path, str(staff_id_key)])
		var created_round := 0
		if record_in.has("created_round"):
			var created_round_read := _parse_int(record_in.get("created_round", null), "%s[%s].created_round" % [path, str(staff_id_key)])
			if not created_round_read.ok:
				return created_round_read
			created_round = int(created_round_read.value)
		registry_out[staff_id] = {
			"staff_id": staff_id,
			"employee_type": employee_type,
			"created_round": created_round,
		}
	return Result.success({
		"registry": registry_out,
		"max_staff_id": max_staff_id,
	})

static func _require_staff_registry(player: Dictionary, prefix_label: String) -> Result:
	var registry_info_read := _normalize_staff_registry(player.get(STAFF_REGISTRY_KEY, {}), "player.%s" % STAFF_REGISTRY_KEY)
	if not registry_info_read.ok:
		return registry_info_read
	var registry_info: Dictionary = registry_info_read.value
	return Result.success(registry_info.get("registry", {}))

static func _require_staff_id_array(value, path: String) -> Result:
	if value == null:
		return Result.success([])
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[int]）" % path)
	var arr: Array = value
	var out: Array[int] = []
	for i in range(arr.size()):
		var staff_id_read := _parse_staff_id(arr[i], "%s[%d]" % [path, i])
		if not staff_id_read.ok:
			return staff_id_read
		out.append(int(staff_id_read.value))
	return Result.success(out)

static func _parse_staff_id_key(value, path: String) -> Result:
	if value is int:
		if int(value) <= 0:
			return Result.failure("%s key 必须 > 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is String:
		var s := str(value).strip_edges()
		if not s.is_valid_int():
			return Result.failure("%s key 必须为正整数或数字字符串，实际: %s" % [path, str(value)])
		var parsed := s.to_int()
		if parsed <= 0:
			return Result.failure("%s key 必须 > 0，实际: %d" % [path, parsed])
		return Result.success(parsed)
	return Result.failure("%s key 类型错误（期望 int/String）" % path)

static func _parse_staff_id(value, path: String) -> Result:
	if value is int:
		if int(value) <= 0:
			return Result.failure("%s 必须 > 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		if int(f) <= 0:
			return Result.failure("%s 必须 > 0，实际: %d" % [path, int(f)])
		return Result.success(int(f))
	if value is String:
		var s := str(value).strip_edges()
		if not s.is_valid_int():
			return Result.failure("%s 类型错误（期望正整数）" % path)
		var parsed := s.to_int()
		if parsed <= 0:
			return Result.failure("%s 必须 > 0，实际: %d" % [path, parsed])
		return Result.success(parsed)
	return Result.failure("%s 类型错误（期望正整数）" % path)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var int_read := _parse_int(value, path)
	if not int_read.ok:
		return int_read
	var n := int(int_read.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func _append_candidate(candidates_by_type: Dictionary, employee_type: String, staff_id: int) -> void:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty() or staff_id <= 0:
		return
	if not candidates_by_type.has(emp_id):
		candidates_by_type[emp_id] = []
	var ids: Array = candidates_by_type[emp_id]
	if ids.find(staff_id) >= 0:
		return
	ids.append(staff_id)
	candidates_by_type[emp_id] = ids

static func _take_candidate_id(
	candidates_by_type: Dictionary,
	employee_type: String,
	assigned_ids: Dictionary,
	used_global_ids: Dictionary
) -> int:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return -1
	if not candidates_by_type.has(emp_id):
		return -1
	var ids: Array = candidates_by_type[emp_id]
	for staff_id_val in ids:
		var staff_id := int(staff_id_val)
		if staff_id <= 0:
			continue
		if assigned_ids.has(staff_id) or used_global_ids.has(staff_id):
			continue
		return staff_id
	return -1
