# 联机恢复房完整历史适配层
# 目标：统一从恢复房历史缓存读取 timeline/log；在单 full-engine 模式下，history engine 可直接等于 runtime_engine。
class_name OnlineResumeFullHistoryAdapter
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
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
