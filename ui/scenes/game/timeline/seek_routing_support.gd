# Game timeline：seek 路由支持
# 负责：时间线 seek 可用性判断、日志 entry -> timeline 索引映射、以及 seek 路由决策。
extends RefCounted

static func is_seek_enabled(
	replay_mode_active: bool,
	history_step_timeline_active: bool,
	history_step_timeline: Dictionary,
	history_cursor_step_index: int,
	history_head_step_index: int,
	manual_replay_enabled: bool
) -> bool:
	if bool(replay_mode_active):
		return true
	if bool(history_step_timeline_active) and _has_steps(history_step_timeline):
		return int(history_cursor_step_index) < int(history_head_step_index)
	return bool(manual_replay_enabled)

static func get_entry_timeline_index(game_log_panel: Object, entry_id: int) -> int:
	if game_log_panel == null or not is_instance_valid(game_log_panel):
		return -999
	if not game_log_panel.has_method("get_entry_timeline_index"):
		return -999
	return int(game_log_panel.call("get_entry_timeline_index", int(entry_id)))

static func ensure_online_seek_allowed(
	is_online_client_mode: bool,
	replay_mode_active: bool,
	online_resume_full_history_ready: bool
) -> Result:
	if bool(is_online_client_mode) and not bool(replay_mode_active) and not bool(online_resume_full_history_ready):
		return Result.failure("联机完整历史尚未就绪，暂不支持时间线回退/复盘")
	return Result.success()

static func resolve_seek_plan(
	engine: GameEngine,
	target_index: int,
	replay_mode_active: bool,
	replay_step_timeline: Dictionary,
	history_step_timeline_active: bool,
	history_step_timeline: Dictionary
) -> Dictionary:
	if engine == null:
		return {"kind": "noop"}

	if bool(replay_mode_active) and _has_steps(replay_step_timeline):
		return {
			"kind": "replay_step",
			"target_step_index": int(target_index),
		}

	if bool(history_step_timeline_active) and _has_steps(history_step_timeline):
		return {
			"kind": "history_step",
			"target_step_index": int(target_index),
		}

	var head_index := engine.command_history.size() - 1
	var target := clampi(int(target_index), -1, head_index)
	var current := int(engine.current_command_index)

	if target == current:
		if not bool(history_step_timeline_active) and target < head_index:
			return {
				"kind": "enter_history",
				"target_command_index": target,
				"fallback_to_rewind": false,
				"update_ui_when_enter_fail": true,
			}
		return {"kind": "refresh_only"}

	if target < head_index:
		return {
			"kind": "enter_history",
			"target_command_index": target,
			"fallback_to_rewind": true,
			"update_ui_when_enter_fail": false,
		}

	return {
		"kind": "rewind_command",
		"target_command_index": target,
	}

static func _has_steps(step_timeline: Dictionary) -> bool:
	if step_timeline == null or step_timeline.is_empty():
		return false
	var steps_val = step_timeline.get("steps", null)
	return (steps_val is Array)
