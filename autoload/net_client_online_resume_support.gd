# NetClient：联机恢复房完整历史缓存支持
# 目标：把恢复房 full-history timeline / entries cache 与兼容态收口到独立模块。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumeSessionStateClass = preload("res://autoload/online_resume_session_state.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/timeline/log_entries_builder.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

class _LocalEventSink:
	extends RefCounted

	var _history: Array[Dictionary] = []
	var _sequence: int = 0

	func clear_history_and_reset_sequence() -> void:
		_history.clear()
		_sequence = 0

	func clear_history() -> void:
		_history.clear()

	func emit_event(event_type: String, data: Dictionary) -> void:
		record_event(event_type, data)

	func record_event(event_type: String, data: Dictionary = {}) -> void:
		_sequence += 1
		_history.append({
			"type": str(event_type),
			"data": Dictionary(data).duplicate(true),
			"sequence": _sequence,
			"timestamp": _sequence,
		})

	func get_history(count: int = -1) -> Array[Dictionary]:
		if count < 0 or count >= _history.size():
			return _history.duplicate(true)
		var out: Array[Dictionary] = []
		var start := _history.size() - count
		for i in range(start, _history.size()):
			out.append(Dictionary(_history[i]).duplicate(true))
		return out

var _net = null
var _session_state = OnlineResumeSessionStateClass.new()

var _load_archive_for_online_client: Callable = Callable()
var _mark_online_client_engine_ready: Callable = Callable()
var _sync_online_resume_progress: Callable = Callable()
var _get_online_client_engine_room_code: Callable = Callable()
var _safe_text: Callable = Callable()
var _short_hash: Callable = Callable()
var _net_has_signal: Callable = Callable()

func setup(net_client, callbacks: Dictionary = {}) -> void:
	_net = net_client
	_load_archive_for_online_client = callbacks.get("load_archive_for_online_client", Callable())
	_mark_online_client_engine_ready = callbacks.get("mark_online_client_engine_ready", Callable())
	_sync_online_resume_progress = callbacks.get("sync_online_resume_progress", Callable())
	_get_online_client_engine_room_code = callbacks.get("get_online_client_engine_room_code", Callable())
	_safe_text = callbacks.get("safe_text", Callable())
	_short_hash = callbacks.get("short_hash", Callable())
	_net_has_signal = callbacks.get("net_has_signal", Callable())

func get_session_state():
	return _session_state

func snapshot() -> Dictionary:
	return _session_state.snapshot()

func get_full_replay_engine():
	return _session_state.full_replay_engine

func ensure_full_replay_engine_current() -> Result:
	if bool(_session_state.single_full_engine_mode):
		var runtime_engine: GameEngine = _session_state.runtime_engine
		if runtime_engine == null or runtime_engine.get_state() == null:
			return Result.failure("single_full_engine runtime 未就绪")
		_session_state.full_replay_engine = runtime_engine
		_session_state.full_replay_engine_ready = true
		return Result.success(runtime_engine)
	var full_engine: GameEngine = _session_state.full_replay_engine
	var generation := int(_session_state.full_history_generation)
	var room_code := str(_session_state.full_replay_room_code).strip_edges().to_upper()
	if room_code.is_empty():
		room_code = str(_session_state.runtime_room_code).strip_edges().to_upper()

	if not _session_state.full_replay_engine_ready or full_engine == null or full_engine.get_state() == null:
		if _session_state.full_history_source_mode != "archive_payload" or _session_state.full_archive.is_empty():
			return Result.failure("full_replay_engine 未就绪")
		var build_r := _build_full_replay_engine_for_generation(room_code, generation, false, true)
		if not build_r.ok:
			return build_r
		full_engine = _session_state.full_replay_engine
		if full_engine == null or full_engine.get_state() == null:
			return Result.failure("full_replay_engine 构建后仍未就绪")

	var tail_r := _replay_pending_full_replay_live_tail(full_engine, generation)
	if not tail_r.ok:
		return tail_r
	return Result.success(full_engine)

