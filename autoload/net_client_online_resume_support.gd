# NetClient：联机恢复房双轨支持（runtime_engine + full_replay_engine）
# 目标：把 fast-start / full-history / live-tail 的复杂度从 net_client/client.gd 中收口出去。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumeSessionStateClass = preload("res://autoload/online_resume_session_state.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")

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

func clear_online_resume_dual_engine_state() -> void:
	_session_state.reset()

func extract_resume_fast_start_bundle(payload: Dictionary) -> Dictionary:
	var bundle_val = payload.get("resume_fast_start_bundle", null)
	if not (bundle_val is Dictionary):
		return {}
	var bundle: Dictionary = Dictionary(bundle_val).duplicate(true)
	var runtime_archive_val = bundle.get("runtime_archive", null)
	if not (runtime_archive_val is Dictionary):
		GameLog.warn("NetClient", "RX GameStarted fast-start ignored: runtime_archive type invalid")
		return {}
	return bundle

func bootstrap_runtime_engine_from_fast_start_bundle(
	bundle: Dictionary,
	room_code: String,
	local_pid: int
) -> Result:
	var runtime_archive: Dictionary = Dictionary(bundle.get("runtime_archive", {})).duplicate(true)
	if runtime_archive.is_empty():
		return Result.failure("resume_fast_start_bundle.runtime_archive 缺失")
	if not _load_archive_for_online_client.is_valid():
		return Result.failure("load_archive_for_online_client 未绑定")
	var engine = GameEngineClass.new()
	var load_r = _load_archive_for_online_client.call(engine, runtime_archive)
	if not (load_r is Result):
		return Result.failure("load_archive_for_online_client 返回类型错误")
	if not load_r.ok:
		GameLog.error("NetClient", "Online resume fast-start runtime load failed: %s" % load_r.error)
		return Result.failure(str(load_r.error))
	if _mark_online_client_engine_ready.is_valid():
		_mark_online_client_engine_ready.call(engine, room_code, local_pid)
	bind_resume_fast_start_session(engine, room_code, local_pid, bundle)
	GameLog.info(
		"NetClient",
		"Online client runtime_engine ready via fast-start room=%s commands=%d"
			% [_safe_text_value(room_code), int(engine.command_history.size())]
	)
	return Result.success(engine)

func bind_resume_fast_start_session(
	runtime_engine: GameEngine,
	room_code: String,
	local_pid: int,
	bundle: Dictionary
) -> void:
	_session_state.bind_runtime(runtime_engine, room_code, local_pid)
	_session_state.runtime_anchor = Dictionary(bundle.get("runtime_anchor", {})).duplicate(true)
	_session_state.full_archive_meta = Dictionary(bundle.get("full_archive_meta", {})).duplicate(true)
	var full_archive_payload: Dictionary = Dictionary(bundle.get("full_archive_payload", {})).duplicate(true)
	if not full_archive_payload.is_empty():
		_session_state.full_archive = full_archive_payload
		_session_state.full_history_source_mode = "archive_payload"
	else:
		_session_state.full_archive = {}
		_session_state.full_history_source_mode = "none"
		_session_state.full_replay_engine = null
		_session_state.full_replay_engine_ready = false
		_session_state.full_replay_room_code = ""
	if _sync_online_resume_progress.is_valid():
		_sync_online_resume_progress.call(runtime_engine)

func mark_runtime_engine_as_full_history(engine) -> void:
	if engine == null:
		return
	var room_code := ""
	if _get_online_client_engine_room_code.is_valid():
		room_code = str(_get_online_client_engine_room_code.call())
	var local_pid := int(NetContext.local_player_id) if NetContext != null else -1
	if engine is GameEngine:
		_session_state.bind_runtime(engine, room_code, local_pid)
	_session_state.runtime_anchor = {
		"global_command_start_index": 0,
		"global_command_end_index": int(engine.current_command_index) if engine is Object else -1,
	}

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

