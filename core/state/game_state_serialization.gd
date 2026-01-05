# GameState 序列化/反序列化（Fail Fast）
# 负责：GameState <-> Dictionary 的严格解析与 JSON-safe 转换。
class_name GameStateSerialization
extends RefCounted

static func to_dict(state, schema_version: int) -> Dictionary:
	return {
		"schema_version": schema_version,
		"round_number": state.round_number,
		"phase": state.phase,
		"sub_phase": state.sub_phase,
		"turn_order": state.turn_order,
		"current_player_index": state.current_player_index,
		"selection_order": state.selection_order,
		"bank": state.bank,
		"rules": _to_json_safe(state.rules),
		"modules": state.modules,
		"players": state.players,
		"map": _to_json_safe(state.map),
		"employee_pool": state.employee_pool,
		"milestone_pool": state.milestone_pool,
		"marketing_instances": state.marketing_instances,
		"round_state": _to_json_safe(state.round_state),
		"seed": state.seed
	}

# 将 Variant 深度转换为 JSON 友好结构（用于存档与哈希）
static func _to_json_safe(value):
	match typeof(value):
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				# JSON object key 必须是字符串；这里保持稳定且兼容反序列化
				out[str(k)] = _to_json_safe(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for item in value:
				out_arr.append(_to_json_safe(item))
			return out_arr
		_:
			return value

static func apply_from_dict(state, data: Dictionary, expected_schema_version: int) -> Result:
	if not (data is Dictionary):
		return Result.failure("GameState.from_dict: data 类型错误（期望 Dictionary）")

	var schema_read := _parse_int(data.get("schema_version", null), "GameState.schema_version")
	if not schema_read.ok:
		return schema_read
	var schema_version: int = int(schema_read.value)
	if schema_version != expected_schema_version:
		return Result.failure("不支持的 GameState.schema_version: %d (期望: %d)" % [schema_version, expected_schema_version])

	var round_read := _parse_non_negative_int(data.get("round_number", null), "GameState.round_number")
	if not round_read.ok:
		return round_read
	state.round_number = int(round_read.value)

	var phase_val = data.get("phase", null)
	if not (phase_val is String):
		return Result.failure("GameState.phase 缺失或类型错误（期望 String）")
	state.phase = str(phase_val)

	var sub_phase_val = data.get("sub_phase", null)
	if not (sub_phase_val is String):
		return Result.failure("GameState.sub_phase 缺失或类型错误（期望 String）")
	state.sub_phase = str(sub_phase_val)

	var turn_order_read := _parse_int_array(data.get("turn_order", null), "GameState.turn_order")
	if not turn_order_read.ok:
		return turn_order_read
	state.turn_order = turn_order_read.value

	var cpi_read := _parse_non_negative_int(data.get("current_player_index", null), "GameState.current_player_index")
	if not cpi_read.ok:
		return cpi_read
	state.current_player_index = int(cpi_read.value)

	var selection_order_read := _parse_int_array(data.get("selection_order", null), "GameState.selection_order")
	if not selection_order_read.ok:
		return selection_order_read
	state.selection_order = selection_order_read.value

	var bank_val = data.get("bank", null)
	if not (bank_val is Dictionary):
		return Result.failure("GameState.bank 缺失或类型错误（期望 Dictionary）")
	var bank: Dictionary = bank_val
	for k in ["total", "broke_count", "ceo_slots_after_first_break", "reserve_added_total", "removed_total"]:
		if not bank.has(k):
			return Result.failure("GameState.bank 缺少字段: %s" % k)
	var bank_total_read := _parse_int(bank.get("total", null), "GameState.bank.total")
	if not bank_total_read.ok:
		return bank_total_read
	var broke_count_read := _parse_non_negative_int(bank.get("broke_count", null), "GameState.bank.broke_count")
	if not broke_count_read.ok:
		return broke_count_read
	var ceo_slots_after_read := _parse_int(bank.get("ceo_slots_after_first_break", null), "GameState.bank.ceo_slots_after_first_break")
	if not ceo_slots_after_read.ok:
		return ceo_slots_after_read
	var reserve_added_total_read := _parse_non_negative_int(bank.get("reserve_added_total", null), "GameState.bank.reserve_added_total")
	if not reserve_added_total_read.ok:
		return reserve_added_total_read
	var removed_total_read := _parse_non_negative_int(bank.get("removed_total", null), "GameState.bank.removed_total")
	if not removed_total_read.ok:
		return removed_total_read
	state.bank = {
		"total": int(bank_total_read.value),
		"broke_count": int(broke_count_read.value),
		"ceo_slots_after_first_break": int(ceo_slots_after_read.value),
		"reserve_added_total": int(reserve_added_total_read.value),
		"removed_total": int(removed_total_read.value),
	}

	var rules_val = data.get("rules", null)
	if not (rules_val is Dictionary):
		return Result.failure("GameState.rules 缺失或类型错误（期望 Dictionary）")
	var rules: Dictionary = rules_val
	if rules.is_empty():
		return Result.failure("GameState.rules 不能为空")
	var parsed_rules := {}
	for k in rules.keys():
		if not (k is String):
			return Result.failure("GameState.rules key 类型错误（期望 String）")
		var key := str(k)
		var v_read := _parse_int(rules.get(k, null), "GameState.rules.%s" % key)
		if not v_read.ok:
			return v_read
		parsed_rules[key] = int(v_read.value)
	state.rules = parsed_rules

	var modules_val = data.get("modules", null)
	if not (modules_val is Array):
		return Result.failure("GameState.modules 缺失或类型错误（期望 Array[String]）")
	var modules_any: Array = modules_val
	var modules_out: Array[String] = []
	var module_seen := {}
	for i in range(modules_any.size()):
		var m_val = modules_any[i]
		if not (m_val is String):
			return Result.failure("GameState.modules[%d] 类型错误（期望 String）" % i)
		var mid: String = str(m_val)
		if mid.is_empty():
			return Result.failure("GameState.modules[%d] 不能为空" % i)
		if module_seen.has(mid):
			return Result.failure("GameState.modules 出现重复 id: %s" % mid)
		module_seen[mid] = true
		modules_out.append(mid)
	state.modules = modules_out

	var players_val = data.get("players", null)
	if not (players_val is Array):
		return Result.failure("GameState.players 缺失或类型错误（期望 Array）")
	var players_any: Array = players_val
	var players_out: Array[Dictionary] = []
	for i in range(players_any.size()):
		var p_val = players_any[i]
		if not (p_val is Dictionary):
			return Result.failure("GameState.players[%d] 类型错误（期望 Dictionary）" % i)
		players_out.append(p_val)
	state.players = players_out

	var map_val = data.get("map", null)
	if not (map_val is Dictionary):
		return Result.failure("GameState.map 缺失或类型错误（期望 Dictionary）")
	var map_read := _decode_map(map_val)
	if not map_read.ok:
		return map_read
	state.map = map_read.value

	var employee_pool_val = data.get("employee_pool", null)
	if not (employee_pool_val is Dictionary):
		return Result.failure("GameState.employee_pool 缺失或类型错误（期望 Dictionary）")
	var pool_read := _parse_non_negative_int_dict(employee_pool_val, "GameState.employee_pool")
	if not pool_read.ok:
		return pool_read
	state.employee_pool = pool_read.value

	var milestone_pool_val = data.get("milestone_pool", null)
	if not (milestone_pool_val is Array):
		return Result.failure("GameState.milestone_pool 缺失或类型错误（期望 Array[String]）")
	var milestone_any: Array = milestone_pool_val
	var milestone_out: Array[String] = []
	for i in range(milestone_any.size()):
		var m_val = milestone_any[i]
		if not (m_val is String):
			return Result.failure("GameState.milestone_pool[%d] 类型错误（期望 String）" % i)
		var mid: String = str(m_val)
		if mid.is_empty():
			return Result.failure("GameState.milestone_pool[%d] 不能为空" % i)
		milestone_out.append(mid)
	state.milestone_pool = milestone_out

	var marketing_instances_val = data.get("marketing_instances", null)
	if not (marketing_instances_val is Array):
		return Result.failure("GameState.marketing_instances 缺失或类型错误（期望 Array）")
	var instances_any: Array = marketing_instances_val
	var instances_out: Array[Dictionary] = []
	for i in range(instances_any.size()):
		var inst_val = instances_any[i]
		if not (inst_val is Dictionary):
			return Result.failure("GameState.marketing_instances[%d] 类型错误（期望 Dictionary）" % i)
		instances_out.append(inst_val)
	state.marketing_instances = instances_out

	var round_state_read := _parse_round_state(data.get("round_state", null))
	if not round_state_read.ok:
		return round_state_read
	state.round_state = round_state_read.value

	var seed_read := _parse_non_negative_int(data.get("seed", null), "GameState.seed")
	if not seed_read.ok:
		return seed_read
	state.seed = int(seed_read.value)

	return Result.success(state)

# 反序列化地图：将 [x,y] 转回 Vector2i，并递归处理嵌套结构
static func _decode_map(value: Dictionary) -> Result:
	return _decode_value(value, "", "GameState.map")

static func _decode_value(value, key_hint: String, path: String) -> Result:
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			if not (k is String):
				return Result.failure("%s key 类型错误（期望 String）" % path)
			var ks: String = k
			var v_read := _decode_value(value[k], ks, "%s.%s" % [path, ks])
			if not v_read.ok:
				return v_read
			out[ks] = v_read.value
		return Result.success(out)

	if value is Array:
		# 形如 [x, y] 的坐标
		if value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			match key_hint:
				"grid_size", "tile_grid_size", "tile_origin", "anchor_pos", "entrance_pos", "world_pos", "parent_anchor", "board_pos":
					var x_read := _parse_int(value[0], "%s[0]" % path)
					if not x_read.ok:
						return x_read
					var y_read := _parse_int(value[1], "%s[1]" % path)
					if not y_read.ok:
						return y_read
					return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

		# 形如 [[x,y], [x,y], ...] 的坐标列表（例如 footprint/path/house cells）
		var all_vec2i := true
		for item in value:
			if not (item is Array and item.size() == 2 and (item[0] is int or item[0] is float) and (item[1] is int or item[1] is float)):
				all_vec2i = false
				break
		if all_vec2i and value.size() > 0:
			var out_vecs: Array[Vector2i] = []
			for i in range(value.size()):
				var item: Array = value[i]
				var x_read := _parse_int(item[0], "%s[%d][0]" % [path, i])
				if not x_read.ok:
					return x_read
				var y_read := _parse_int(item[1], "%s[%d][1]" % [path, i])
				if not y_read.ok:
					return y_read
				out_vecs.append(Vector2i(int(x_read.value), int(y_read.value)))
			return Result.success(out_vecs)

		var out_arr := []
		for i in range(value.size()):
			var item = value[i]
			var item_read := _decode_value(item, key_hint, "%s[%d]" % [path, i])
			if not item_read.ok:
				return item_read
			out_arr.append(item_read.value)
		return Result.success(out_arr)

	return Result.success(value)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func _parse_int_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array[int]）" % path)
	var out: Array[int] = []
	for i in range(value.size()):
		var item_read := _parse_int(value[i], "%s[%d]" % [path, i])
		if not item_read.ok:
			return item_read
		out.append(int(item_read.value))
	return Result.success(out)

static func _parse_non_negative_int_dict(value, path: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	var out := {}
	for k in value.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String）" % path)
		var key := str(k)
		var v_read := _parse_non_negative_int(value.get(k, null), "%s.%s" % [path, key])
		if not v_read.ok:
			return v_read
		out[key] = int(v_read.value)
	return Result.success(out)

static func _parse_round_state(value) -> Result:
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
			var v_read := _parse_non_negative_int(per.get(action_id, null), "GameState.round_state.action_counts[%s].%s" % [str(k), action_key])
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
				var v_read := _parse_int(per.get(modifier_key, null), "GameState.round_state.price_modifiers[%s].%s" % [str(k), mk])
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
				var v_read := _parse_non_negative_int(per.get(emp_id, null), "GameState.round_state.immediate_train_pending[%s].%s" % [str(k), emp_key])
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
			var v_read := _parse_non_negative_int(all_val.get(k, null), "GameState.round_state.%s[%s]" % [counter_key, str(k)])
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
				var v_read := _parse_non_negative_int(per.get(item_key, null), "GameState.round_state.%s[%s].%s" % [counter_key, str(k), ik])
				if not v_read.ok:
					return v_read
				per_norm[ik] = int(v_read.value)
			norm[pid] = per_norm
		out[counter_key] = norm

	return Result.success(out)
