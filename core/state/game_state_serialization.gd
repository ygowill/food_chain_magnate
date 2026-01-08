# GameState 序列化/反序列化（Fail Fast）
# 负责：GameState <-> Dictionary 的严格解析与 JSON-safe 转换。
class_name GameStateSerialization
extends RefCounted

const JsonSafe = preload("res://core/state/serialization/json_safe.gd")
const ParseHelpers = preload("res://core/state/serialization/parse_helpers.gd")
const ValueDecoder = preload("res://core/state/serialization/value_decoder.gd")
const RoundStateParser = preload("res://core/state/serialization/round_state_parser.gd")

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
	return JsonSafe.to_json_safe(value)

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
	return ValueDecoder.decode_map(value)

static func _decode_value(value, key_hint: String, path: String) -> Result:
	return ValueDecoder.decode_value(value, key_hint, path)

static func _parse_int(value, path: String) -> Result:
	return ParseHelpers.parse_int(value, path)

static func _parse_non_negative_int(value, path: String) -> Result:
	return ParseHelpers.parse_non_negative_int(value, path)

static func _parse_int_array(value, path: String) -> Result:
	return ParseHelpers.parse_int_array(value, path)

static func _parse_non_negative_int_dict(value, path: String) -> Result:
	return ParseHelpers.parse_non_negative_int_dict(value, path)

static func _parse_round_state(value) -> Result:
	return RoundStateParser.parse_round_state(value)