func ensure_full_replay_step_timeline_current(allow_incremental_append: bool = true) -> Result:
	var ensure_r := ensure_full_replay_engine_current()
	if not ensure_r.ok:
		return ensure_r
	var full_engine: GameEngine = _session_state.full_replay_engine
	if bool(_session_state.single_full_engine_mode):
		full_engine = _session_state.runtime_engine
	if full_engine == null or full_engine.get_state() == null:
		return Result.failure("full_replay_engine 未就绪")
	var cached_timeline := _session_state.get_full_replay_step_timeline()
	var cached_processed := StepTimelineHelpersClass.read_processed_command_count(cached_timeline)
	var command_count := int(full_engine.command_history.size())
	if cached_timeline.is_empty() or cached_processed < command_count:
		var cache_r := _refresh_full_replay_step_timeline_cache(full_engine, bool(allow_incremental_append))
		if not cache_r.ok:
			return cache_r
	return Result.success(_session_state.get_full_replay_step_timeline())

func get_full_replay_step_timeline() -> Dictionary:
	return _session_state.get_full_replay_step_timeline()

func set_full_replay_step_timeline(timeline: Dictionary) -> void:
	_session_state.set_full_replay_step_timeline(timeline)

func get_full_replay_step_timeline_entries() -> Array[Dictionary]:
	return _session_state.get_full_replay_step_timeline_entries()

func set_full_replay_step_timeline_entries(entries: Array) -> void:
	var processed_count := StepTimelineHelpersClass.read_processed_command_count(
		_session_state.get_full_replay_step_timeline()
	)
	_session_state.set_full_replay_step_timeline_entries(entries, processed_count)

func clear_online_resume_dual_engine_state() -> void:
	_session_state.reset()

func mark_runtime_engine_as_full_history(engine) -> void:
	if engine == null:
		return
	var room_code := ""
	if _get_online_client_engine_room_code.is_valid():
		room_code = str(_get_online_client_engine_room_code.call())
	var local_pid := int(NetContext.local_player_id) if NetContext != null else -1
	if _is_resume_archive_runtime_context(room_code):
		var prepare_r := prepare_single_full_engine_runtime(engine, room_code, local_pid, {}, true)
		if not prepare_r.ok:
			GameLog.warn("NetClient", "single full-engine runtime refresh failed: %s" % prepare_r.error)
		return
	if engine is GameEngine:
		_session_state.bind_runtime(engine, room_code, local_pid)
	_session_state.runtime_anchor = {
		"global_command_start_index": 0,
		"global_command_end_index": int(engine.current_command_index) if engine is Object else -1,
	}

func prepare_single_full_engine_runtime(
	engine: GameEngine,
	room_code: String,
	local_pid: int,
	archive_meta: Dictionary = {},
	build_timeline_cache: bool = true
) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("single_full_engine runtime 未就绪")
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	var span := OnlinePerfTraceClass.begin_span("client.resume_single_full.prepare", {
		"room_code": normalized_room_code,
		"build_timeline_cache": bool(build_timeline_cache),
		"command_count": int(engine.command_history.size()),
	})
	_session_state.bind_runtime(engine, normalized_room_code, int(local_pid))
	_session_state.runtime_anchor = {
		"global_command_start_index": 0,
		"global_command_end_index": int(engine.current_command_index),
	}
	_session_state.full_replay_engine = engine
	_session_state.full_replay_engine_ready = true
	_session_state.full_replay_room_code = normalized_room_code
	_session_state.full_archive = {}
	_session_state.full_archive_meta = Dictionary(archive_meta).duplicate(true)
	_session_state.full_history_source_mode = "single_full_engine"
	_session_state.single_full_engine_mode = true
	_session_state.last_full_history_error = ""
	_session_state.full_replay_live_tail_commands.clear()
	_session_state.full_replay_live_tail_applied_count = 0
	if not bool(build_timeline_cache):
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"timeline_cached": bool(_session_state.has_full_replay_step_timeline()),
			"single_full_engine_mode": true,
		})
		return Result.success(_session_state.snapshot())
	_session_state.set_full_replay_step_timeline({})
	var cache_r := _refresh_full_replay_step_timeline_cache(engine, false)
	if not cache_r.ok:
		_session_state.last_full_history_error = str(cache_r.error)
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"error": str(cache_r.error),
			"single_full_engine_mode": true,
		})
		return cache_r
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"timeline_cached": bool(_session_state.has_full_replay_step_timeline()),
		"timeline_entry_count": int(_session_state.full_replay_step_timeline_entries.size()),
		"single_full_engine_mode": true,
	})
	return Result.success(_session_state.snapshot())

