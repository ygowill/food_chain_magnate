# Game timeline：历史 step 时间线支持
# 负责：进入历史 step 时间线、命令到 step 的映射、以及 step seek。
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const GameTimelineStepSeekHelpersClass = preload("res://ui/scenes/game/timeline/step_seek_helpers.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")

static func has_steps(history_step_timeline: Dictionary) -> bool:
	if history_step_timeline == null or history_step_timeline.is_empty():
		return false
	var steps_val = history_step_timeline.get("steps", null)
	return (steps_val is Array)

static func enter_for_command(
	engine: GameEngine,
	game_log_panel: Object,
	target_command_index: int
) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")

	var build_r: Result = StepTimelineBuildHelpersClass.build_and_load(engine, game_log_panel, false)
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("构建 step 时间线失败（返回类型错误）")

	var info: Dictionary = Dictionary(build_r.value)
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("构建 step 时间线失败（返回结构错误）")

	var timeline: Dictionary = Dictionary(timeline_val).duplicate(true)
	var head_step_index := int(info.get("head_step_index", -1))
	var cursor_step_index := head_step_index

	if game_log_panel.has_method("set_timeline_head"):
		game_log_panel.call("set_timeline_head", head_step_index)
	if game_log_panel.has_method("set_timeline_cursor"):
		game_log_panel.call("set_timeline_cursor", cursor_step_index)

	return Result.success({
		"timeline": timeline,
		"head_step_index": head_step_index,
		"cursor_step_index": cursor_step_index,
		"target_step_index": map_command_index_to_step_index(timeline, int(target_command_index)),
	})

static func map_command_index_to_step_index(history_step_timeline: Dictionary, command_index: int) -> int:
	if not has_steps(history_step_timeline):
		return -999

	var steps: Array = history_step_timeline.get("steps", [])
	var cmd := int(command_index)
	if cmd < 0:
		return -1

	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		if str(step.get("kind", "")).strip_edges() != "command":
			continue
		if int(step.get("anchor_command_index", -999)) == cmd:
			return idx
	return -999

static func resolve_seek_engine(runtime_engine: GameEngine, use_online_full_history: bool) -> GameEngine:
	if use_online_full_history:
		return OnlineResumeFullHistoryAdapterClass.get_history_engine()
	return runtime_engine

static func seek_to_step(
	history_step_timeline: Dictionary,
	engine: GameEngine,
	current_cursor_step_index: int,
	target_step_index: int,
	use_online_full_history: bool
) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	if not has_steps(history_step_timeline):
		return Result.failure("history_step_timeline 缺少 steps")

	var steps: Array = history_step_timeline.get("steps", [])
	var head_step_index := steps.size() - 1
	var target := clampi(int(target_step_index), -1, head_step_index)

	if target == int(current_cursor_step_index):
		return Result.success({
			"head_step_index": head_step_index,
			"cursor_step_index": target,
			"restore_runtime_display_engine": use_online_full_history and target >= head_step_index,
			"set_display_history_engine": false,
			"force_full_panel_sync": false,
		})

	if use_online_full_history and target >= head_step_index:
		return Result.success({
			"head_step_index": head_step_index,
			"cursor_step_index": head_step_index,
			"restore_runtime_display_engine": true,
			"set_display_history_engine": false,
			"force_full_panel_sync": true,
		})

	var restore_r: Result = GameTimelineStepSeekHelpersClass.restore_state_from_step_timeline(
		history_step_timeline,
		steps,
		target
	)
	if not restore_r.ok:
		return Result.failure(str(restore_r.error))
	if not (restore_r.value is Dictionary):
		return Result.failure("内部错误（返回类型错误）")

	var info: Dictionary = Dictionary(restore_r.value)
	var restored: GameState = info.get("state", null)
	if restored == null:
		return Result.failure("恢复 state 为空")

	engine.state = restored
	engine.current_command_index = int(info.get("anchor_command_index", -1))

	return Result.success({
		"head_step_index": head_step_index,
		"cursor_step_index": target,
		"restore_runtime_display_engine": false,
		"set_display_history_engine": use_online_full_history,
		"force_full_panel_sync": true,
	})
