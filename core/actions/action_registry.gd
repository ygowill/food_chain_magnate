# 动作注册表
# 管理所有动作执行器的注册、查询和校验
class_name ActionRegistry
extends RefCounted

# 注册的执行器
# action_id -> ActionExecutor
var _executors: Dictionary = {}

# 动作可用性（phase/sub_phase -> action_ids）
var _availability_registry = null

# 校验器
# action_id -> Array[{id, validator, priority}]
var _validators_by_action: Dictionary = {}

# 全局校验器（对所有动作执行）
var _global_validators: Array[Dictionary] = []

# === 执行器管理 ===

# 注册执行器
func register_executor(executor: ActionExecutor) -> void:
	if executor.action_id.is_empty():
		GameLog.error("ActionRegistry", "执行器缺少 action_id")
		return

	if _executors.has(executor.action_id):
		GameLog.warn("ActionRegistry", "覆盖已存在的执行器: %s" % executor.action_id)

	_executors[executor.action_id] = executor
	GameLog.info("ActionRegistry", "注册执行器: %s" % executor.action_id)

func set_availability_registry(registry) -> void:
	_availability_registry = registry

func get_availability_registry():
	return _availability_registry

# 批量注册
func register_executors(executors: Array[ActionExecutor]) -> void:
	for executor in executors:
		register_executor(executor)

# 注销执行器
func unregister_executor(action_id: String) -> bool:
	if _executors.has(action_id):
		_executors.erase(action_id)
		GameLog.info("ActionRegistry", "注销执行器: %s" % action_id)
		return true
	return false

# 获取执行器
func get_executor(action_id: String) -> ActionExecutor:
	return _executors.get(action_id, null)

# 检查执行器是否存在
func has_executor(action_id: String) -> bool:
	return _executors.has(action_id)

# 获取所有动作ID
func get_all_action_ids() -> Array:
	return _executors.keys()

# 获取所有执行器元数据
func get_all_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action_id in _executors:
		result.append(_executors[action_id].get_metadata())
	return result

# === 校验器管理 ===

# 注册全局校验器
# 对所有动作执行前调用
func register_global_validator(
	validator_id: String,
	validator: Callable,
	priority: int = 100
) -> void:
	_global_validators.append({
		"id": validator_id,
		"validator": validator,
		"priority": priority
	})
	_global_validators.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return str(a.id) < str(b.id)
	)
	GameLog.info("ActionRegistry", "注册全局校验器: %s (优先级: %d)" % [validator_id, priority])

# 注销全局校验器
func unregister_global_validator(validator_id: String) -> bool:
	for i in range(_global_validators.size() - 1, -1, -1):
		if _global_validators[i].id == validator_id:
			_global_validators.remove_at(i)
			return true
	return false

# 注册特定动作的校验器
func register_validator(
	action_id: String,
	validator_id: String,
	validator: Callable,
	priority: int = 100
) -> void:
	if not _validators_by_action.has(action_id):
		_validators_by_action[action_id] = []

	var list: Array = _validators_by_action[action_id]
	for i in range(list.size() - 1, -1, -1):
		if str(list[i].id) == validator_id:
			list.remove_at(i)

	list.append({
		"id": validator_id,
		"validator": validator,
		"priority": priority
	})
	list.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		return str(a.id) < str(b.id)
	)
	_validators_by_action[action_id] = list

func unregister_validator(action_id: String, validator_id: String) -> bool:
	if not _validators_by_action.has(action_id):
		return false

	var list: Array = _validators_by_action[action_id]
	for i in range(list.size() - 1, -1, -1):
		if str(list[i].id) == validator_id:
			list.remove_at(i)
			_validators_by_action[action_id] = list
			return true
	return false

# === 执行校验 ===

