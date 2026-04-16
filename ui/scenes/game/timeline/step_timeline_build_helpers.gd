# GameTimelineController：step_timeline 构建辅助（从 game_timeline_controller.gd 抽取）
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/timeline/log_entries_builder.gd")

static func build_step_timeline(
	engine: GameEngine,
	previous_timeline: Dictionary = {},
	allow_incremental_append: bool = false
) -> Result:
	if engine == null or not is_instance_valid(engine):
		return Result.failure("engine 为空")

	if bool(allow_incremental_append) and previous_timeline is Dictionary and not previous_timeline.is_empty():
		var append_r: Result = StepTimelineBuildClass.append_from_existing(engine, previous_timeline)
		if append_r.ok and append_r.value is Dictionary:
			var append_info: Dictionary = Dictionary(append_r.value)
			if bool(append_info.get("append_applied", false)):
				var append_timeline: Dictionary = Dictionary(append_info.get("timeline", {})).duplicate(true)
				var appended_events_val = append_info.get("appended_events", [])
				var appended_events: Array = appended_events_val if (appended_events_val is Array) else []
				var appended_entries := GameTimelineLogEntriesBuilderClass.build(appended_events)

				var append_steps_val = append_timeline.get("steps", [])
				var append_steps: Array = append_steps_val if (append_steps_val is Array) else []

				return Result.success({
					"timeline": append_timeline,
					"entries": appended_entries,
					"appended_entries": appended_entries,
					"append_applied": true,
					"steps": append_steps,
					"head_step_index": append_steps.size() - 1,
				}).with_warnings(append_r.warnings)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure(str(build_r.error))

	if not (build_r.value is Dictionary):
		return Result.failure("返回类型错误")

	var timeline: Dictionary = Dictionary(build_r.value).duplicate(true)
	var info_r := build_info_from_timeline(timeline)
	if not info_r.ok:
		return info_r
	return Result.success(Dictionary(info_r.value).duplicate(true)).with_warnings(build_r.warnings)

static func build_info_from_timeline(timeline: Dictionary) -> Result:
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		return Result.failure("timeline 为空")

	var normalized_timeline: Dictionary = Dictionary(timeline).duplicate(true)
	var events_val = timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)

	var steps_val = timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []

	return Result.success({
		"timeline": normalized_timeline,
		"entries": entries,
		"appended_entries": [],
		"append_applied": false,
		"steps": steps,
		"head_step_index": steps.size() - 1,
	})

static func build_and_load(
	engine: GameEngine,
	game_log_panel: Object,
	read_only: bool,
	previous_timeline: Dictionary = {},
	allow_incremental_append: bool = false
) -> Result:
	var build_r := build_step_timeline(engine, previous_timeline, allow_incremental_append)
	if not build_r.ok:
		return build_r
	return load_timeline_info(Dictionary(build_r.value), game_log_panel, read_only).with_warnings(build_r.warnings)

static func load_prebuilt_timeline(
	timeline: Dictionary,
	game_log_panel: Object,
	read_only: bool
) -> Result:
	var info_r := build_info_from_timeline(timeline)
	if not info_r.ok:
		return info_r
	return load_timeline_info(Dictionary(info_r.value), game_log_panel, read_only).with_warnings(info_r.warnings)

static func load_timeline_info(
	info: Dictionary,
	game_log_panel: Object,
	read_only: bool
) -> Result:
	if info == null or not (info is Dictionary):
		return Result.failure("返回类型错误")
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("返回结构错误")

	var entries_val = info.get("entries", [])
	var entries: Array = entries_val if (entries_val is Array) else []
	var appended_entries_val = info.get("appended_entries", [])
	var appended_entries: Array[Dictionary] = []
	if appended_entries_val is Array:
		for entry_val in appended_entries_val:
			if entry_val is Dictionary:
				appended_entries.append(Dictionary(entry_val).duplicate(true))

	if game_log_panel != null and is_instance_valid(game_log_panel):
		if bool(info.get("append_applied", false)):
			var append_loaded := false
			if game_log_panel.has_method("append_step_timeline"):
				append_loaded = bool(
					game_log_panel.call(
						"append_step_timeline",
						Dictionary(timeline_val),
						appended_entries,
						bool(read_only)
					)
				)
			if not append_loaded and game_log_panel.has_method("load_step_timeline"):
				var combined_entries := _combine_entries_for_append(game_log_panel, appended_entries)
				game_log_panel.call("load_step_timeline", Dictionary(timeline_val), combined_entries, bool(read_only))
			elif not append_loaded:
				game_log_panel.call("load_entries", appended_entries)
		elif game_log_panel.has_method("load_step_timeline"):
			game_log_panel.call("load_step_timeline", Dictionary(timeline_val), entries, bool(read_only))
		else:
			game_log_panel.call("load_entries", entries)
	return Result.success(info.duplicate(true))

static func _combine_entries_for_append(game_log_panel: Object, appended_entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if game_log_panel != null and is_instance_valid(game_log_panel) and game_log_panel.has_method("get_step_timeline_entries"):
		var existing_val = game_log_panel.call("get_step_timeline_entries")
		if existing_val is Array:
			for entry_val in existing_val:
				if entry_val is Dictionary:
					out.append(Dictionary(entry_val).duplicate(true))
	for appended in appended_entries:
		if appended is Dictionary:
			out.append(Dictionary(appended).duplicate(true))
	return out
