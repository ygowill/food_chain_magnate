# GameEngine：存档序列化/文件读写（Fail Fast）
# 负责：构建 archive 字典、序列化命令/校验点，以及 JSON 文件读写。
extends RefCounted

const GameStateClass = preload("res://core/state/game_state.gd")

static func create_archive(
	state: GameState,
	random_manager: RandomManager,
	checkpoints: Array[Dictionary],
	command_history: Array[Command],
	current_command_index: int,
	modules_v2_base_dir: String
) -> Result:
	if state == null:
		return Result.failure("无法创建存档：GameState 未初始化")
	if random_manager == null:
		return Result.failure("无法创建存档：RandomManager 未初始化")
	if checkpoints.is_empty():
		return Result.failure("无法创建存档：缺少初始 checkpoint")

	var rng_dict: Dictionary = random_manager.to_dict()
	if rng_dict.is_empty():
		return Result.failure("无法创建存档：rng 不能为空")
	if modules_v2_base_dir.is_empty():
		return Result.failure("无法创建存档：modules_v2_base_dir 不能为空")

	return Result.success({
		"schema_version": GameStateClass.SCHEMA_VERSION,
		"game_version": _get_game_version(),
		"created_at": Time.get_datetime_string_from_system(),
		"modules_v2_base_dir": modules_v2_base_dir,
		"rng": rng_dict,
		"initial_state": checkpoints[0].state_dict,
		"commands": serialize_commands(command_history),
		"checkpoints": _require_checkpoint_metadata(checkpoints),
		"current_index": current_command_index,
		"final_hash": state.compute_hash()
	})

static func _get_game_version() -> String:
	var v = ProjectSettings.get_setting("application/config/version", "")
	var s := str(v).strip_edges()
	if s.is_empty():
		return "0.0.0"
	return s

static func serialize_commands(command_history: Array[Command]) -> Array:
	var out: Array = []
	for cmd in command_history:
		out.append(cmd.to_dict())
	return out

static func serialize_checkpoint_metadata(checkpoints: Array[Dictionary]) -> Array:
	var out: Array = []
	for checkpoint in checkpoints:
		out.append({
			"index": checkpoint.index,
			"hash": checkpoint.hash,
			"rng_calls": checkpoint.rng_calls
		})
	return out

static func _require_checkpoint_metadata(checkpoints: Array[Dictionary]) -> Array:
	# 这里不做兼容：checkpoint 必须包含 rng_calls，否则说明内部实现错误，需要立刻修复。
	for i in range(checkpoints.size()):
		var checkpoint_val = checkpoints[i]
		assert(checkpoint_val is Dictionary, "Archive.create_archive: checkpoint[%d] 类型错误（期望 Dictionary）" % i)
		var checkpoint: Dictionary = checkpoint_val
		assert(checkpoint.has("rng_calls"), "Archive.create_archive: checkpoint[%d] 缺少字段: rng_calls" % i)
		assert(checkpoint["rng_calls"] is int, "Archive.create_archive: checkpoint[%d].rng_calls 类型错误（期望 int）" % i)

	return serialize_checkpoint_metadata(checkpoints)

static func save_archive_to_file(archive: Dictionary, path: String) -> Result:
	if path.is_empty():
		return Result.failure("path 不能为空")
	var json := JSON.stringify(archive, "\t")

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Result.failure("无法打开文件: %s" % path)
	file.store_string(json)
	file.close()

	GameLog.info("GameEngine", "存档已保存: %s" % path)
	return Result.success(path)

static func load_archive_from_file(path: String) -> Result:
	if path.is_empty():
		return Result.failure("path 不能为空")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开文件: %s" % path)

	var json := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("无法解析存档文件")

	return Result.success(parsed)
