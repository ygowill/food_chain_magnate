extends RefCounted

const RequiredFieldsClass = preload("res://core/state/serialization/round_state_parser_required_fields.gd")
const OptionalFieldsClass = preload("res://core/state/serialization/round_state_parser_optional_fields.gd")
const StateSchemaRegistryClass = preload("res://core/state/state_schema_registry.gd")

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

	var required_read := RequiredFieldsClass.apply(rs, out)
	if not required_read.ok:
		return required_read
	out = required_read.value

	var optional_read := OptionalFieldsClass.apply(rs, out)
	if not optional_read.ok:
		return optional_read
	out = optional_read.value

	# 模块扩展字段：按 StateSchemaRegistry 声明，对指定路径的 Dict 执行 int-key 归一化
	var schema_norm := StateSchemaRegistryClass.normalize_int_key_dicts_in_container("round_state", out, "GameState.round_state")
	if not schema_norm.ok:
		return schema_norm
	out = schema_norm.value

	return Result.success(out)
