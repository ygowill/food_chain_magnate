extends RefCounted

const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")

static func parse_round_state(value) -> Result:
	if not (value is Dictionary):
		return Result.failure("GameState.round_state 缺失或类型错误（期望 Dictionary）")
	var rs: Dictionary = value
	for key in ["mandatory_actions_completed", "actions_this_round", "action_counts", "sub_phase_passed"]:
		if not rs.has(key):
			return Result.failure("GameState.round_state 缺少字段: %s" % key)

	var out: Dictionary = rs.duplicate(true)

	# actions_this_round：结构较灵活（调试/测试字段较多），这里只做容器类型严格检查
	if not (rs.get("actions_this_round", null) is Array):
		return Result.failure("GameState.round_state.actions_this_round 类型错误（期望 Array）")

	# mandatory_actions_completed: key 必须为玩家 id（字符串形式），内部统一转为 int key
	var mac_val = rs.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return Result.failure("GameState.round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
	var mac_norm := {}
	for k in mac_val.keys():
		if not (k is String) or not str(k).is_valid_int():
			return Result.failure("GameState.round_state.mandatory_actions_completed key 必须为数字字符串，实际: %s" % str(k))
		var pid: int = str(k).to_int()
		if pid < 0:
			return Result.failure("GameState.round_state.mandatory_actions_completed key 不能为负数: %d" % pid)
		var actions_val = mac_val.get(k, null)
		if not (actions_val is Array):
			return Result.failure("GameState.round_state.mandatory_actions_completed[%s] 类型错误（期望 Array）" % str(k))
		for i in range(actions_val.size()):
			if not (actions_val[i] is String):
				return Result.failure("GameState.round_state.mandatory_actions_completed[%s][%d] 类型错误（期望 String）" % [str(k), i])
		var actions_out: Array[String] = []
		for i in range(actions_val.size()):
			actions_out.append(actions_val[i])
		mac_norm[pid] = actions_out
	out["mandatory_actions_completed"] = mac_norm

	# sub_phase_passed: key 必须为玩家 id（字符串形式），内部统一转为 int key
	var sp_val = rs.get("sub_phase_passed", null)
	if not (sp_val is Dictionary):
		return Result.failure("GameState.round_state.sub_phase_passed 类型错误（期望 Dictionary）")
	var sp_norm := {}
	for k in sp_val.keys():
		if not (k is String) or not str(k).is_valid_int():
			return Result.failure("GameState.round_state.sub_phase_passed key 必须为数字字符串，实际: %s" % str(k))
		var pid: int = str(k).to_int()
		if pid < 0:
			return Result.failure("GameState.round_state.sub_phase_passed key 不能为负数: %d" % pid)
		var passed_val = sp_val.get(k, null)
		if not (passed_val is bool):
			return Result.failure("GameState.round_state.sub_phase_passed[%s] 类型错误（期望 bool）" % str(k))
		sp_norm[pid] = bool(passed_val)
	out["sub_phase_passed"] = sp_norm

	# action_counts: key 必须为玩家 id（字符串形式），内部统一转为 int key
	var ac_val = rs.get("action_counts", null)
	if not (ac_val is Dictionary):
		return Result.failure("GameState.round_state.action_counts 类型错误（期望 Dictionary）")
	var ac_norm := {}
	for k in ac_val.keys():
		if not (k is String) or not str(k).is_valid_int():
			return Result.failure("GameState.round_state.action_counts key 必须为数字字符串，实际: %s" % str(k))
		var pid: int = str(k).to_int()
		if pid < 0:
			return Result.failure("GameState.round_state.action_counts key 不能为负数: %d" % pid)
		var per_val = ac_val.get(k, null)
		if not (per_val is Dictionary):
			return Result.failure("GameState.round_state.action_counts[%s] 类型错误（期望 Dictionary）" % str(k))
		var per: Dictionary = per_val
		var per_norm := {}
		for action_id in per.keys():
			if not (action_id is String):
				return Result.failure("GameState.round_state.action_counts[%s] key 类型错误（期望 String）" % str(k))
			var action_key: String = str(action_id)
			if action_key.is_empty():
				return Result.failure("GameState.round_state.action_counts[%s] key 不能为空" % str(k))
			var v_read := ParseHelpers.parse_non_negative_int(per.get(action_id, null), "GameState.round_state.action_counts[%s].%s" % [str(k), action_key])
			if not v_read.ok:
				return v_read
			per_norm[action_key] = int(v_read.value)
		ac_norm[pid] = per_norm
	out["action_counts"] = ac_norm

	# price_modifiers: per-player modifier dict（值允许为负数）
	if rs.has("price_modifiers"):
		var pm_val = rs.get("price_modifiers", null)
		if not (pm_val is Dictionary):
			return Result.failure("GameState.round_state.price_modifiers 类型错误（期望 Dictionary）")
		var pm_norm := {}
		for k in pm_val.keys():
			if not (k is String) or not str(k).is_valid_int():
				return Result.failure("GameState.round_state.price_modifiers key 必须为数字字符串，实际: %s" % str(k))
			var pid: int = str(k).to_int()
			if pid < 0:
				return Result.failure("GameState.round_state.price_modifiers key 不能为负数: %d" % pid)
			var per_val = pm_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("GameState.round_state.price_modifiers[%s] 类型错误（期望 Dictionary）" % str(k))
			var per: Dictionary = per_val
			var per_norm := {}
			for modifier_key in per.keys():
				if not (modifier_key is String):
					return Result.failure("GameState.round_state.price_modifiers[%s] key 类型错误（期望 String）" % str(k))
				var mk: String = str(modifier_key)
				if mk.is_empty():
					return Result.failure("GameState.round_state.price_modifiers[%s] key 不能为空" % str(k))
				var v_read := ParseHelpers.parse_int(per.get(modifier_key, null), "GameState.round_state.price_modifiers[%s].%s" % [str(k), mk])
				if not v_read.ok:
					return v_read
				per_norm[mk] = int(v_read.value)
			pm_norm[pid] = per_norm
		out["price_modifiers"] = pm_norm

	# immediate_train_pending: per-player {employee_type -> count}
	if rs.has("immediate_train_pending"):
		var itp_val = rs.get("immediate_train_pending", null)
		if not (itp_val is Dictionary):
			return Result.failure("GameState.round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		var itp_norm := {}
		for k in itp_val.keys():
			if not (k is String) or not str(k).is_valid_int():
				return Result.failure("GameState.round_state.immediate_train_pending key 必须为数字字符串，实际: %s" % str(k))
			var pid: int = str(k).to_int()
			if pid < 0:
				return Result.failure("GameState.round_state.immediate_train_pending key 不能为负数: %d" % pid)
			var per_val = itp_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("GameState.round_state.immediate_train_pending[%s] 类型错误（期望 Dictionary）" % str(k))
			var per: Dictionary = per_val
			var per_norm := {}
			for emp_id in per.keys():
				if not (emp_id is String):
					return Result.failure("GameState.round_state.immediate_train_pending[%s] key 类型错误（期望 String）" % str(k))
				var emp_key: String = str(emp_id)
				if emp_key.is_empty():
					return Result.failure("GameState.round_state.immediate_train_pending[%s] key 不能为空" % str(k))
				var v_read := ParseHelpers.parse_non_negative_int(per.get(emp_id, null), "GameState.round_state.immediate_train_pending[%s].%s" % [str(k), emp_key])
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
		var all_val = rs.get(counter_key, null)
		if not (all_val is Dictionary):
			return Result.failure("GameState.round_state.%s 类型错误（期望 Dictionary）" % counter_key)
		var norm := {}
		for k in all_val.keys():
			if not (k is String) or not str(k).is_valid_int():
				return Result.failure("GameState.round_state.%s key 必须为数字字符串，实际: %s" % [counter_key, str(k)])
			var pid: int = str(k).to_int()
			if pid < 0:
				return Result.failure("GameState.round_state.%s key 不能为负数: %d" % [counter_key, pid])
			var v_read := ParseHelpers.parse_non_negative_int(all_val.get(k, null), "GameState.round_state.%s[%s]" % [counter_key, str(k)])
			if not v_read.ok:
				return v_read
			norm[pid] = int(v_read.value)
		out[counter_key] = norm

	var per_player_key_int_keys := ["production_counts", "procurement_counts", "marketing_used"]
	for counter_key in per_player_key_int_keys:
		if not rs.has(counter_key):
			continue
		var all_val = rs.get(counter_key, null)
		if not (all_val is Dictionary):
			return Result.failure("GameState.round_state.%s 类型错误（期望 Dictionary）" % counter_key)
		var norm := {}
		for k in all_val.keys():
			if not (k is String) or not str(k).is_valid_int():
				return Result.failure("GameState.round_state.%s key 必须为数字字符串，实际: %s" % [counter_key, str(k)])
			var pid: int = str(k).to_int()
			if pid < 0:
				return Result.failure("GameState.round_state.%s key 不能为负数: %d" % [counter_key, pid])
			var per_val = all_val.get(k, null)
			if not (per_val is Dictionary):
				return Result.failure("GameState.round_state.%s[%s] 类型错误（期望 Dictionary）" % [counter_key, str(k)])
			var per: Dictionary = per_val
			var per_norm := {}
			for item_key in per.keys():
				if not (item_key is String):
					return Result.failure("GameState.round_state.%s[%s] key 类型错误（期望 String）" % [counter_key, str(k)])
				var ik: String = str(item_key)
				if ik.is_empty():
					return Result.failure("GameState.round_state.%s[%s] key 不能为空" % [counter_key, str(k)])
				var v_read := ParseHelpers.parse_non_negative_int(per.get(item_key, null), "GameState.round_state.%s[%s].%s" % [counter_key, str(k), ik])
				if not v_read.ok:
					return v_read
				per_norm[ik] = int(v_read.value)
			norm[pid] = per_norm
		out[counter_key] = norm

	return Result.success(out)

