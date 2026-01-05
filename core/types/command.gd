# 命令数据结构
# 所有游戏状态变化都通过 Command 记录，支持回放和撤销
class_name Command
extends RefCounted

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

static func _parse_from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("Command.from_dict: data 类型错误（期望 Dictionary）")

	var cmd := Command.new()

	# index（仅用于调试；回放时会被 GameEngine 覆盖，但仍要求格式正确）
	if not data.has("index"):
		return Result.failure("Command.index 缺失")
	var index_read := _parse_int_value(data.get("index", null), "Command.index")
	if not index_read.ok:
		return index_read
	var index_val: int = int(index_read.value)
	if index_val < 0:
		return Result.failure("Command.index 不能为负数: %d" % index_val)
	cmd.index = index_val

	# action_id
	if not data.has("action_id"):
		return Result.failure("Command.action_id 缺失")
	var action_val = data.get("action_id", null)
	if not (action_val is String):
		return Result.failure("Command.action_id 类型错误（期望 String）")
	var action_id_str: String = str(action_val)
	if action_id_str.is_empty():
		return Result.failure("Command.action_id 不能为空")
	cmd.action_id = action_id_str

	# actor
	if not data.has("actor"):
		return Result.failure("Command.actor 缺失")
	var actor_read := _parse_int_value(data.get("actor", null), "Command.actor")
	if not actor_read.ok:
		return actor_read
	var actor_val: int = int(actor_read.value)
	if actor_val < -1:
		return Result.failure("Command.actor 非法: %d" % actor_val)
	cmd.actor = actor_val

	# params
	if not data.has("params"):
		return Result.failure("Command.params 缺失")
	var params_val = data.get("params", null)
	if not (params_val is Dictionary):
		return Result.failure("Command.params 类型错误（期望 Dictionary）")
	var parsed_params: Dictionary = params_val
	for k in parsed_params.keys():
		if not (k is String):
			return Result.failure("Command.params key 类型错误（期望 String）")
	cmd.params = parsed_params

	# phase
	if not data.has("phase"):
		return Result.failure("Command.phase 缺失")
	var phase_val = data.get("phase", null)
	if not (phase_val is String):
		return Result.failure("Command.phase 类型错误（期望 String）")
	var phase_str: String = str(phase_val)
	if phase_str.is_empty():
		return Result.failure("Command.phase 不能为空")
	cmd.phase = phase_str

	# sub_phase（允许为空字符串）
	if not data.has("sub_phase"):
		return Result.failure("Command.sub_phase 缺失")
	var sub_phase_val = data.get("sub_phase", null)
	if not (sub_phase_val is String):
		return Result.failure("Command.sub_phase 类型错误（期望 String）")
	cmd.sub_phase = str(sub_phase_val)

	# timestamp
	if not data.has("timestamp"):
		return Result.failure("Command.timestamp 缺失")
	var ts_read := _parse_int_value(data.get("timestamp", null), "Command.timestamp")
	if not ts_read.ok:
		return ts_read
	var ts_val: int = int(ts_read.value)
	if ts_val < 0:
		return Result.failure("Command.timestamp 不能为负数: %d" % ts_val)
	cmd.timestamp = ts_val

	# metadata（允许空字典）
	if not data.has("metadata"):
		return Result.failure("Command.metadata 缺失")
	var meta_val = data.get("metadata", null)
	if not (meta_val is Dictionary):
		return Result.failure("Command.metadata 类型错误（期望 Dictionary）")
	var meta: Dictionary = meta_val
	for k in meta.keys():
		if not (k is String):
			return Result.failure("Command.metadata key 类型错误（期望 String）")
	cmd.metadata = meta

	return Result.success(cmd)

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数），实际: %s" % [path, typeof(value)])

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
