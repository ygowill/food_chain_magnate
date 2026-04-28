# GameEngine 存档恢复辅助
# 负责：导入旧联机存档时补齐在线确认 marker；联机恢复可额外截断到最后可回放前缀。
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"
const ACTION_CONFIRM_DINNERTIME := "confirm_dinnertime"
const ACTION_CONFIRM_MARKETING := "confirm_marketing"

class _SilentEventSink:
	extends RefCounted

	func emit_event(_event_type: String, _data: Dictionary) -> void:
		pass

	func clear_history_and_reset_sequence() -> void:
		pass

	func clear_history() -> void:
		pass

	func record_event(_event_type: String, _data: Dictionary) -> void:
		pass

static func load_for_online_resume(archive: Dictionary, allow_prefix_recovery: bool = true) -> Result:
	if archive.is_empty():
		return Result.failure("resume archive missing")

	var original_archive := Dictionary(archive).duplicate(true)
	var repair_info := _repair_online_confirm_markers_for_replay(original_archive)
	var load_archive: Dictionary = Dictionary(repair_info.get("archive", original_archive)).duplicate(true)
	var repair_warnings: Array[String] = Array(repair_info.get("warnings", []), TYPE_STRING, "", null)
	var repaired_markers: Array[String] = Array(repair_info.get("repaired_markers", []), TYPE_STRING, "", null)
	var full_engine = _new_engine()
	var full_load: Result = full_engine.load_from_archive(load_archive.duplicate(true))
	if full_load.ok:
		var out_archive := load_archive
		var archive_warnings: Array[String] = []
		if not repaired_markers.is_empty():
			var archive_r := _create_recovered_archive(full_engine, load_archive)
			if not archive_r.ok:
				return archive_r.with_warnings(full_load.warnings).with_warnings(repair_warnings)
			out_archive = Dictionary(archive_r.value).duplicate(true)
			archive_warnings.append_array(archive_r.warnings)
		return Result.success({
			"archive": out_archive,
			"engine": full_engine,
			"truncated": false,
			"original_command_count": _get_command_count(original_archive),
			"recovered_command_count": _get_command_count(original_archive),
			"failed_command_index": -1,
			"original_error": "",
			"repaired_online_confirm_markers": repaired_markers.duplicate(),
		}).with_warnings(repair_warnings).with_warnings(full_load.warnings).with_warnings(archive_warnings)

	if not allow_prefix_recovery:
		return Result.failure(str(full_load.error)).with_warnings(repair_warnings).with_warnings(full_load.warnings)

	var commands_val = load_archive.get("commands", null)
	if not (commands_val is Array):
		return Result.failure(str(full_load.error)).with_warnings(repair_warnings).with_warnings(full_load.warnings)

	var original_commands: Array = Array(commands_val)
	var failed_index := extract_replay_failure_index(str(full_load.error))
	var start_count := original_commands.size()
	if failed_index >= 0:
		start_count = mini(start_count, failed_index)

	for command_count in range(start_count, -1, -1):
		var candidate := _build_prefix_archive(load_archive, command_count)
		var engine = _new_engine()
		var load_r: Result = engine.load_from_archive(candidate)
		if not load_r.ok:
			continue
		var recovered_archive_r := _create_recovered_archive(engine, original_archive)
		if not recovered_archive_r.ok:
			return recovered_archive_r.with_warnings(load_r.warnings)
		var recovered_archive: Dictionary = Dictionary(recovered_archive_r.value).duplicate(true)
		var warning := _build_recovery_warning(original_commands.size(), command_count, failed_index, str(full_load.error))
		return Result.success({
			"archive": recovered_archive,
			"engine": engine,
			"truncated": command_count < original_commands.size(),
			"original_command_count": original_commands.size(),
			"recovered_command_count": command_count,
			"failed_command_index": failed_index,
			"original_error": str(full_load.error),
			"repaired_online_confirm_markers": repaired_markers.duplicate(),
		}).with_warnings(repair_warnings).with_warnings(full_load.warnings).with_warnings(load_r.warnings).with_warnings(recovered_archive_r.warnings).with_warning(warning)

	return Result.failure("存档无法截断到任何可回放点：%s" % full_load.error).with_warnings(repair_warnings).with_warnings(full_load.warnings)

