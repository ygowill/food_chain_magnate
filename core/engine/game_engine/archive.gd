# GameEngine：存档序列化/文件读写（Fail Fast）
# 负责：构建 archive 字典、序列化命令/校验点，以及 JSON 文件读写。
extends RefCounted

const GameStateClass = preload("res://core/state/game_state.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")
const ONLINE_RESUME_META_KEY := "online_resume_meta"
const ONLINE_RESUME_META_VERSION := 1

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

	AutoloadAccessClass.log_info("GameEngine", "存档已保存: %s" % path)
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

	# Godot JSON.parse_string 会把所有数字解析为 float。
	# 存档/回放中大量字段（cash/库存/计数等）语义上是 int，若不归一化会导致加载后类型不匹配。
	return Result.success(_normalize_json_numbers(parsed))

static func with_online_resume_meta(archive: Dictionary, meta: Dictionary) -> Dictionary:
	var out: Dictionary = Dictionary(archive).duplicate(true)
	if meta.is_empty():
		out.erase(ONLINE_RESUME_META_KEY)
		return out
	out[ONLINE_RESUME_META_KEY] = Dictionary(meta).duplicate(true)
	return out

static func get_online_resume_meta(archive: Dictionary) -> Dictionary:
	if not (archive is Dictionary):
		return {}
	var meta_val = archive.get(ONLINE_RESUME_META_KEY, null)
	if not (meta_val is Dictionary):
		return {}
	var meta: Dictionary = Dictionary(meta_val).duplicate(true)
	meta["version"] = int(meta.get("version", ONLINE_RESUME_META_VERSION))
	return meta

static func get_online_resume_participant_slots(archive: Dictionary) -> Array[Dictionary]:
	var meta: Dictionary = get_online_resume_meta(archive)
	var slots_val = meta.get("participant_slots", null)
	if not (slots_val is Array):
		return []
	return _normalize_online_resume_participant_slots(Array(slots_val))

static func _normalize_online_resume_participant_slots(value: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in value:
		if not (item is Dictionary):
			continue
		var slot_src: Dictionary = Dictionary(item)
		var user_id := str(slot_src.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		var seat_index := _parse_optional_int(slot_src.get("seat_index", null), -1)
		if seat_index < 0:
			seat_index = _parse_optional_int(slot_src.get("player_id", null), -1)
		if seat_index < 0:
			continue
		out.append({
			"seat_index": seat_index,
			"player_id": _parse_optional_int(slot_src.get("player_id", null), seat_index),
			"user_id": user_id,
			"display_name": str(slot_src.get("display_name", "")).strip_edges(),
			"role": "host" if str(slot_src.get("role", "")).strip_edges() == "host" else "player",
			"restaurant_logo_id": _parse_optional_int(slot_src.get("restaurant_logo_id", null), -1),
			"restaurants_count": _parse_optional_int(slot_src.get("restaurants_count", null), 0),
			"cash": _parse_optional_int(slot_src.get("cash", null), 0),
			"restaurant_summary": _duplicate_array_value(slot_src.get("restaurant_summary", [])),
		})
	return out

static func _duplicate_array_value(value) -> Array:
	if value is Array:
		return Array(value).duplicate(true)
	return []

static func _parse_optional_int(value, default_value: int = -1) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return default_value

static func _normalize_json_numbers(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for k in value.keys():
				out[k] = _normalize_json_numbers(value[k])
			return out
		TYPE_ARRAY:
			var out_arr := []
			for item in value:
				out_arr.append(_normalize_json_numbers(item))
			return out_arr
		TYPE_FLOAT:
			var f: float = float(value)
			# 仅将“整值 float”转换为 int；保留真正的小数（例如 Vector2/Color 等）
			if f == floor(f) and f >= -9223372036854775808.0 and f <= 9223372036854775807.0:
				return int(f)
			return f
		_:
			return value
