# Game timeline：回放会话支持
# 负责：回放文件装载、进入前日志快照捕获、以及退出后的日志恢复。
extends RefCounted

const ArchiveRecoveryClass = preload("res://core/engine/game_engine/archive_recovery.gd")

static func capture_original_log_entries(game_log_panel: Object, replay_mode_active: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bool(replay_mode_active):
		return out
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return out
	if not game_log_panel.has_method("get_entries"):
		return out

	var entries_val = game_log_panel.call("get_entries")
	if not (entries_val is Array):
		return out

	for entry_val in entries_val:
		if entry_val is Dictionary:
			out.append(Dictionary(entry_val).duplicate(true))
	return out

static func load_engine_from_file(file_path: String) -> Result:
	var load_result := load_replay_import_from_file(file_path)
	if not load_result.ok:
		return load_result
	var info: Dictionary = Dictionary(load_result.value) if load_result.value is Dictionary else {}
	var engine_val = info.get("engine", null)
	if not (engine_val is GameEngine):
		return Result.failure("回放载入失败：engine 类型错误")
	return Result.success(engine_val).with_warnings(load_result.warnings)

static func load_replay_import_from_file(file_path: String) -> Result:
	if str(file_path).is_empty():
		return Result.failure("file_path 为空")
	var load_result: Result = ArchiveRecoveryClass.load_file_for_replay_import(file_path)
	if not load_result.ok:
		return Result.failure(str(load_result.error))
	return load_result

static func move_engine_to_latest_state(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("回放载入后进入可操作模式失败：engine 为空")
	var head_index := engine.command_history.size() - 1
	if int(engine.current_command_index) == head_index:
		return Result.success()
	var rewind_r := engine.rewind_to_command(head_index)
	if not rewind_r.ok:
		return Result.failure("回放载入后进入可操作模式失败：无法定位到最新状态: %s" % rewind_r.error)
	return Result.success()

static func restore_original_log_entries(game_log_panel: Object, replay_original_log_entries: Array[Dictionary]) -> void:
	if replay_original_log_entries.is_empty():
		return
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("load_entries"):
		return
	game_log_panel.call("load_entries", replay_original_log_entries.duplicate(true))

static func sync_log_panel_cursor_from_engine(game_log_panel: Object, engine: GameEngine) -> void:
	if engine == null:
		return
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return
	if game_log_panel.has_method("set_timeline_head"):
		game_log_panel.call("set_timeline_head", engine.command_history.size() - 1)
	if game_log_panel.has_method("set_timeline_cursor"):
		game_log_panel.call("set_timeline_cursor", int(engine.current_command_index))
