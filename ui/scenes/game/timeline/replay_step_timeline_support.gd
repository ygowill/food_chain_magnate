# Game timeline：回放 step 时间线支持
# 负责：加载回放 step 时间线，以及回放模式下的 step seek。
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const GameTimelineStepSeekHelpersClass = preload("res://ui/scenes/game/timeline/step_seek_helpers.gd")

static func load_for_engine(engine: GameEngine, game_log_panel: Object) -> Result:
	if engine == null or not is_instance_valid(engine):
		return Result.failure("engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")

	var build_r: Result = StepTimelineBuildHelpersClass.build_and_load(engine, game_log_panel, true)
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
	})

static func seek_to_step(
	replay_step_timeline: Dictionary,
	engine: GameEngine,
	current_cursor_step_index: int,
	target_step_index: int
) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	if replay_step_timeline == null or replay_step_timeline.is_empty():
		return Result.failure("replay_step_timeline 为空")

	var steps_val = replay_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return Result.failure("replay_step_timeline 缺少 steps")
	var steps: Array = steps_val

	var head_step_index := steps.size() - 1
	var target := clampi(int(target_step_index), -1, head_step_index)
	if target == int(current_cursor_step_index):
		return Result.success({
			"head_step_index": head_step_index,
			"cursor_step_index": target,
			"force_full_panel_sync": false,
		})

	var restore_r: Result = GameTimelineStepSeekHelpersClass.restore_state_from_step_timeline(
		replay_step_timeline,
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
		"force_full_panel_sync": true,
	})