func map_online_resume_progress_from_engine(engine, checkpoint_id: String = "") -> Dictionary:
	if engine == null or _session_state.runtime_engine == null:
		return {}
	if engine != _session_state.runtime_engine:
		return {}
	var state = engine.get_state() if engine.has_method("get_state") else null
	if state == null or not state.has_method("compute_hash"):
		return {}
	var current_index_val = engine.get("current_command_index") if engine is Object else null
	if not (current_index_val is int or current_index_val is float):
		return {}
	var local_sequence := maxi(0, int(current_index_val) + 1)
	var base_global_start := int(_session_state.runtime_anchor.get("global_command_start_index", -1))
	if base_global_start < 0:
		return {}
	var out := {
		"last_applied_sequence": base_global_start + local_sequence,
		"last_state_hash": str(state.compute_hash()),
	}
	var normalized_checkpoint_id := str(checkpoint_id).strip_edges()
	if not normalized_checkpoint_id.is_empty():
		out["checkpoint_id"] = normalized_checkpoint_id
	return out

func _build_full_replay_engine_for_generation(
	room_code: String,
	generation: int,
	build_timeline_cache: bool,
	emit_ready_signal: bool
) -> Result:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	var archive: Dictionary = Dictionary(_session_state.full_archive).duplicate(true)
	if archive.is_empty():
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "archive_empty",
		})
		_maybe_emit_match_bootstrap_local_failed("完整历史构建失败：恢复存档为空", normalized_room_code)
		return Result.failure("archive_empty")
	if not _load_archive_for_online_client.is_valid():
		_session_state.mark_full_history_error("load_archive_for_online_client 未绑定", generation)
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "load_archive_callback_missing",
		})
		_maybe_emit_match_bootstrap_local_failed("完整历史构建失败：本地载入回调缺失", normalized_room_code)
		return Result.failure("load_archive_for_online_client 未绑定")

	var engine = GameEngineClass.new()
	engine.set_event_sink(_LocalEventSink.new())
	var load_r = _load_archive_for_online_client.call(engine, archive)
	if not (load_r is Result):
		_session_state.mark_full_history_error("load_archive_for_online_client 返回类型错误", generation)
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "load_archive_callback_bad_return",
		})
		_maybe_emit_match_bootstrap_local_failed("完整历史构建失败：本地载入回调返回类型错误", normalized_room_code)
		return Result.failure("load_archive_for_online_client 返回类型错误")
	if not load_r.ok:
		_session_state.mark_full_history_error("load_from_archive failed: %s" % load_r.error, generation)
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "load_archive_failed",
			"error": str(load_r.error),
		})
		GameLog.error("NetClient", "Online resume full_replay_engine load failed: %s" % load_r.error)
		_maybe_emit_match_bootstrap_local_failed(
			"完整历史构建失败：载入恢复存档失败：%s" % str(load_r.error),
			normalized_room_code
		)
		return Result.failure(str(load_r.error))

	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		_session_state.mark_full_history_error("prepare_engine_for_online_resume failed: %s" % prepare_r.error, generation)
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "prepare_resume_point_failed",
			"error": str(prepare_r.error),
		})
		GameLog.error("NetClient", "Online resume full_replay_engine prepare failed: %s" % prepare_r.error)
		_maybe_emit_match_bootstrap_local_failed(
			"完整历史构建失败：恢复点校验失败：%s" % str(prepare_r.error),
			normalized_room_code
		)
		return Result.failure(str(prepare_r.error))

	var replay_tail_r: Result = replay_full_replay_live_tail(engine, generation)
	if not replay_tail_r.ok:
		_session_state.mark_full_history_error("replay_full_replay_live_tail failed: %s" % replay_tail_r.error, generation)
		_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
			"room_code": normalized_room_code,
			"generation": generation,
			"reason": "replay_live_tail_failed",
			"error": str(replay_tail_r.error),
		})
		GameLog.error("NetClient", "Online resume full_replay_engine tail replay failed: %s" % replay_tail_r.error)
		_maybe_emit_match_bootstrap_local_failed(
			"完整历史构建失败：补放实时尾部命令失败：%s" % str(replay_tail_r.error),
			normalized_room_code
		)
		return Result.failure(str(replay_tail_r.error))

	if bool(build_timeline_cache):
		var timeline_cache_r: Result = _refresh_full_replay_step_timeline_cache(engine, false)
		if not timeline_cache_r.ok:
			_session_state.set_full_replay_step_timeline({})
			_emit_resume_cache_event("resume_cache.startup_full_build.failed", {
				"room_code": normalized_room_code,
				"generation": generation,
				"reason": "timeline_cache_build_failed",
				"error": str(timeline_cache_r.error),
				"full_replay_command_count": int(engine.command_history.size()),
			})
			GameLog.warn(
				"NetClient",
				"Online resume full_replay step timeline cache build failed room=%s err=%s"
					% [_safe_text_value(normalized_room_code), _safe_text_value(timeline_cache_r.error)]
			)
			if _should_abort_match_bootstrap_on_full_history_failure(normalized_room_code):
				_session_state.mark_full_history_error("timeline cache build failed: %s" % timeline_cache_r.error, generation)
				_maybe_emit_match_bootstrap_local_failed(
					"完整历史构建失败：日志时间线缓存构建失败：%s" % str(timeline_cache_r.error),
					normalized_room_code
				)
				return Result.failure(str(timeline_cache_r.error))
		else:
			_session_state.mark_full_replay_live_tail_applied(_session_state.full_replay_live_tail_commands.size())

	if not _session_state.mark_full_replay_engine_ready(engine, generation):
		return Result.failure("generation changed")

	_emit_resume_cache_event("resume_cache.startup_full_build.done", {
		"room_code": normalized_room_code,
		"generation": generation,
		"full_replay_command_count": int(engine.command_history.size()),
		"timeline_cached": bool(_session_state.has_full_replay_step_timeline()),
		"timeline_step_count": int(Array(_session_state.full_replay_step_timeline.get("steps", [])).size()),
		"timeline_processed_command_count": int(
			_session_state.full_replay_step_timeline.get("_build_meta", {}).get("processed_command_count", -1)
		),
		"live_tail_count": int(_session_state.full_replay_live_tail_commands.size()),
		"live_tail_applied_count": int(_session_state.full_replay_live_tail_applied_count),
	})
	GameLog.info(
		"NetClient",
		"Online resume full_replay_engine ready room=%s commands=%d timeline_cached=%s"
			% [
				_safe_text_value(normalized_room_code),
				int(engine.command_history.size()),
				str(_session_state.has_full_replay_step_timeline())
			]
	)
	if bool(emit_ready_signal) and _net != null and is_instance_valid(_net) and _net_has_signal_value("resume_full_history_ready"):
		_net.emit_signal("resume_full_history_ready", _session_state.snapshot())
	return Result.success(engine)