# 运行所有校验器
func run_validators(state: GameState, command: Command) -> Result:
	# 0. 动作可用性（phase/sub_phase gating）
	if _availability_registry != null:
		if _availability_registry.has_method("validate_command"):
			var gate: Result = _availability_registry.validate_command(state, command)
			if not gate.ok:
				return gate

	# 1. 运行全局校验器
	for validator_data in _global_validators:
		var result = validator_data.validator.call(state, command)
		if result is Result and not result.ok:
			return result

	# 2. 运行特定动作校验器
	var list: Array = _validators_by_action.get(command.action_id, [])
	for validator_data in list:
		var result = validator_data.validator.call(state, command)
		if result is Result and not result.ok:
			return result

	return Result.success()

# === 按阶段/子阶段查询 ===

# 获取当前阶段可用的动作
func get_available_actions(state: GameState) -> Array[String]:
	if _availability_registry != null and _availability_registry.has_method("get_available_action_ids"):
		return _availability_registry.get_available_action_ids(str(state.phase), str(state.sub_phase))

	var result: Array[String] = []

	for action_id in _executors:
		var executor: ActionExecutor = _executors[action_id]

		# 检查阶段限制
		if executor.allowed_phases.size() > 0:
			if not executor.allowed_phases.has(state.phase):
				continue

		# 检查子阶段限制
		if executor.allowed_sub_phases.size() > 0 and not state.sub_phase.is_empty():
			if not executor.allowed_sub_phases.has(state.sub_phase):
				continue

		result.append(action_id)

	return result

# 获取玩家可执行的动作
func get_player_available_actions(state: GameState, player_id: int) -> Array[String]:
	var available := get_available_actions(state)
	var result: Array[String] = []

	for action_id in available:
		var executor := get_executor(action_id)
		if executor == null:
			continue

		# 创建测试命令
		var test_command := Command.create(action_id, player_id)
		test_command.phase = state.phase
		test_command.sub_phase = state.sub_phase

		# 基础校验
		var validate_result := executor.validate(state, test_command)
		if validate_result.ok:
			result.append(action_id)

	return result

# 获取强制动作
func get_mandatory_actions(state: GameState) -> Array[String]:
	var result: Array[String] = []

	for action_id in _executors:
		var executor: ActionExecutor = _executors[action_id]
		if executor.is_mandatory:
			# 检查阶段/子阶段
			if _availability_registry != null and _availability_registry.has_method("is_action_available"):
				if not _availability_registry.is_action_available(action_id, str(state.phase), str(state.sub_phase)):
					continue
			else:
				if executor.allowed_phases.size() > 0:
					if not executor.allowed_phases.has(state.phase):
						continue
			result.append(action_id)

	return result

# === 调试 ===

func dump() -> String:
	var output := "=== ActionRegistry ===\n"
	output += "Registered Executors: %d\n" % _executors.size()

	for action_id in _executors:
		var executor: ActionExecutor = _executors[action_id]
		output += "  %s: %s\n" % [action_id, executor.display_name]
		if executor.allowed_phases.size() > 0:
			output += "    Phases: %s\n" % ", ".join(executor.allowed_phases)
		if executor.allowed_sub_phases.size() > 0:
			output += "    SubPhases: %s\n" % ", ".join(executor.allowed_sub_phases)

	output += "Global Validators: %d\n" % _global_validators.size()
	for v in _global_validators:
		output += "  %s (priority: %d)\n" % [v.id, v.priority]

	var action_validator_count := 0
	for action_id in _validators_by_action:
		action_validator_count += _validators_by_action[action_id].size()

	output += "Action Validators: %d\n" % action_validator_count
	var action_ids := _validators_by_action.keys()
	action_ids.sort()
	for action_id in action_ids:
		var list: Array = _validators_by_action[action_id]
		for v in list:
			output += "  %s:%s (priority: %d)\n" % [action_id, str(v.id), int(v.priority)]

	return output

func get_status() -> Dictionary:
	var action_validator_count := 0
	for action_id in _validators_by_action:
		action_validator_count += _validators_by_action[action_id].size()

	return {
		"executor_count": _executors.size(),
		"global_validator_count": _global_validators.size(),
		"action_validator_count": action_validator_count,
		"action_ids": _executors.keys()
	}