static func load_file_for_replay_import(path: String) -> Result:
	var archive_result := ArchiveClass.load_archive_from_file(path)
	if not archive_result.ok:
		return archive_result
	var archive: Dictionary = Dictionary(archive_result.value).duplicate(true)
	return load_for_replay_import(archive)

static func load_for_replay_import(archive: Dictionary) -> Result:
	if archive.is_empty():
		return Result.failure("replay archive missing")

	var original_archive := Dictionary(archive).duplicate(true)
	var repair_info := _repair_online_confirm_markers_for_replay(original_archive)
	var load_archive: Dictionary = Dictionary(repair_info.get("archive", original_archive)).duplicate(true)
	var repair_warnings: Array[String] = Array(repair_info.get("warnings", []), TYPE_STRING, "", null)
	var repaired_markers: Array[String] = Array(repair_info.get("repaired_markers", []), TYPE_STRING, "", null)
	var engine = _new_engine()
	var load_r: Result = engine.load_from_archive(load_archive.duplicate(true))
	if not load_r.ok:
		return Result.failure(str(load_r.error)).with_warnings(repair_warnings).with_warnings(load_r.warnings)

	var out_archive := load_archive
	var archive_warnings: Array[String] = []
	if not repaired_markers.is_empty():
		var archive_r := _create_recovered_archive(engine, load_archive)
		if not archive_r.ok:
			return archive_r.with_warnings(load_r.warnings).with_warnings(repair_warnings)
		out_archive = Dictionary(archive_r.value).duplicate(true)
		archive_warnings.append_array(archive_r.warnings)

	return Result.success({
		"archive": out_archive,
		"engine": engine,
		"truncated": false,
		"original_command_count": _get_command_count(original_archive),
		"recovered_command_count": _get_command_count(original_archive),
		"failed_command_index": -1,
		"original_error": "",
		"repaired_online_confirm_markers": repaired_markers.duplicate(),
	}).with_warnings(repair_warnings).with_warnings(load_r.warnings).with_warnings(archive_warnings)

static func _repair_online_confirm_markers_for_replay(archive: Dictionary) -> Dictionary:
	var out := Dictionary(archive).duplicate(true)
	var commands_val = out.get("commands", null)
	if not (commands_val is Array):
		return {
			"archive": out,
			"warnings": [],
			"repaired_markers": [],
		}

	var needs_dinnertime := false
	var needs_marketing := false
	for cmd_val in Array(commands_val):
		if not (cmd_val is Dictionary):
			continue
		var cmd: Dictionary = cmd_val
		if int(cmd.get("actor", -1)) < 0:
			continue
		var action_id := str(cmd.get("action_id", "")).strip_edges()
		if action_id == ACTION_CONFIRM_DINNERTIME:
			needs_dinnertime = true
		elif action_id == ACTION_CONFIRM_MARKETING:
			needs_marketing = true

	if not needs_dinnertime and not needs_marketing:
		return {
			"archive": out,
			"warnings": [],
			"repaired_markers": [],
		}

	var initial_val = out.get("initial_state", null)
	if not (initial_val is Dictionary):
		return {
			"archive": out,
			"warnings": [],
			"repaired_markers": [],
		}
	var initial: Dictionary = Dictionary(initial_val).duplicate(true)
	var rules: Dictionary = Dictionary(initial.get("rules", {})).duplicate(true) if initial.get("rules", null) is Dictionary else {}
	var repaired: Array[String] = []
	if needs_dinnertime and int(rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, 0)) != 1:
		rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
		repaired.append(ONLINE_DINNERTIME_CONFIRM_KEY)
	if needs_marketing and int(rules.get(ONLINE_MARKETING_CONFIRM_KEY, 0)) != 1:
		rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
		repaired.append(ONLINE_MARKETING_CONFIRM_KEY)
	if repaired.is_empty():
		return {
			"archive": out,
			"warnings": [],
			"repaired_markers": [],
		}

	initial["rules"] = rules
	out["initial_state"] = initial
	var warnings: Array[String] = []
	warnings.append("存档包含玩家级在线确认命令，已补齐缺失的回放规则标记: %s" % ", ".join(repaired))
	return {
		"archive": out,
		"warnings": warnings,
		"repaired_markers": repaired,
	}