func invalidate_full_replay_engine(reason: String) -> void:
	if not _session_state.full_replay_engine_ready \
		and _session_state.full_archive.is_empty() \
		and _session_state.last_full_history_error.is_empty():
		return
	var room_code = _session_state.runtime_room_code
	_session_state.clear_full_history()
	GameLog.warn(
		"NetClient",
		"Online resume full_replay_engine invalidated room=%s reason=%s"
			% [_safe_text_value(room_code), _safe_text_value(str(reason))]
	)

func record_online_resume_full_history_entries(entries: Array, origin: String) -> void:
	for item_val in entries:
		if not (item_val is Dictionary):
			continue
		var entry: Dictionary = Dictionary(item_val)
		var cmd_val = entry.get("cmd", null)
		if not (cmd_val is Dictionary):
			continue
		record_online_resume_full_history_command(
			Dictionary(cmd_val).duplicate(true),
			str(entry.get("post_state_hash", "")).strip_edges(),
			origin
		)

func record_online_resume_full_history_command(cmd_dict: Dictionary, state_hash: String, origin: String) -> void:
	if cmd_dict.is_empty():
		return
	if bool(_session_state.single_full_engine_mode):
		_emit_resume_cache_event("resume_cache.live_tail.skipped_single_full_engine", {
			"origin": str(origin),
			"command_index": int(cmd_dict.get("index", -1)),
		})
		return
	if _session_state.full_history_source_mode != "archive_payload" and _session_state.full_archive.is_empty():
		return
	_session_state.append_full_replay_live_tail_command(cmd_dict, state_hash)
	_emit_resume_cache_event("resume_cache.live_tail.recorded", {
		"origin": str(origin),
		"full_replay_live_tail_count": int(_session_state.full_replay_live_tail_commands.size()),
		"full_replay_live_tail_applied_count": int(_session_state.full_replay_live_tail_applied_count),
		"full_replay_live_tail_pending_count": maxi(
			0,
			int(_session_state.full_replay_live_tail_commands.size()) - int(_session_state.full_replay_live_tail_applied_count)
		),
	})

