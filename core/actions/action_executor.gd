# 动作执行器基类
# 定义动作执行的接口：校验、计算新状态、生成事件
class_name ActionExecutor
extends RefCounted

# 动作标识符
var action_id: String = ""

# 动作元数据
var display_name: String = ""
var description: String = ""
var allowed_phases: Array[String] = []  # 允许执行的阶段
var allowed_sub_phases: Array[String] = []  # 允许执行的子阶段
var requires_actor: bool = true  # 是否需要玩家执行
var is_mandatory: bool = false  # 是否是强制动作
var is_internal: bool = false  # 内部动作：不应出现在“可用动作列表”中（但可被直接执行）

# === 核心接口（子类必须实现） ===

# 校验动作是否可执行
# 返回 Result，ok=true 表示可执行
# 这是纯函数，不应修改任何状态
func validate(state: GameState, command: Command) -> Result:
	# 基础校验
	var base_result := _validate_base(state, command)
	if not base_result.ok:
		return base_result

	# 子类实现具体校验
	return _validate_specific(state, command)

# 计算新状态
# 返回 Result，value 为新的 GameState
# 这是纯函数，不应修改输入状态
func compute_new_state(state: GameState, command: Command) -> Result:
	# 先校验
	var validate_result := validate(state, command)
	if not validate_result.ok:
		return validate_result

	# 深拷贝状态
	var new_state := state.duplicate_state()

	# 子类实现具体状态变更
	var apply_result := _apply_changes(new_state, command)
	if not apply_result.ok:
		return apply_result

	return Result.success(new_state).with_warnings(apply_result.warnings)

# 生成事件
# 返回事件数组，用于通知其他系统
func generate_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	# 子类可覆盖此方法添加特定事件
	return _generate_specific_events(old_state, new_state, command)

# === 子类需要实现的方法 ===

# 具体校验逻辑
func _validate_specific(_state: GameState, _command: Command) -> Result:
	# 子类实现
	return Result.success()

# 应用状态变更
func _apply_changes(_state: GameState, _command: Command) -> Result:
	# 子类实现
	return Result.success()

# 生成特定事件
func _generate_specific_events(_old_state: GameState, _new_state: GameState, _command: Command) -> Array[Dictionary]:
	# 子类实现
	return []

# === 基础校验 ===

func _validate_base(state: GameState, command: Command) -> Result:
	# 校验动作ID
	if command.action_id != action_id:
		return Result.failure("动作ID不匹配: 期望 %s, 实际 %s" % [action_id, command.action_id])

	# 校验执行者
	if requires_actor:
		if command.actor < 0:
			return Result.failure("此动作需要玩家执行")
		if command.actor >= state.players.size():
			return Result.failure("无效的玩家ID: %d" % command.actor)

	return Result.success()

# === 辅助方法 ===

# 获取必需参数，如果不存在返回错误
func require_param(command: Command, key: String) -> Result:
	if not command.params.has(key):
		return Result.failure("缺少必需参数: %s" % key)
	return Result.success(command.params[key])

# === 严格参数解析（Fail Fast） ===

func require_array_param(command: Command, key: String) -> Result:
	if not command.params.has(key):
		return Result.failure("缺少参数: %s" % key)
	var value = command.params[key]
	if not (value is Array):
		return Result.failure("%s 必须为数组" % key)
	return Result.success(value)

func require_string_param(command: Command, key: String) -> Result:
	if not command.params.has(key):
		return Result.failure("缺少参数: %s" % key)
	var value = command.params[key]
	if not (value is String):
		return Result.failure("%s 必须为字符串" % key)
	var s: String = value
	if s.is_empty():
		return Result.failure("%s 不能为空" % key)
	return Result.success(s)

func optional_string_param(command: Command, key: String, default_value: String) -> Result:
	if not command.params.has(key):
		return Result.success(default_value)
	var value = command.params[key]
	if not (value is String):
		return Result.failure("%s 必须为字符串" % key)
	var s: String = value
	if s.is_empty():
		return Result.failure("%s 不能为空" % key)
	return Result.success(s)

func require_int_param(command: Command, key: String) -> Result:
	if not command.params.has(key):
		return Result.failure("缺少参数: %s" % key)
	return _parse_int_value(command.params[key], key)

func optional_int_param(command: Command, key: String, default_value: int) -> Result:
	if not command.params.has(key):
		return Result.success(default_value)
	return _parse_int_value(command.params[key], key)

func require_vector2i_param(command: Command, key: String) -> Result:
	var arr_result := require_array_param(command, key)
	if not arr_result.ok:
		return arr_result

	var arr: Array = arr_result.value
	if arr.size() != 2:
		return Result.failure("%s 格式错误（期望 [x,y]）" % key)

	var x_result := _parse_int_value(arr[0], "%s[0]" % key)
	if not x_result.ok:
		return x_result
	var y_result := _parse_int_value(arr[1], "%s[1]" % key)
	if not y_result.ok:
		return y_result

	return Result.success(Vector2i(int(x_result.value), int(y_result.value)))

static func _parse_int_value(value, key: String) -> Result:
	if value is int:
		return Result.success(value)
	if value is float:
		var f: float = value
		if f == int(f):
			return Result.success(int(f))
		return Result.failure("%s 必须为整数（不允许小数）" % key)
	return Result.failure("%s 必须为整数" % key)

# 获取玩家
func get_actor_player(state: GameState, command: Command) -> Dictionary:
	if command.actor >= 0 and command.actor < state.players.size():
		return state.players[command.actor]
	return {}

# === 元数据 ===

func get_metadata() -> Dictionary:
	return {
		"action_id": action_id,
		"display_name": display_name,
		"description": description,
		"allowed_phases": allowed_phases,
		"allowed_sub_phases": allowed_sub_phases,
		"requires_actor": requires_actor,
		"is_mandatory": is_mandatory,
		"is_internal": is_internal,
	}

func _to_string() -> String:
	return "[ActionExecutor: %s]" % action_id
