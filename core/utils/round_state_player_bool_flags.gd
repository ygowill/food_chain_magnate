# RoundState：按玩家维护 bool 标记的读写工具（Fail Fast）
# 用途：统一 round_state 下“player_id -> bool”结构的读取/校验/写入，减少重复样板。
class_name RoundStatePlayerBoolFlags
extends RefCounted

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func _path_label(path: Array[String]) -> String:
	var out := "round_state"
	for seg_val in path:
		out = "%s.%s" % [out, str(seg_val)]
	return out

static func _validate_path(path: Array[String], prefix: String) -> Result:
	if path == null or path.is_empty():
		return Result.failure("%spath 不能为空" % prefix)
	for i in range(path.size()):
		var seg := str(path[i])
		if seg.is_empty():
			return Result.failure("%spath[%d] 不能为空" % [prefix, i])
	return Result.success()

static func _parse_player_id_key(key, dict_path: String, prefix: String) -> Result:
	var player_id := -1
	if key is int:
		player_id = int(key)
	elif key is String:
		var key_str := str(key)
		if not key_str.is_valid_int():
			return Result.failure("%s%s key 必须为 int 或数字字符串，实际: %s" % [prefix, dict_path, key_str])
		player_id = key_str.to_int()
	else:
		return Result.failure("%s%s key 类型错误（期望 int/数字字符串），实际: %s" % [prefix, dict_path, typeof(key)])
	if player_id < 0:
		return Result.failure("%s%s key 不能为负数: %d" % [prefix, dict_path, player_id])
	return Result.success(player_id)

static func _get_flags_dict_at_path(
	container: Dictionary,
	path: Array[String],
	prefix: String,
	allow_missing: bool,
	depth: int = 0,
	current_path: String = "round_state"
) -> Result:
	if depth >= path.size():
		return Result.failure("%s内部错误：path 越界" % prefix)
	var seg := str(path[depth])
	var next_path := "%s.%s" % [current_path, seg]
	if not container.has(seg):
		if allow_missing:
			return Result.success(null)
		return Result.failure("%s%s 缺失" % [prefix, next_path])
	var val = container.get(seg, null)
	if depth == path.size() - 1:
		if not (val is Dictionary):
			return Result.failure("%s%s 类型错误（期望 Dictionary）" % [prefix, next_path])
		return Result.success(val)
	if not (val is Dictionary):
		return Result.failure("%s%s 类型错误（期望 Dictionary）" % [prefix, next_path])
	return _get_flags_dict_at_path(val, path, prefix, allow_missing, depth + 1, next_path)

static func _set_flags_dict_at_path(
	container: Dictionary,
	path: Array[String],
	flags: Dictionary,
	prefix: String,
	depth: int = 0,
	current_path: String = "round_state"
) -> Result:
	if depth >= path.size():
		return Result.failure("%s内部错误：path 越界" % prefix)
	var seg := str(path[depth])
	var next_path := "%s.%s" % [current_path, seg]
	if depth == path.size() - 1:
		container[seg] = flags
		return Result.success(flags)
	var child: Dictionary = {}
	if container.has(seg):
		var child_val = container.get(seg, null)
		if not (child_val is Dictionary):
			return Result.failure("%s%s 类型错误（期望 Dictionary）" % [prefix, next_path])
		child = child_val
	var set_r := _set_flags_dict_at_path(child, path, flags, prefix, depth + 1, next_path)
	if not set_r.ok:
		return set_r
	container[seg] = child
	return Result.success(flags)

static func _validate_flags_dict(flags: Dictionary, dict_path: String, prefix: String) -> Result:
	for key in flags.keys():
		if key is String:
			var key_str := str(key)
			if key_str.is_valid_int():
				return Result.failure("%s%s 不应包含字符串玩家 key: %s" % [prefix, dict_path, key_str])
			return Result.failure("%s%s key 类型错误（期望 int），实际: %s" % [prefix, dict_path, key_str])
		if not (key is int):
			return Result.failure("%s%s key 类型错误（期望 int），实际: %s" % [prefix, dict_path, typeof(key)])
		var player_id := int(key)
		if player_id < 0:
			return Result.failure("%s%s key 不能为负数: %d" % [prefix, dict_path, player_id])
		var flag_val = flags.get(key, null)
		if not (flag_val is bool):
			return Result.failure("%s%s[%d] 类型错误（期望 bool）" % [prefix, dict_path, player_id])
	return Result.success(flags)