func _refresh_full_replay_step_timeline_cache(engine: GameEngine, allow_incremental_append: bool = false) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("full_replay_engine 未就绪")

	var previous_timeline := _session_state.get_full_replay_step_timeline()
	var previous_processed_count := StepTimelineHelpersClass.read_processed_command_count(previous_timeline)
	_emit_resume_cache_event("resume_cache.timeline_cache_refresh.start", {
		"allow_incremental_append": bool(allow_incremental_append),
		"previous_timeline_ready": bool(not previous_timeline.is_empty()),
		"previous_processed_command_count": int(previous_processed_count),
		"full_replay_command_count": int(engine.command_history.size()),
	})
	if bool(allow_incremental_append) and not previous_timeline.is_empty():
		var append_r: Result = StepTimelineBuildClass.append_from_existing(engine, previous_timeline)
		if append_r.ok and append_r.value is Dictionary:
			var append_info: Dictionary = Dictionary(append_r.value)
			var append_timeline_val = append_info.get("timeline", null)
			if append_timeline_val is Dictionary:
				var append_timeline: Dictionary = Dictionary(append_timeline_val).duplicate(false)
				var next_entries: Array[Dictionary] = []
				var append_applied := bool(append_info.get("append_applied", false))
				var cached_entries_ready := _session_state.has_full_replay_step_timeline_entries()
				var previous_entries := _session_state.get_full_replay_step_timeline_entries()
				if append_applied and cached_entries_ready:
					var appended_events_val = append_info.get("appended_events", [])
					var appended_events: Array = appended_events_val if (appended_events_val is Array) else []
					next_entries = previous_entries
					for appended_entry in GameTimelineLogEntriesBuilderClass.build(appended_events):
						if appended_entry is Dictionary:
							next_entries.append(Dictionary(appended_entry).duplicate(false))
				elif cached_entries_ready and int(previous_processed_count) >= 0:
					next_entries = previous_entries
				else:
					var append_events_val = append_timeline.get("events", [])
					var append_events_all: Array = append_events_val if (append_events_val is Array) else []
					next_entries = GameTimelineLogEntriesBuilderClass.build(append_events_all)
				_store_full_replay_step_timeline_cache(append_timeline, next_entries)
				_emit_resume_cache_event("resume_cache.timeline_cache_refresh.done", {
					"mode": "append" if append_applied else "reuse",
					"allow_incremental_append": bool(allow_incremental_append),
					"previous_processed_command_count": int(previous_processed_count),
					"timeline_processed_command_count": int(
						StepTimelineHelpersClass.read_processed_command_count(append_timeline)
					),
					"timeline_step_count": int(Array(append_timeline.get("steps", [])).size()),
					"timeline_entry_count": int(next_entries.size()),
				})
				return Result.success({
					"timeline": append_timeline,
					"append_applied": append_applied,
				}).with_warnings(append_r.warnings)
		_emit_resume_cache_event("resume_cache.timeline_cache_refresh.append_failed_fallback_full", {
			"allow_incremental_append": bool(allow_incremental_append),
			"previous_processed_command_count": int(previous_processed_count),
			"full_replay_command_count": int(engine.command_history.size()),
			"append_ok": bool(append_r.ok),
			"append_error": str(append_r.error),
		})

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		_emit_resume_cache_event("resume_cache.timeline_cache_refresh.failed", {
			"mode": "full_rebuild",
			"allow_incremental_append": bool(allow_incremental_append),
			"previous_processed_command_count": int(previous_processed_count),
			"full_replay_command_count": int(engine.command_history.size()),
			"error": str(build_r.error),
		})
		return build_r
	if not (build_r.value is Dictionary):
		_emit_resume_cache_event("resume_cache.timeline_cache_refresh.failed", {
			"mode": "full_rebuild",
			"allow_incremental_append": bool(allow_incremental_append),
			"previous_processed_command_count": int(previous_processed_count),
			"full_replay_command_count": int(engine.command_history.size()),
			"error": "step timeline cache build 返回类型错误",
		})
		return Result.failure("step timeline cache build 返回类型错误")

	var timeline: Dictionary = Dictionary(build_r.value).duplicate(true)
	var events_val = timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)
	_store_full_replay_step_timeline_cache(timeline, entries)
	_emit_resume_cache_event("resume_cache.timeline_cache_refresh.done", {
		"mode": "full_rebuild",
		"allow_incremental_append": bool(allow_incremental_append),
		"previous_processed_command_count": int(previous_processed_count),
		"timeline_processed_command_count": int(
			StepTimelineHelpersClass.read_processed_command_count(timeline)
		),
		"timeline_step_count": int(Array(timeline.get("steps", [])).size()),
		"timeline_entry_count": int(entries.size()),
	})
	return Result.success({
		"timeline": timeline,
		"append_applied": false,
	}).with_warnings(build_r.warnings)

