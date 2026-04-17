# 联机恢复房完整历史适配层
# 目标：保持 runtime_engine 作为 live active engine，同时允许 timeline/log 读取 full_replay_engine。
class_name OnlineResumeFullHistoryAdapter
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/timeline/log_entries_builder.gd")
const GameLogEntryUtilsClass = preload("res://ui/components/game_log/game_log_entry_utils.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

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

static func get_cached_history_timeline() -> Dictionary:
	if NetClient == null or not NetClient.has_method("get_online_resume_full_replay_step_timeline"):
		return {}
	var timeline_val = NetClient.get_online_resume_full_replay_step_timeline()
	return Dictionary(timeline_val).duplicate(false) if (timeline_val is Dictionary) else {}

static func set_cached_history_timeline(timeline: Dictionary) -> void:
	if NetClient == null or not NetClient.has_method("set_online_resume_full_replay_step_timeline"):
		return
	NetClient.set_online_resume_full_replay_step_timeline(Dictionary(timeline).duplicate(false))

static func get_cached_history_timeline_entries() -> Array[Dictionary]:
	if NetClient == null or not NetClient.has_method("get_online_resume_full_replay_step_timeline_entries"):
		return []
	var entries_val = NetClient.get_online_resume_full_replay_step_timeline_entries()
	var out: Array[Dictionary] = []
	if entries_val is Array:
		for entry_val in entries_val:
			if not (entry_val is Dictionary):
				continue
			out.append(Dictionary(entry_val).duplicate(false))
	return out

static func set_cached_history_timeline_entries(entries: Array) -> void:
	if NetClient == null or not NetClient.has_method("set_online_resume_full_replay_step_timeline_entries"):
		return
	NetClient.set_online_resume_full_replay_step_timeline_entries(entries)

static func build_history_timeline(
	game_log_panel: Object,
	read_only: bool,
	previous_timeline: Dictionary = {},
	allow_incremental_append: bool = false
) -> Result:
	var cached_history_timeline: Dictionary = {}
	if NetClient != null and NetClient.has_method("ensure_online_resume_full_history_timeline_current"):
		var ensure_timeline_r = NetClient.ensure_online_resume_full_history_timeline_current(bool(allow_incremental_append))
		if ensure_timeline_r is Result:
			if not ensure_timeline_r.ok:
				return ensure_timeline_r
			if ensure_timeline_r.value is Dictionary:
				cached_history_timeline = Dictionary(ensure_timeline_r.value).duplicate(true)
	elif NetClient != null and NetClient.has_method("ensure_online_resume_full_history_current"):
		var ensure_r = NetClient.ensure_online_resume_full_history_current()
		if ensure_r is Result and not ensure_r.ok:
			return ensure_r
	var engine := get_history_engine()
	if engine == null:
		return Result.failure("full_replay_engine 未就绪")

	var current_count := int(engine.command_history.size())
	if cached_history_timeline.is_empty():
		cached_history_timeline = get_cached_history_timeline()
	var baseline_choice := select_preferred_baseline_timeline(
		previous_timeline,
		cached_history_timeline,
		current_count,
		allow_incremental_append
	)
	var baseline_timeline: Dictionary = Dictionary(baseline_choice.get("timeline", {})).duplicate(true)
	_emit_resume_cache_event("resume_cache.baseline_timeline.selected", {
		"source": str(baseline_choice.get("source", "none")),
		"allow_incremental_append": bool(allow_incremental_append),
		"current_command_count": int(current_count),
		"previous_processed_command_count": int(baseline_choice.get("previous_processed_command_count", -1)),
		"cached_processed_command_count": int(baseline_choice.get("cached_processed_command_count", -1)),
		"selected_processed_command_count": int(baseline_choice.get("selected_processed_command_count", -1)),
	})

	if not baseline_timeline.is_empty():
		var cached_processed_count := StepTimelineHelpersClass.read_processed_command_count(baseline_timeline)
		var snapshot := get_session_snapshot()
		var cached_entry_count := int(snapshot.get("full_replay_step_timeline_entry_count", -1))
		var cached_entries_processed_count := int(
			snapshot.get("full_replay_step_timeline_entries_processed_command_count", -1)
		)
		var can_use_cached_entries := bool(snapshot.get("full_replay_step_timeline_entries_ready", false)) \
			and cached_entries_processed_count == cached_processed_count
		if cached_processed_count >= current_count:
			_emit_resume_cache_event("resume_cache.used_prebuilt_timeline", {
				"cached_processed_command_count": int(cached_processed_count),
				"current_command_count": int(current_count),
				"allow_incremental_append": bool(allow_incremental_append),
				"timeline_step_count": int(Array(baseline_timeline.get("steps", [])).size()),
				"cached_entry_count": int(cached_entry_count),
				"cached_entries_processed_command_count": int(cached_entries_processed_count),
				"used_cached_entries": bool(can_use_cached_entries),
			})
		var build_r: Result
		if cached_processed_count >= current_count:
			if can_use_cached_entries:
				var cached_history_entries := get_cached_history_timeline_entries()
				build_r = StepTimelineBuildHelpersClass.load_prebuilt_timeline_with_entries(
					baseline_timeline,
					cached_history_entries,
					game_log_panel,
					read_only
				)
			else:
				build_r = StepTimelineBuildHelpersClass.load_prebuilt_timeline(
					baseline_timeline,
					game_log_panel,
					read_only
				)
		else:
			build_r = StepTimelineBuildHelpersClass.build_and_load(
				engine,
				game_log_panel,
				read_only,
				baseline_timeline,
				true
			)
		if build_r.ok and build_r.value is Dictionary:
			var info: Dictionary = Dictionary(build_r.value)
			var next_timeline_val = info.get("timeline", null)
			if next_timeline_val is Dictionary:
				set_cached_history_timeline(Dictionary(next_timeline_val))
			if not bool(info.get("append_applied", false)):
				var entries_val = info.get("entries", [])
				if entries_val is Array:
					set_cached_history_timeline_entries(entries_val)
		return build_r

	_emit_resume_cache_event("resume_cache.miss_prebuilt_timeline", {
		"current_command_count": int(engine.command_history.size()),
		"allow_incremental_append": bool(allow_incremental_append),
		"previous_timeline_present": bool(previous_timeline is Dictionary and not previous_timeline.is_empty()),
		"cached_timeline_present": bool(not cached_history_timeline.is_empty()),
	})
	var build_r := StepTimelineBuildHelpersClass.build_and_load(
		engine,
		game_log_panel,
		read_only,
		{},
		false
	)
	if build_r.ok and build_r.value is Dictionary:
		var info: Dictionary = Dictionary(build_r.value)
		var timeline_val = info.get("timeline", null)
		if timeline_val is Dictionary:
			set_cached_history_timeline(Dictionary(timeline_val))
	return build_r

static func build_live_history_timeline_from_cached_baseline(
	runtime_engine: GameEngine,
	game_log_panel: Object,
	read_only: bool = false
) -> Result:
	if runtime_engine == null:
		return Result.failure("runtime_engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")
	if not is_ready():
		return Result.failure("联机完整历史尚未就绪")

	var cached_history_timeline := get_cached_history_timeline()
	if cached_history_timeline.is_empty():
		return Result.failure("cached full-history timeline 未就绪")

	var cached_history_entries := get_cached_history_timeline_entries()
	if cached_history_entries.is_empty():
		var cached_events_val = cached_history_timeline.get("events", [])
		var cached_events: Array = cached_events_val if (cached_events_val is Array) else []
		cached_history_entries = GameTimelineLogEntriesBuilderClass.build(cached_events)

	var snapshot := get_session_snapshot()
	var runtime_anchor: Dictionary = Dictionary(snapshot.get("runtime_anchor", {})).duplicate(true)
	var global_command_start_index := int(runtime_anchor.get("global_command_start_index", 0))
	if global_command_start_index < 0:
		global_command_start_index = 0

	var replace_step_start_index := _find_first_step_index_at_or_after_command(
		cached_history_timeline,
		global_command_start_index
	)

	var runtime_info_r := StepTimelineBuildHelpersClass.build_step_timeline(runtime_engine, {}, false)
	if not runtime_info_r.ok:
		return runtime_info_r
	if not (runtime_info_r.value is Dictionary):
		return Result.failure("runtime timeline 构建失败（返回类型错误）")

	var runtime_info: Dictionary = Dictionary(runtime_info_r.value)
	var runtime_timeline_val = runtime_info.get("timeline", null)
	if not (runtime_timeline_val is Dictionary):
		return Result.failure("runtime timeline 构建失败（返回结构错误）")
	var runtime_timeline: Dictionary = Dictionary(runtime_timeline_val).duplicate(true)

	var rebased_runtime_timeline := _rebase_runtime_timeline_for_live_view(
		runtime_timeline,
		global_command_start_index,
		replace_step_start_index
	)
	var merged_timeline := _merge_cached_prefix_with_runtime_timeline(
		cached_history_timeline,
		rebased_runtime_timeline,
		global_command_start_index,
		replace_step_start_index
	)
	var merged_entries := _merge_cached_prefix_with_runtime_entries(
		cached_history_entries,
		rebased_runtime_timeline,
		global_command_start_index
	)

	var load_r := StepTimelineBuildHelpersClass.load_prebuilt_timeline_with_entries(
		merged_timeline,
		merged_entries,
		game_log_panel,
		read_only
	)
	if not load_r.ok:
		return load_r
	if not (load_r.value is Dictionary):
		return Result.failure("加载 live baseline timeline 失败（返回类型错误）")

	var load_info: Dictionary = Dictionary(load_r.value)
	var merged_steps_val = merged_timeline.get("steps", [])
	var merged_steps: Array = merged_steps_val if (merged_steps_val is Array) else []
	var head_step_index := int(merged_steps.size()) - 1
	var head_command_index := int(runtime_engine.command_history.size()) - 1
	var cursor_command_index := int(runtime_engine.current_command_index)
	var cursor_step_index := head_step_index
	if cursor_command_index < 0:
		cursor_step_index = -1
	elif cursor_command_index >= head_command_index:
		cursor_step_index = head_step_index
	else:
		cursor_step_index = map_runtime_command_index_to_step_index(cursor_command_index, merged_timeline)
		if cursor_step_index < -1:
			cursor_step_index = head_step_index

	load_info["timeline"] = merged_timeline.duplicate(true)
	load_info["entries"] = _duplicate_entry_array(merged_entries)
	load_info["head_step_index"] = head_step_index
	load_info["cursor_step_index"] = cursor_step_index
	load_info["history_timeline_source"] = "runtime"
	load_info["restore_runtime_display_engine"] = false
	load_info["uses_global_timeline"] = true
	return Result.success(load_info).with_warnings(load_r.warnings)

static func select_preferred_baseline_timeline(
	previous_timeline: Dictionary,
	cached_timeline: Dictionary,
	current_command_count: int,
	allow_incremental_append: bool
) -> Dictionary:
	var previous_normalized := previous_timeline.duplicate(true) if (previous_timeline is Dictionary) else {}
	var cached_normalized := cached_timeline.duplicate(true) if (cached_timeline is Dictionary) else {}

	var previous_processed_count := -1
	if not previous_normalized.is_empty():
		previous_processed_count = int(StepTimelineHelpersClass.read_processed_command_count(previous_normalized))
	var cached_processed_count := -1
	if not cached_normalized.is_empty():
		cached_processed_count = int(StepTimelineHelpersClass.read_processed_command_count(cached_normalized))

	var selected_timeline: Dictionary = {}
	var source := "none"
	if bool(allow_incremental_append):
		if not cached_normalized.is_empty() and (previous_normalized.is_empty() or cached_processed_count > previous_processed_count):
			selected_timeline = cached_normalized
			source = "cached"
		elif not previous_normalized.is_empty():
			selected_timeline = previous_normalized
			source = "previous"
		elif not cached_normalized.is_empty():
			selected_timeline = cached_normalized
			source = "cached"
	elif not cached_normalized.is_empty() and (previous_normalized.is_empty() or cached_processed_count >= previous_processed_count):
		selected_timeline = cached_normalized
		source = "cached"
	elif not previous_normalized.is_empty():
		selected_timeline = previous_normalized
		source = "previous"

	var selected_processed_count := -1
	if not selected_timeline.is_empty():
		selected_processed_count = int(StepTimelineHelpersClass.read_processed_command_count(selected_timeline))

	return {
		"timeline": selected_timeline,
		"source": source,
		"current_command_count": int(current_command_count),
		"previous_processed_command_count": int(previous_processed_count),
		"cached_processed_command_count": int(cached_processed_count),
		"selected_processed_command_count": int(selected_processed_count),
	}

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

static func _find_first_step_index_at_or_after_command(timeline: Dictionary, command_index: int) -> int:
	if timeline.is_empty():
		return 0
	var steps_val = timeline.get("steps", null)
	if not (steps_val is Array):
		return 0
	var steps: Array = steps_val
	var target := maxi(0, int(command_index))
	for idx in range(steps.size()):
		var step_val = steps[idx]
		if not (step_val is Dictionary):
			continue
		if int(Dictionary(step_val).get("anchor_command_index", -999999)) >= target:
			return idx
	return steps.size()

static func _rebase_runtime_timeline_for_live_view(
	runtime_timeline: Dictionary,
	command_offset: int,
	step_offset: int
) -> Dictionary:
	var out: Dictionary = runtime_timeline.duplicate(true)
	var rebased_steps: Array[Dictionary] = []
	var steps_val = runtime_timeline.get("steps", [])
	if steps_val is Array:
		for step_val in steps_val:
			if not (step_val is Dictionary):
				continue
			var step: Dictionary = Dictionary(step_val).duplicate(true)
			var anchor_command_index := int(step.get("anchor_command_index", -1))
			if anchor_command_index >= 0:
				step["anchor_command_index"] = anchor_command_index + int(command_offset)
			rebased_steps.append(step)
	out["steps"] = rebased_steps

	var rebased_events: Array[Dictionary] = []
	var next_sequence := 0
	var events_val = runtime_timeline.get("events", [])
	if events_val is Array:
		for event_val in events_val:
			if not (event_val is Dictionary):
				continue
			var event_data: Dictionary = Dictionary(event_val).duplicate(true)
			var command_index := int(event_data.get("command_index", -1))
			if command_index >= 0:
				event_data["command_index"] = command_index + int(command_offset)
			var step_index := int(event_data.get("step_index", -1))
			if step_index >= 0:
				event_data["step_index"] = step_index + int(step_offset)
			var command_step_index := int(event_data.get("command_step_index", -1))
			if command_step_index >= 0:
				event_data["command_step_index"] = command_step_index + int(step_offset)
			event_data["sequence"] = next_sequence
			rebased_events.append(event_data)
			next_sequence += 1
	out["events"] = rebased_events
	return out

static func _merge_cached_prefix_with_runtime_timeline(
	cached_history_timeline: Dictionary,
	rebased_runtime_timeline: Dictionary,
	global_command_start_index: int,
	replace_step_start_index: int
) -> Dictionary:
	var merged_timeline: Dictionary = {
		"initial_state_dict": Dictionary(cached_history_timeline.get("initial_state_dict", {})).duplicate(true),
	}

	var merged_steps: Array[Dictionary] = []
	var cached_steps_val = cached_history_timeline.get("steps", [])
	if cached_steps_val is Array:
		var cached_steps: Array = cached_steps_val
		var prefix_end := mini(maxi(0, int(replace_step_start_index)), cached_steps.size())
		for idx in range(prefix_end):
			var step_val = cached_steps[idx]
			if not (step_val is Dictionary):
				continue
			merged_steps.append(Dictionary(step_val).duplicate(true))
	var runtime_steps_val = rebased_runtime_timeline.get("steps", [])
	if runtime_steps_val is Array:
		for step_val in runtime_steps_val:
			if not (step_val is Dictionary):
				continue
			merged_steps.append(Dictionary(step_val).duplicate(true))
	merged_timeline["steps"] = merged_steps

	var merged_events: Array[Dictionary] = []
	var cached_events_val = cached_history_timeline.get("events", [])
	if cached_events_val is Array:
		for event_val in cached_events_val:
			if not (event_val is Dictionary):
				continue
			var event_data: Dictionary = Dictionary(event_val)
			if int(event_data.get("command_index", -1)) >= int(global_command_start_index):
				continue
			merged_events.append(event_data.duplicate(true))
	var next_sequence := 0
	if not merged_events.is_empty():
		next_sequence = int(Dictionary(merged_events.back()).get("sequence", -1)) + 1
	var runtime_events_val = rebased_runtime_timeline.get("events", [])
	if runtime_events_val is Array:
		for event_val in runtime_events_val:
			if not (event_val is Dictionary):
				continue
			var event_data: Dictionary = Dictionary(event_val).duplicate(true)
			if int(event_data.get("command_index", -1)) < int(global_command_start_index):
				continue
			event_data["sequence"] = next_sequence
			merged_events.append(event_data)
			next_sequence += 1
	merged_timeline["events"] = merged_events

	var processed_command_count := maxi(
		_read_processed_command_count_from_events(merged_events),
		_read_processed_command_count_from_steps(merged_steps)
	)
	var last_event_sequence := 0
	if not merged_events.is_empty():
		last_event_sequence = int(Dictionary(merged_events.back()).get("sequence", 0))
	return StepTimelineHelpersClass.attach_build_meta(
		merged_timeline,
		processed_command_count,
		last_event_sequence
	)

static func _merge_cached_prefix_with_runtime_entries(
	cached_history_entries: Array[Dictionary],
	rebased_runtime_timeline: Dictionary,
	global_command_start_index: int
) -> Array[Dictionary]:
	var merged_entries: Array[Dictionary] = []
	for entry in cached_history_entries:
		if not (entry is Dictionary):
			continue
		if int(GameLogEntryUtilsClass.get_entry_command_index(entry)) >= int(global_command_start_index):
			continue
		merged_entries.append(Dictionary(entry).duplicate(true))

	var runtime_events_val = rebased_runtime_timeline.get("events", [])
	var runtime_events: Array = runtime_events_val if (runtime_events_val is Array) else []
	for entry in GameTimelineLogEntriesBuilderClass.build(runtime_events):
		if not (entry is Dictionary):
			continue
		if int(GameLogEntryUtilsClass.get_entry_command_index(entry)) < int(global_command_start_index):
			continue
		merged_entries.append(Dictionary(entry).duplicate(true))
	return merged_entries

static func _read_processed_command_count_from_events(events: Array[Dictionary]) -> int:
	var max_command_index := -1
	for event_val in events:
		if not (event_val is Dictionary):
			continue
		max_command_index = maxi(max_command_index, int(Dictionary(event_val).get("command_index", -1)))
	return max_command_index + 1 if max_command_index >= 0 else 0

static func _read_processed_command_count_from_steps(steps: Array[Dictionary]) -> int:
	var max_command_index := -1
	for step_val in steps:
		if not (step_val is Dictionary):
			continue
		max_command_index = maxi(max_command_index, int(Dictionary(step_val).get("anchor_command_index", -1)))
	return max_command_index + 1 if max_command_index >= 0 else 0

static func _duplicate_entry_array(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (entries is Array):
		return out
	for entry_val in entries:
		if not (entry_val is Dictionary):
			continue
		out.append(Dictionary(entry_val).duplicate(true))
	return out

static func _emit_resume_cache_event(event: String, fields: Dictionary = {}) -> void:
	if not OnlinePerfTraceClass.enabled():
		return
	var snapshot := get_session_snapshot()
	var out: Dictionary = {
		"room_code": str(snapshot.get("runtime_room_code", "")).strip_edges().to_upper(),
		"full_replay_ready": bool(snapshot.get("full_replay_ready", false)),
		"cached_timeline_ready": bool(snapshot.get("full_replay_step_timeline_ready", false)),
		"full_replay_command_count": int(snapshot.get("full_replay_command_count", -1)),
	}
	for key in fields.keys():
		out[str(key)] = fields[key]
	OnlinePerfTraceClass.emit_event(str(event).strip_edges(), out)
