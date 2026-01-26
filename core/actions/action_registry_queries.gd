# ActionRegistry：查询/过滤辅助（不包含注册与校验器管理）
# 目的：把“按阶段/玩家查询动作”的逻辑从 ActionRegistry 主体中拆出，降低单文件职责与体积。
extends RefCounted

static func get_available_actions(registry, state) -> Array[String]:
	var availability = null
	if registry.has_method("get_availability_registry"):
		availability = registry.get_availability_registry()

	if availability != null and availability.has_method("get_available_action_ids"):
		var ids: Array[String] = availability.get_available_action_ids(str(state.phase), str(state.sub_phase))
		var filtered: Array[String] = []
		for aid in ids:
			var ex = registry.get_executor(aid)
			if ex != null and ex.is_internal:
				continue
			filtered.append(aid)
		return filtered

	var result: Array[String] = []
	for action_id in registry.get_all_action_ids():
		var executor = registry.get_executor(action_id)
		if executor == null:
			continue
		if executor.is_internal:
			continue

		if executor.allowed_phases.size() > 0:
			if not executor.allowed_phases.has(state.phase):
				continue

		if executor.allowed_sub_phases.size() > 0 and not state.sub_phase.is_empty():
			if not executor.allowed_sub_phases.has(state.sub_phase):
				continue

		result.append(action_id)

	return result

static func get_player_available_actions(registry, state, player_id: int) -> Array[String]:
	var available := get_available_actions(registry, state)
	var result: Array[String] = []

	for action_id in available:
		var executor = registry.get_executor(action_id)
		if executor == null:
			continue

		var test_command := Command.create(action_id, player_id)
		test_command.phase = state.phase
		test_command.sub_phase = state.sub_phase

		var validate_result: Result = executor.validate(state, test_command)
		if validate_result.ok:
			result.append(action_id)

	return result

static func get_player_initiatable_actions(registry, state, player_id: int) -> Array[String]:
	var available := get_available_actions(registry, state)
	var result: Array[String] = []

	for action_id in available:
		var executor = registry.get_executor(action_id)
		if executor == null:
			continue

		var test_command := Command.create(action_id, player_id)
		test_command.phase = state.phase
		test_command.sub_phase = state.sub_phase

		var validate_result: Result = executor.validate(state, test_command)
		if validate_result.ok:
			result.append(action_id)
			continue

		if _is_missing_params_error(validate_result):
			var can_initiate := true
			if executor.has_method("can_initiate"):
				var v = executor.can_initiate(state, player_id)
				if v is bool:
					can_initiate = bool(v)
			if can_initiate:
				result.append(action_id)

	return result

static func get_mandatory_actions(registry, state) -> Array[String]:
	var result: Array[String] = []
	var availability = null
	if registry.has_method("get_availability_registry"):
		availability = registry.get_availability_registry()

	for action_id in registry.get_all_action_ids():
		var executor = registry.get_executor(action_id)
		if executor == null:
			continue
		if not executor.is_mandatory:
			continue

		if availability != null and availability.has_method("is_action_available"):
			if not availability.is_action_available(action_id, str(state.phase), str(state.sub_phase)):
				continue
		else:
			if executor.allowed_phases.size() > 0:
				if not executor.allowed_phases.has(state.phase):
					continue

		result.append(action_id)

	return result

static func _is_missing_params_error(r: Result) -> bool:
	if r == null or r.ok:
		return false
	return int(r.error_code) == Result.ErrorCode.MISSING_PARAMS