func replay_full_replay_live_tail(engine: GameEngine, generation: int) -> Result:
	return _replay_pending_full_replay_live_tail(engine, generation, 0)

func _replay_pending_full_replay_live_tail(
	engine: GameEngine,
	generation: int,
	start_index: int = -1
) -> Result:
	if int(generation) != int(_session_state.full_history_generation):
		return Result.failure("generation mismatch")
	var tail_commands: Array[Dictionary] = _session_state.get_full_replay_live_tail_commands()
	var start := int(start_index)
	if start < 0:
		start = int(_session_state.full_replay_live_tail_applied_count)
	start = clampi(start, 0, tail_commands.size())
	for idx in range(start, tail_commands.size()):
		if int(generation) != int(_session_state.full_history_generation):
			return Result.failure("generation changed while replaying tail")
		var item_val = tail_commands[idx]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val)
		var cmd_dict: Dictionary = Dictionary(item.get("cmd_dict", {})).duplicate(true)
		var apply_r: Result = apply_full_history_command_to_engine(
			engine,
			cmd_dict,
			str(item.get("state_hash", "")).strip_edges()
		)
		if not apply_r.ok:
			return apply_r
	_session_state.mark_full_replay_live_tail_applied(tail_commands.size())
	return Result.success()

func apply_full_history_command_to_engine(engine: GameEngine, cmd_dict: Dictionary, expected_state_hash: String) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	if cmd_dict.is_empty():
		return Result.failure("cmd_dict 为空")
	var parsed: Result = CommandClass.from_dict(Dictionary(cmd_dict).duplicate(true))
	if not parsed.ok:
		return Result.failure("命令解析失败: %s" % parsed.error)
	var cmd: Command = parsed.value
	var expected_index := int(engine.command_history.size())
	if int(cmd.index) != expected_index:
		return Result.failure("cmd.index 不匹配（expected=%d actual=%d）" % [expected_index, int(cmd.index)])
	var exec_r: Result = engine.execute_command(cmd, true)
	if not exec_r.ok:
		return Result.failure("命令回放失败: %s" % exec_r.error)
	var normalized_hash := str(expected_state_hash).strip_edges()
	if normalized_hash.is_empty():
		return Result.success()
	var state = engine.get_state()
	if state == null or not state.has_method("compute_hash"):
		return Result.failure("state hash 不可用")
	var local_hash := str(state.compute_hash())
	if local_hash != normalized_hash:
		return Result.failure(
			"state_hash 不匹配（local=%s server=%s）"
				% [_short_hash_value(local_hash), _short_hash_value(normalized_hash)]
		)
	return Result.success()