func schedule_full_replay_engine_bootstrap(room_code: String, preserve_live_tail: bool = false) -> void:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if _session_state.runtime_room_code != normalized_room_code:
		return
	if _session_state.full_history_source_mode != "archive_payload" or _session_state.full_archive.is_empty():
		return
	var expected_hash := str(_session_state.full_archive_meta.get("full_final_hash", "")).strip_edges()
	if _session_state.full_replay_engine_ready \
		and _session_state.full_replay_engine != null \
		and _session_state.full_replay_engine.get_state() != null:
		if _session_state.full_replay_room_code == normalized_room_code:
			var current_hash := str(_session_state.full_replay_engine.get_state().compute_hash())
			if expected_hash.is_empty() or current_hash == expected_hash:
				return
	var generation = _session_state.begin_full_history_build(
		normalized_room_code,
		_session_state.full_archive,
		_session_state.runtime_anchor,
		_session_state.full_archive_meta,
		_session_state.full_history_source_mode,
		bool(preserve_live_tail)
	)
	call_deferred("_deferred_build_full_replay_engine", normalized_room_code, generation)

func _deferred_build_full_replay_engine(room_code: String, generation: int) -> void:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if int(generation) != int(_session_state.full_history_generation):
		return
	if _session_state.full_replay_room_code != normalized_room_code:
		return
	var archive: Dictionary = Dictionary(_session_state.full_archive).duplicate(true)
	if archive.is_empty():
		return
	if not _load_archive_for_online_client.is_valid():
		_session_state.mark_full_history_error("load_archive_for_online_client 未绑定", generation)
		return

	var engine = GameEngineClass.new()
	engine.set_event_sink(_LocalEventSink.new())
	var load_r = _load_archive_for_online_client.call(engine, archive)
	if not (load_r is Result):
		_session_state.mark_full_history_error("load_archive_for_online_client 返回类型错误", generation)
		return
	if not load_r.ok:
		_session_state.mark_full_history_error("load_from_archive failed: %s" % load_r.error, generation)
		GameLog.error("NetClient", "Online resume full_replay_engine load failed: %s" % load_r.error)
		return
	var prepare_r: Result = OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	if not prepare_r.ok:
		_session_state.mark_full_history_error("prepare_engine_for_online_resume failed: %s" % prepare_r.error, generation)
		GameLog.error("NetClient", "Online resume full_replay_engine prepare failed: %s" % prepare_r.error)
		return
	var replay_tail_r: Result = replay_full_replay_live_tail(engine, generation)
	if not replay_tail_r.ok:
		_session_state.mark_full_history_error("replay_full_replay_live_tail failed: %s" % replay_tail_r.error, generation)
		GameLog.error("NetClient", "Online resume full_replay_engine tail replay failed: %s" % replay_tail_r.error)
		return
	if not _session_state.mark_full_replay_engine_ready(engine, generation):
		return
	GameLog.info(
		"NetClient",
		"Online resume full_replay_engine ready room=%s commands=%d"
			% [_safe_text_value(normalized_room_code), int(engine.command_history.size())]
	)
	if _net != null and is_instance_valid(_net) and _net_has_signal_value("resume_full_history_ready"):
		_net.emit_signal("resume_full_history_ready", _session_state.snapshot())

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
	if _session_state.full_history_source_mode != "archive_payload" and _session_state.full_archive.is_empty():
		return
	_session_state.append_full_replay_live_tail_command(cmd_dict, state_hash)
	var full_engine: GameEngine = _session_state.full_replay_engine
	if not _session_state.full_replay_engine_ready or full_engine == null or full_engine.get_state() == null:
		return
	var apply_r: Result = apply_full_history_command_to_engine(full_engine, cmd_dict, state_hash)
	if apply_r.ok:
		return
	GameLog.warn(
		"NetClient",
		"Online resume full_replay_engine append failed room=%s origin=%s err=%s"
			% [_safe_text_value(_session_state.runtime_room_code), _safe_text_value(str(origin)), _safe_text_value(apply_r.error)]
	)
	if _session_state.full_history_source_mode == "archive_payload" and not _session_state.full_archive.is_empty():
		schedule_full_replay_engine_bootstrap(_session_state.runtime_room_code, true)
		return
	_session_state.mark_full_history_error("append failed: %s" % apply_r.error, _session_state.full_history_generation)

func replay_full_replay_live_tail(engine: GameEngine, generation: int) -> Result:
	if int(generation) != int(_session_state.full_history_generation):
		return Result.failure("generation mismatch")
	var tail_commands: Array[Dictionary] = _session_state.get_full_replay_live_tail_commands()
	for item_val in tail_commands:
		if int(generation) != int(_session_state.full_history_generation):
			return Result.failure("generation changed while replaying tail")
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