static func extract_replay_failure_index(error: String) -> int:
	var marker := "回放命令 #"
	var pos := error.find(marker)
	if pos < 0:
		return -1
	var start := pos + marker.length()
	var finish := start
	while finish < error.length():
		var ch := error.substr(finish, 1)
		if "0123456789".find(ch) < 0:
			break
		finish += 1
	if finish <= start:
		return -1
	return int(error.substr(start, finish - start))

static func _new_engine():
	var engine = GameEngineClass.new()
	if engine.has_method("set_event_sink"):
		engine.set_event_sink(_SilentEventSink.new())
	return engine

static func _get_command_count(archive: Dictionary) -> int:
	var commands_val = archive.get("commands", null)
	if commands_val is Array:
		return Array(commands_val).size()
	return 0

static func _build_prefix_archive(archive: Dictionary, command_count: int) -> Dictionary:
	var out := Dictionary(archive).duplicate(true)
	var source_commands: Array = Array(archive.get("commands", [])) if archive.get("commands", null) is Array else []
	var commands_out: Array = []
	var max_keep := clampi(command_count, 0, source_commands.size())
	for i in range(max_keep):
		commands_out.append(source_commands[i])
	out["commands"] = commands_out

	var desired_index := _parse_archive_current_index(archive, max_keep - 1)
	out["current_index"] = clampi(desired_index, -1, max_keep - 1)
	out["checkpoints"] = _build_prefix_checkpoint_metadata(archive, max_keep)
	return out

static func _parse_archive_current_index(archive: Dictionary, fallback_value: int) -> int:
	var value = archive.get("current_index", fallback_value)
	if value is int:
		return int(value)
	if value is float:
		var f := float(value)
		if f == floor(f):
			return int(f)
	return fallback_value

static func _build_prefix_checkpoint_metadata(archive: Dictionary, kept_command_count: int) -> Array:
	var out: Array = []
	var checkpoints_val = archive.get("checkpoints", null)
	if checkpoints_val is Array:
		for checkpoint_val in Array(checkpoints_val):
			if not (checkpoint_val is Dictionary):
				continue
			var checkpoint: Dictionary = Dictionary(checkpoint_val).duplicate(true)
			var checkpoint_index := int(checkpoint.get("index", -1))
			if checkpoint_index < 0 or checkpoint_index > kept_command_count:
				continue
			out.append(checkpoint)
	if not out.is_empty():
		return out
	return [{
		"index": 0,
		"hash": "",
		"rng_calls": 0,
	}]

static func _create_recovered_archive(engine, original_archive: Dictionary) -> Result:
	if engine == null or not engine.has_method("create_archive"):
		return Result.failure("恢复存档失败：engine 无效")
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("恢复存档失败：create_archive failed: %s" % archive_r.error)
	var recovered: Dictionary = Dictionary(archive_r.value).duplicate(true)
	if original_archive.has(ArchiveClass.ONLINE_RESUME_META_KEY):
		var meta_val = original_archive.get(ArchiveClass.ONLINE_RESUME_META_KEY, null)
		if meta_val is Dictionary:
			recovered[ArchiveClass.ONLINE_RESUME_META_KEY] = Dictionary(meta_val).duplicate(true)
	return Result.success(recovered).with_warnings(archive_r.warnings)

static func _build_recovery_warning(original_count: int, recovered_count: int, failed_index: int, original_error: String) -> String:
	var failed_text := "未知"
	if failed_index >= 0:
		failed_text = str(failed_index)
	return "存档尾部回放失败，已截断到最后可回放点（命令数 %d/%d，失败命令 #%s）：%s" % [
		recovered_count,
		original_count,
		failed_text,
		original_error,
	]