func _safe_text_value(value: String) -> String:
	if _safe_text.is_valid():
		return str(_safe_text.call(value))
	return str(value)

func _short_hash_value(value: String) -> String:
	if _short_hash.is_valid():
		return str(_short_hash.call(value))
	return str(value)

func _net_has_signal_value(signal_name: String) -> bool:
	if _net_has_signal.is_valid():
		return bool(_net_has_signal.call(signal_name))
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return false
	return (_net as Object).has_signal(signal_name)

func _emit_resume_cache_event(event: String, fields: Dictionary = {}) -> void:
	if not OnlinePerfTraceClass.enabled():
		return
	var out: Dictionary = {
		"room_code": str(_session_state.runtime_room_code).strip_edges().to_upper(),
		"full_history_generation": int(_session_state.full_history_generation),
		"full_replay_ready": bool(_session_state.full_replay_engine_ready),
		"full_replay_live_tail_count": int(_session_state.full_replay_live_tail_commands.size()),
		"cached_timeline_ready": bool(_session_state.has_full_replay_step_timeline()),
		"cached_timeline_processed_command_count": int(
			_session_state.full_replay_step_timeline.get("_build_meta", {}).get("processed_command_count", -1)
		),
		"cached_timeline_entries_ready": bool(_session_state.has_full_replay_step_timeline_entries()),
		"cached_timeline_entry_count": int(_session_state.full_replay_step_timeline_entries.size()),
		"cached_timeline_entries_processed_command_count": int(
			_session_state.get_full_replay_step_timeline_entries_processed_command_count()
		),
	}
	for key in fields.keys():
		out[str(key)] = fields[key]
	OnlinePerfTraceClass.emit_event(str(event).strip_edges(), out)

func _store_full_replay_step_timeline_cache(timeline: Dictionary, entries: Array) -> void:
	var normalized_timeline := Dictionary(timeline).duplicate(false) if (timeline is Dictionary) else {}
	_session_state.set_full_replay_step_timeline(normalized_timeline)
	_session_state.set_full_replay_step_timeline_entries(
		entries,
		StepTimelineHelpersClass.read_processed_command_count(normalized_timeline)
	)

func _maybe_emit_match_bootstrap_local_failed(message: String, room_code: String = "") -> void:
	if not _should_abort_match_bootstrap_on_full_history_failure(room_code):
		return
	if _net == null or not is_instance_valid(_net):
		return
	if not _net_has_signal_value("match_bootstrap_local_failed"):
		return
	_net.emit_signal("match_bootstrap_local_failed", str(message).strip_edges())

func _should_abort_match_bootstrap_on_full_history_failure(room_code: String = "") -> bool:
	if NetContext == null:
		return false
	var room_state: Dictionary = Dictionary(NetContext.room_state).duplicate(true)
	if str(room_state.get("status", "")).strip_edges() != "Starting":
		return false
	if str(room_state.get("room_mode", "")).strip_edges() != "resume_archive":
		return false
	var expected_room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if expected_room_code.is_empty():
		return false
	if not normalized_room_code.is_empty() and normalized_room_code != expected_room_code:
		return false
	return true

func _is_resume_archive_runtime_context(room_code: String = "") -> bool:
	if NetContext == null:
		return false
	var room_state: Dictionary = Dictionary(NetContext.room_state).duplicate(true)
	if str(room_state.get("room_mode", "")).strip_edges() == "resume_archive":
		var expected_room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
		var normalized_room_code := str(room_code).strip_edges().to_upper()
		if expected_room_code.is_empty() or normalized_room_code.is_empty() or expected_room_code == normalized_room_code:
			return true
	if bool(_session_state.single_full_engine_mode):
		return true
	return false
