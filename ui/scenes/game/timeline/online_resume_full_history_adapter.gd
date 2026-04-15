# 联机恢复房完整历史适配层
# 目标：保持 runtime_engine 作为 live active engine，同时允许 timeline/log 读取 full_replay_engine。
class_name OnlineResumeFullHistoryAdapter
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")

static func is_applicable() -> bool:
	if NetContext == null:
		return false
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	return str(NetContext.room_state.get("room_mode", "")).strip_edges() == "resume_archive"

static func is_ready() -> bool:
	if not is_applicable():
		return false
	if NetClient == null or not NetClient.has_method("get_online_resume_session_snapshot"):
		return false
	var snapshot: Dictionary = Dictionary(NetClient.get_online_resume_session_snapshot()).duplicate(true)
	return bool(snapshot.get("full_replay_ready", false))

static func get_session_snapshot() -> Dictionary:
	if NetClient == null or not NetClient.has_method("get_online_resume_session_snapshot"):
		return {}
	return Dictionary(NetClient.get_online_resume_session_snapshot()).duplicate(true)

static func get_runtime_engine() -> GameEngine:
	if Globals == null:
		return null
	var engine = Globals.current_game_engine
	if engine is GameEngine:
		return engine
	return null

static func get_history_engine() -> GameEngine:
	if NetClient == null or not NetClient.has_method("get_online_resume_full_replay_engine"):
		return null
	var engine = NetClient.get_online_resume_full_replay_engine()
	if engine is GameEngine:
		return engine
	return null

static func build_history_timeline(game_log_panel: Object, read_only: bool) -> Result:
	var engine := get_history_engine()
	if engine == null:
		return Result.failure("full_replay_engine 未就绪")
	return StepTimelineBuildHelpersClass.build_and_load(engine, game_log_panel, read_only)

static func map_runtime_command_index_to_global(runtime_command_index: int) -> int:
	var snapshot := get_session_snapshot()
	var anchor: Dictionary = Dictionary(snapshot.get("runtime_anchor", {})).duplicate(true)
	var global_start := int(anchor.get("global_command_start_index", -1))
	var local_index := int(runtime_command_index)
	if global_start < 0:
		return local_index
	if local_index < 0:
		return global_start - 1
	return global_start + local_index

static func map_global_command_index_to_step_index(global_command_index: int, timeline: Dictionary) -> int:
	var cmd := int(global_command_index)
	if cmd < 0:
		return -1
	if timeline.is_empty():
		return -1
	var steps_val = timeline.get("steps", null)
	if not (steps_val is Array):
		return -1
	var steps: Array = steps_val
	for idx in range(steps.size() - 1, -1, -1):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		if int(Dictionary(step_val).get("anchor_command_index", -999999)) == cmd:
			return idx
	return -1

static func map_runtime_command_index_to_step_index(runtime_command_index: int, timeline: Dictionary) -> int:
	return map_global_command_index_to_step_index(
		map_runtime_command_index_to_global(runtime_command_index),
		timeline
	)
