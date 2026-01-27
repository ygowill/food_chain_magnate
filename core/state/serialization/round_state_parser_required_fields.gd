extends RefCounted

const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")
const PlayerIdKeysClass = preload("res://core/state/serialization/round_state_player_id_keys.gd")

static func apply(rs: Dictionary, out: Dictionary) -> Result:
	# mandatory_actions_completed: key 必须为玩家 id（字符串形式），内部统一转为 int key
	var dict_path := "GameState.round_state.mandatory_actions_completed"
	var mac_val = rs.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
	var mac_norm := {}
	for k in mac_val.keys():
		var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
		if not pid_read.ok:
			return pid_read
		var pid: int = int(pid_read.value)

		var actions_val = mac_val.get(k, null)
		if not (actions_val is Array):
			return Result.failure("%s[%s] 类型错误（期望 Array）" % [dict_path, str(k)])
		for i in range(actions_val.size()):
			if not (actions_val[i] is String):
				return Result.failure("%s[%s][%d] 类型错误（期望 String）" % [dict_path, str(k), i])
		var actions_out: Array[String] = []
		for i in range(actions_val.size()):
			actions_out.append(actions_val[i])
		mac_norm[pid] = actions_out
	out["mandatory_actions_completed"] = mac_norm

	# sub_phase_passed: key 必须为玩家 id（字符串形式），内部统一转为 int key
	dict_path = "GameState.round_state.sub_phase_passed"
	var sp_val = rs.get("sub_phase_passed", null)
	if not (sp_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
	var sp_norm := {}
	for k in sp_val.keys():
		var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
		if not pid_read.ok:
			return pid_read
		var pid: int = int(pid_read.value)

		var passed_val = sp_val.get(k, null)
		if not (passed_val is bool):
			return Result.failure("%s[%s] 类型错误（期望 bool）" % [dict_path, str(k)])
		sp_norm[pid] = bool(passed_val)
	out["sub_phase_passed"] = sp_norm

	# action_counts: key 必须为玩家 id（字符串形式），内部统一转为 int key
	dict_path = "GameState.round_state.action_counts"
	var ac_val = rs.get("action_counts", null)
	if not (ac_val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % dict_path)
	var ac_norm := {}
	for k in ac_val.keys():
		var pid_read := PlayerIdKeysClass.parse_player_id_key(k, dict_path)
		if not pid_read.ok:
			return pid_read
		var pid: int = int(pid_read.value)

		var per_val = ac_val.get(k, null)
		if not (per_val is Dictionary):
			return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [dict_path, str(k)])
		var per: Dictionary = per_val
		var per_norm := {}
		for action_id in per.keys():
			if not (action_id is String):
				return Result.failure("%s[%s] key 类型错误（期望 String）" % [dict_path, str(k)])
			var action_key: String = str(action_id)
			if action_key.is_empty():
				return Result.failure("%s[%s] key 不能为空" % [dict_path, str(k)])
			var v_read := ParseHelpers.parse_non_negative_int(per.get(action_id, null), "%s[%s].%s" % [dict_path, str(k), action_key])
			if not v_read.ok:
				return v_read
			per_norm[action_key] = int(v_read.value)
		ac_norm[pid] = per_norm
	out["action_counts"] = ac_norm

	return Result.success(out)

