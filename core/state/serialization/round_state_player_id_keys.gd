extends RefCounted

static func parse_player_id_key(key, container_path: String) -> Result:
	if not (key is String) or not str(key).is_valid_int():
		return Result.failure("%s key 必须为数字字符串，实际: %s" % [container_path, str(key)])
	var pid: int = str(key).to_int()
	if pid < 0:
		return Result.failure("%s key 不能为负数: %d" % [container_path, pid])
	return Result.success(pid)

