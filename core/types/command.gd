# 命令数据结构
# 所有游戏状态变化都通过 Command 记录，支持回放和撤销
class_name Command
extends RefCounted

const JsonValueParseHelpersClass = preload("res://core/utils/json_value_parse_helpers.gd")

# === 核心字段 ===
var index: int = -1              # 全局序号（从 0 递增）
var action_id: String = ""       # 动作类型 ID，如 "Recruit", "Train", "PlaceRestaurant"
var actor: int = -1              # 执行者：玩家 ID (0-5) 或 -1 (系统动作)
var params: Dictionary = {}      # 动作参数（具体结构取决于 action_id）
var phase: String = ""           # 所在阶段
var sub_phase: String = ""       # 所在子阶段（工作阶段内）
var timestamp: int = -1          # 游戏内时间戳：round * 1000 + phase_index * 100 + sub_phase_index（-1 表示未设置）

# === 可选元数据 ===
var metadata: Dictionary = {}    # 调试信息、UI 提示、随机结果等

# === 构造函数 ===
func _init() -> void:
	pass

# === 序列化 ===
func to_dict() -> Dictionary:
	return {
		"index": index,
		"action_id": action_id,
		"actor": actor,
		"params": params,
		"phase": phase,
		"sub_phase": sub_phase,
		"timestamp": timestamp,
		"metadata": metadata
	}

static func from_dict(data: Dictionary) -> Result:
	return _parse_from_dict(data)

static func _require_key(data: Dictionary, key: String, path: String) -> Result:
	if not data.has(key):
		return Result.failure("%s 缺失" % path)
	return Result.success()

static func _parse_required_int_value_field(data: Dictionary, key: String, path: String) -> Result:
	var require := _require_key(data, key, path)
	if not require.ok:
		return require
	var read := JsonValueParseHelpersClass.parse_int_value(data.get(key, null), path)
	if not read.ok:
		return read
	return Result.success(int(read.value))

static func _parse_required_non_empty_string_field(data: Dictionary, key: String, path: String) -> Result:
	var require := _require_key(data, key, path)
	if not require.ok:
		return require
	var val = data.get(key, null)
	if not (val is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = str(val)
	if s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_required_string_field(data: Dictionary, key: String, path: String) -> Result:
	var require := _require_key(data, key, path)
	if not require.ok:
		return require
	var val = data.get(key, null)
	if not (val is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	return Result.success(str(val))

static func _parse_required_dict_with_string_keys(data: Dictionary, key: String, path: String) -> Result:
	var require := _require_key(data, key, path)
	if not require.ok:
		return require
	var val = data.get(key, null)
	if not (val is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	var dict: Dictionary = val
	for k in dict.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String）" % path)
	return Result.success(dict)

static func _parse_from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("Command.from_dict: data 类型错误（期望 Dictionary）")

	var cmd := Command.new()

	# index（仅用于调试；回放时会被 GameEngine 覆盖，但仍要求格式正确）
	var index_read := _parse_required_int_value_field(data, "index", "Command.index")
	if not index_read.ok:
		return index_read
	var index_val: int = int(index_read.value)
	if index_val < 0:
		return Result.failure("Command.index 不能为负数: %d" % index_val)
	cmd.index = index_val

	# action_id
	var action_read := _parse_required_non_empty_string_field(data, "action_id", "Command.action_id")
	if not action_read.ok:
		return action_read
	cmd.action_id = action_read.value

	# actor
	var actor_read := _parse_required_int_value_field(data, "actor", "Command.actor")
	if not actor_read.ok:
		return actor_read
	var actor_val: int = int(actor_read.value)
	if actor_val < -1:
		return Result.failure("Command.actor 非法: %d" % actor_val)
	cmd.actor = actor_val

	# params
	var params_read := _parse_required_dict_with_string_keys(data, "params", "Command.params")
	if not params_read.ok:
		return params_read
	cmd.params = params_read.value

	# phase
	var phase_read := _parse_required_non_empty_string_field(data, "phase", "Command.phase")
	if not phase_read.ok:
		return phase_read
	cmd.phase = phase_read.value

	# sub_phase（允许为空字符串）
	var sub_phase_read := _parse_required_string_field(data, "sub_phase", "Command.sub_phase")
	if not sub_phase_read.ok:
		return sub_phase_read
	cmd.sub_phase = sub_phase_read.value

	# timestamp
	var ts_read := _parse_required_int_value_field(data, "timestamp", "Command.timestamp")
	if not ts_read.ok:
		return ts_read
	var ts_val: int = int(ts_read.value)
	if ts_val < 0:
		return Result.failure("Command.timestamp 不能为负数: %d" % ts_val)
	cmd.timestamp = ts_val

	# metadata（允许空字典）
	var meta_read := _parse_required_dict_with_string_keys(data, "metadata", "Command.metadata")
	if not meta_read.ok:
		return meta_read
	cmd.metadata = meta_read.value

	return Result.success(cmd)

# === 工厂方法 ===
static func create(p_action_id: String, p_actor: int, p_params: Dictionary = {}) -> Command:
	var cmd := Command.new()
	cmd.action_id = p_action_id
	cmd.actor = p_actor
	cmd.params = p_params
	return cmd

static func create_system(p_action_id: String, p_params: Dictionary = {}) -> Command:
	return create(p_action_id, -1, p_params)

# === 判断方法 ===
func is_system_command() -> bool:
	return actor == -1

func is_player_command() -> bool:
	return actor >= 0

# === 调试 ===
func _to_string() -> String:
	if actor >= 0:
		return "[Command#%d %s by Player%d @%s]" % [index, action_id, actor, phase]
	else:
		return "[Command#%d %s (System) @%s]" % [index, action_id, phase]

func get_description() -> String:
	# 返回人类可读描述
	return metadata.get("description", action_id)

func get_short_description() -> String:
	if actor >= 0:
		return "P%d: %s" % [actor, action_id]
	return "Sys: %s" % action_id

# === 复制 ===
func duplicate_command() -> Command:
	var copy := Command.new()
	copy.index = index
	copy.action_id = action_id
	copy.actor = actor
	copy.params = params.duplicate(true)
	copy.phase = phase
	copy.sub_phase = sub_phase
	copy.timestamp = timestamp
	copy.metadata = metadata.duplicate(true)
	return copy

# === 验证 ===
func is_valid() -> bool:
	return not action_id.is_empty()
