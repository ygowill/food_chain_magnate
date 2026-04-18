extends RefCounted

const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")
const PlayerIdKeysClass = preload("res://core/state/serialization/round_state_player_id_keys.gd")

static func apply(rs: Dictionary, out: Dictionary) -> Result:
	# price_modifiers: per-player modifier dict（值允许为负数）
	if rs.has("price_modifiers"):
		var dict_path := "GameState.round_state.price_modifiers"
		var pm_val = rs.get("price_modifiers", null)
		if not (pm_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var pm_norm := {}
		for k in pm_val.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var per_val = pm_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for modifier_key in per.keys():
				if not (modifier_key is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
				var mk: String = str(modifier_key)
				if mk.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
				var v_read := ParseHelpers.parse_int(per.get(modifier_key, null), "%s[%s].%s" % [dict_path, str(k), mk])
				if not v_read.ok:
					return v_read
				per_norm[mk] = int(v_read.value)
			pm_norm[pid] = per_norm
		out["price_modifiers"] = pm_norm

	# immediate_train_pending: per-player {employee_type -> count}
	if rs.has("immediate_train_pending"):
		var dict_path := "GameState.round_state.immediate_train_pending"
		var itp_val = rs.get("immediate_train_pending", null)
		if not (itp_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var itp_norm := {}
		for k in itp_val.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var per_val = itp_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for emp_id in per.keys():
				if not (emp_id is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
				var emp_key: String = str(emp_id)
				if emp_key.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
				var v_read := ParseHelpers.parse_non_negative_int(per.get(emp_id, null), "%s[%s].%s" % [dict_path, str(k), emp_key])
				if not v_read.ok:
					return v_read
				per_norm[emp_key] = int(v_read.value)
			itp_norm[pid] = per_norm
		out["immediate_train_pending"] = itp_norm

	# RoundStateCounters：常用 per-player 计数（全部按玩家 id key 归一化为 int）
	var per_player_int_keys := ["recruit_used", "house_placement_counts"]
	for counter_key in per_player_int_keys:
		if not rs.has(counter_key):
			continue
		var dict_path := "GameState.round_state.%s" % counter_key
		var all_val = rs.get(counter_key, null)
		if not (all_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var norm := {}
		for k in all_val.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var v_read := ParseHelpers.parse_non_negative_int(all_val.get(k, null), "%s[%s]" % [dict_path, str(k)])
			if not v_read.ok:
				return v_read
			norm[pid] = int(v_read.value)
		out[counter_key] = norm

	var per_player_key_int_keys := ["production_counts", "procurement_counts", "marketing_used", "train_slot_usage"]
	for counter_key in per_player_key_int_keys:
		if not rs.has(counter_key):
			continue
		var dict_path := "GameState.round_state.%s" % counter_key
		var all_val = rs.get(counter_key, null)
		if not (all_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var norm := {}
		for k in all_val.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var per_val = all_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for item_key in per.keys():
				if not (item_key is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
				var ik: String = str(item_key)
				if ik.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
				var v_read := ParseHelpers.parse_non_negative_int(per.get(item_key, null), "%s[%s].%s" % [dict_path, str(k), ik])
				if not v_read.ok:
					return v_read
				per_norm[ik] = int(v_read.value)
			norm[pid] = per_norm
		out[counter_key] = norm

	# train_slot_usage_instances: per-player {trainer_id -> Array[int]}
	if rs.has("train_slot_usage_instances"):
		var dict_path := "GameState.round_state.train_slot_usage_instances"
		var tsui_val = rs.get("train_slot_usage_instances", null)
		if not (tsui_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var tsui_all: Dictionary = tsui_val
		var tsui_norm := {}
		for k in tsui_all.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var per_val = tsui_all.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for trainer_key in per.keys():
				if not (trainer_key is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
				var tid: String = str(trainer_key)
				if tid.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
				var arr_val = per.get(trainer_key, null)
				if not (arr_val is Array):
					return Result.failure("%s[%s].%s 类型错误（期望 Array[int]）" % [dict_path, str(k), tid])
				var arr_any: Array = arr_val
				var arr_norm: Array[int] = []
				for i in range(arr_any.size()):
					var v_read := ParseHelpers.parse_non_negative_int(arr_any[i], "%s[%s].%s[%d]" % [dict_path, str(k), tid, i])
					if not v_read.ok:
						return v_read
					arr_norm.append(int(v_read.value))
				per_norm[tid] = arr_norm
			tsui_norm[pid] = per_norm
		out["train_slot_usage_instances"] = tsui_norm

	# train_employee_locks: per-player {employee_type -> Array[{trainer_id, instance_idx}]}
	if rs.has("train_employee_locks"):
		var dict_path := "GameState.round_state.train_employee_locks"
		var tel_val = rs.get("train_employee_locks", null)
		if not (tel_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var tel_all: Dictionary = tel_val
		var tel_norm := {}
		for k in tel_all.keys():
			var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
			if not pid_read.ok:
				return pid_read
			var pid: int = int(pid_read.value)

			var per_val = tel_all.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for emp_key in per.keys():
				if not (emp_key is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
				var emp_id: String = str(emp_key)
				if emp_id.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
				var tokens_val = per.get(emp_key, null)
				if not (tokens_val is Array):
					return Result.failure("%s[%s].%s 类型错误（期望 Array）" % [dict_path, str(k), emp_id])
				var tokens_any: Array = tokens_val
				var tokens_norm: Array = []
				for i in range(tokens_any.size()):
					var t_val = tokens_any[i]
					if not (t_val is Dictionary):
						return Result.failure("%s[%s].%s[%d] 类型错误（期望 Dictionary）" % [dict_path, str(k), emp_id, i])
					var t: Dictionary = t_val
					var trainer_id_val = t.get("trainer_id", "")
					if not (trainer_id_val is String):
						return Result.failure("%s[%s].%s[%d].trainer_id 类型错误（期望 String）" % [dict_path, str(k), emp_id, i])
					var trainer_id: String = str(trainer_id_val)
					var idx_read := ParseHelpers.parse_non_negative_int(t.get("instance_idx", 0), "%s[%s].%s[%d].instance_idx" % [dict_path, str(k), emp_id, i])
					if not idx_read.ok:
						return idx_read
					tokens_norm.append({
						"trainer_id": trainer_id,
						"instance_idx": int(idx_read.value),
					})
				per_norm[emp_id] = tokens_norm
			tel_norm[pid] = per_norm
		out["train_employee_locks"] = tel_norm

	# staff_usage: {staff_id -> {track_id -> used_units}}
	if rs.has("staff_usage"):
		var dict_path := "GameState.round_state.staff_usage"
		var su_val = rs.get("staff_usage", null)
		if not (su_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var su_all: Dictionary = su_val
		var su_norm := {}
		for staff_id_key in su_all.keys():
			var staff_id_read := _parse_positive_int_key(staff_id_key, dict_path)
			if not staff_id_read.ok:
				return staff_id_read
			var staff_id: int = int(staff_id_read.value)

			var per_val = su_all.get(staff_id_key, null)
			if not (per_val is Dictionary):
				return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(staff_id_key)])
			var per: Dictionary = per_val
			var per_norm := {}
			for track_key in per.keys():
				if not (track_key is String):
					return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(staff_id_key)])
				var track_id: String = str(track_key).strip_edges()
				if track_id.is_empty():
					return Result.failure("%s[%s] key 不能为空" % [dict_path, str(staff_id_key)])
				var used_read := ParseHelpers.parse_non_negative_int(per.get(track_key, null), "%s[%s].%s" % [dict_path, str(staff_id_key), track_id])
				if not used_read.ok:
					return used_read
				per_norm[track_id] = int(used_read.value)
			su_norm[staff_id] = per_norm
		out["staff_usage"] = su_norm

	# staff_train_event_counts: {staff_id -> count}
	if rs.has("staff_train_event_counts"):
		var dict_path := "GameState.round_state.staff_train_event_counts"
		var stc_val = rs.get("staff_train_event_counts", null)
		if not (stc_val is Dictionary):
			return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
		var stc_all: Dictionary = stc_val
		var stc_norm := {}
		for staff_id_key in stc_all.keys():
			var staff_id_read := _parse_positive_int_key(staff_id_key, dict_path)
			if not staff_id_read.ok:
				return staff_id_read
			var staff_id: int = int(staff_id_read.value)
			var count_read := ParseHelpers.parse_non_negative_int(stc_all.get(staff_id_key, null), "%s[%s]" % [dict_path, str(staff_id_key)])
			if not count_read.ok:
				return count_read
			stc_norm[staff_id] = int(count_read.value)
		out["staff_train_event_counts"] = stc_norm

	return Result.success(out)

static func _parse_positive_int_key(key, path: String) -> Result:
	if key is int:
		if int(key) <= 0:
			return Result.failure("%s key 必须 > 0，实际: %d" % [path, int(key)])
		return Result.success(int(key))
	if key is String:
		var s := str(key).strip_edges()
		if not s.is_valid_int():
			return Result.failure("%s key 必须为正整数或数字字符串，实际: %s" % [path, str(key)])
		var parsed := s.to_int()
		if parsed <= 0:
			return Result.failure("%s key 必须 > 0，实际: %d" % [path, parsed])
		return Result.success(parsed)
	return Result.failure("%s key 类型错误（期望 int/String）" % path)