static func get_player_flag(
	round_state: Dictionary,
	path: Array[String],
	player_id: int,
	prefix_label: String,
	default_value: bool = false
) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if player_id < 0:
		return Result.failure("%splayer_id 不能为负数: %d" % [prefix, player_id])
	var path_r := _validate_path(path, prefix)
	if not path_r.ok:
		return path_r
	var dict_path := _path_label(path)
	var flags_read := _get_flags_dict_at_path(round_state, path, prefix, true)
	if not flags_read.ok:
		return flags_read
	if flags_read.value == null:
		return Result.success(default_value)
	var flags: Dictionary = flags_read.value
	var validate_r := _validate_flags_dict(flags, dict_path, prefix)
	if not validate_r.ok:
		return validate_r
	if not flags.has(player_id):
		return Result.success(default_value)
	return Result.success(bool(flags.get(player_id, default_value)))

static func set_player_flag(
	round_state: Dictionary,
	path: Array[String],
	player_id: int,
	value: bool,
	prefix_label: String
) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if player_id < 0:
		return Result.failure("%splayer_id 不能为负数: %d" % [prefix, player_id])
	var path_r := _validate_path(path, prefix)
	if not path_r.ok:
		return path_r
	var dict_path := _path_label(path)
	var flags_read := _get_flags_dict_at_path(round_state, path, prefix, true)
	if not flags_read.ok:
		return flags_read
	var flags: Dictionary = {}
	if flags_read.value != null:
		flags = flags_read.value
		var validate_r := _validate_flags_dict(flags, dict_path, prefix)
		if not validate_r.ok:
			return validate_r
	flags[player_id] = value
	var set_r := _set_flags_dict_at_path(round_state, path, flags, prefix)
	if not set_r.ok:
		return set_r
	return Result.success(value)

static func normalize_player_flags(
	round_state: Dictionary,
	path: Array[String],
	player_count: int,
	prefix_label: String,
	default_value: bool = false
) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if player_count < 0:
		return Result.failure("%splayer_count 不能为负数: %d" % [prefix, player_count])
	var path_r := _validate_path(path, prefix)
	if not path_r.ok:
		return path_r
	var dict_path := _path_label(path)
	var flags_read := _get_flags_dict_at_path(round_state, path, prefix, true)
	if not flags_read.ok:
		return flags_read
	var raw: Dictionary = {}
	if flags_read.value != null:
		raw = flags_read.value
	var normalized := {}
	for pid in range(player_count):
		normalized[pid] = default_value
	for key in raw.keys():
		var pid_read := _parse_player_id_key(key, dict_path, prefix)
		if not pid_read.ok:
			return pid_read
		var pid: int = int(pid_read.value)
		var flag_val = raw.get(key, null)
		if not (flag_val is bool):
			return Result.failure("%s%s[%s] 类型错误（期望 bool）" % [prefix, dict_path, str(key)])
		if pid >= player_count:
			continue
		normalized[pid] = bool(flag_val)
	var set_r := _set_flags_dict_at_path(round_state, path, normalized, prefix)
	if not set_r.ok:
		return set_r
	return Result.success(normalized)

static func list_true_players(
	round_state: Dictionary,
	path: Array[String],
	player_count: int,
	prefix_label: String
) -> Result:
	var prefix := _prefix(prefix_label)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if player_count < 0:
		return Result.failure("%splayer_count 不能为负数: %d" % [prefix, player_count])
	var path_r := _validate_path(path, prefix)
	if not path_r.ok:
		return path_r
	var dict_path := _path_label(path)
	var flags_read := _get_flags_dict_at_path(round_state, path, prefix, true)
	if not flags_read.ok:
		return flags_read
	if flags_read.value == null:
		return Result.success([])
	var flags: Dictionary = flags_read.value
	var validate_r := _validate_flags_dict(flags, dict_path, prefix)
	if not validate_r.ok:
		return validate_r
	var out: Array[int] = []
	for pid in range(player_count):
		if bool(flags.get(pid, false)):
			out.append(pid)
	return Result.success(out)
