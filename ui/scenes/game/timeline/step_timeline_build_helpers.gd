# GameTimelineController：step_timeline 构建辅助（从 game_timeline_controller.gd 抽取）
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/timeline/log_entries_builder.gd")

static func build_step_timeline(engine: GameEngine) -> Result:
	if engine == null or not is_instance_valid(engine):
		return Result.failure("engine 为空")

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure(str(build_r.error))

	if not (build_r.value is Dictionary):
		return Result.failure("返回类型错误")

	var timeline: Dictionary = Dictionary(build_r.value).duplicate(true)
	var events_val = timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)

	var steps_val = timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []

	return Result.success({
		"timeline": timeline,
		"entries": entries,
		"steps": steps,
		"head_step_index": steps.size() - 1,
	})

static func build_and_load(engine: GameEngine, game_log_panel: Object, read_only: bool) -> Result:
	var build_r := build_step_timeline(engine)
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("返回类型错误")
	var info: Dictionary = build_r.value
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("返回结构错误")

	var entries_val = info.get("entries", [])
	var entries: Array = entries_val if (entries_val is Array) else []

	if game_log_panel != null and is_instance_valid(game_log_panel):
		if game_log_panel.has_method("load_step_timeline"):
			game_log_panel.call("load_step_timeline", Dictionary(timeline_val), entries, bool(read_only))
		else:
			game_log_panel.call("load_entries", entries)
	return build_r
