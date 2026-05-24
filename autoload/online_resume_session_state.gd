class_name OnlineResumeSessionState
extends RefCounted

const SOURCE_MODE_NONE := "none"
const SOURCE_MODE_SINGLE_FULL_ENGINE := "single_full_engine"

var runtime_engine: GameEngine = null
var runtime_room_code: String = ""
var runtime_local_player_id: int = -1

var full_history_engine: GameEngine = null
var full_history_engine_ready: bool = false
var full_history_room_code: String = ""
var full_archive_meta: Dictionary = {}
var runtime_anchor: Dictionary = {}
var full_history_source_mode: String = SOURCE_MODE_NONE
var single_full_engine_mode: bool = false
var last_full_history_error: String = ""
var full_history_step_timeline: Dictionary = {}
var full_history_step_timeline_entries: Array[Dictionary] = []
var full_history_step_timeline_entries_processed_command_count: int = -1
var full_history_step_timeline_entries_last_event_sequence: int = -1
var _runtime_state_hash_cache_signature: Dictionary = {}
var _runtime_state_hash_cache_value: String = ""
var _full_history_state_hash_cache_signature: Dictionary = {}
var _full_history_state_hash_cache_value: String = ""

func reset() -> void:
	clear_runtime()
	clear_full_history()

func clear_runtime() -> void:
	runtime_engine = null
	runtime_room_code = ""
	runtime_local_player_id = -1
	runtime_anchor = {}
	_clear_runtime_state_hash_cache()

func clear_full_history() -> void:
	_reset_full_history_state()

func bind_runtime(engine: GameEngine, room_code: String, local_player_id: int) -> void:
	runtime_engine = engine
	runtime_room_code = str(room_code).strip_edges().to_upper()
	runtime_local_player_id = int(local_player_id)
	_clear_runtime_state_hash_cache()

func set_full_history_step_timeline(timeline: Dictionary) -> void:
	var previous_entries_processed_count := int(full_history_step_timeline_entries_processed_command_count)
	var previous_entries_last_event_sequence := int(full_history_step_timeline_entries_last_event_sequence)
	full_history_step_timeline = Dictionary(timeline).duplicate(false) if (timeline is Dictionary) else {}
	var next_processed_count := _read_step_timeline_processed_command_count(full_history_step_timeline)
	var next_last_event_sequence := _read_step_timeline_last_event_sequence(full_history_step_timeline)
	if full_history_step_timeline.is_empty() \
		or next_processed_count != previous_entries_processed_count \
		or next_last_event_sequence != previous_entries_last_event_sequence:
		full_history_step_timeline_entries.clear()
		full_history_step_timeline_entries_processed_command_count = -1
		full_history_step_timeline_entries_last_event_sequence = -1

func get_full_history_step_timeline() -> Dictionary:
	return full_history_step_timeline.duplicate(false)

func has_full_history_step_timeline() -> bool:
	return not full_history_step_timeline.is_empty()

func set_full_history_step_timeline_entries(entries: Array, processed_command_count: int = -1) -> void:
	full_history_step_timeline_entries.clear()
	if entries is Array:
		for entry_val in entries:
			if not (entry_val is Dictionary):
				continue
			full_history_step_timeline_entries.append(Dictionary(entry_val).duplicate(false))
	full_history_step_timeline_entries_processed_command_count = int(processed_command_count)
	full_history_step_timeline_entries_last_event_sequence = _read_step_timeline_last_event_sequence(
		full_history_step_timeline
	) if int(processed_command_count) >= 0 else -1

func get_full_history_step_timeline_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_val in full_history_step_timeline_entries:
		if not (entry_val is Dictionary):
			continue
		out.append(Dictionary(entry_val).duplicate(false))
	return out

func has_full_history_step_timeline_entries() -> bool:
	return int(full_history_step_timeline_entries_processed_command_count) >= 0

func get_full_history_step_timeline_entries_processed_command_count() -> int:
	return int(full_history_step_timeline_entries_processed_command_count)

func snapshot() -> Dictionary:
	var runtime_hash := _get_cached_engine_state_hash(runtime_engine, true)
	var full_hash := _get_cached_engine_state_hash(full_history_engine, false)
	return {
		"runtime_room_code": runtime_room_code,
		"runtime_local_player_id": runtime_local_player_id,
		"runtime_ready": runtime_engine != null and runtime_engine.get_state() != null,
		"runtime_current_index": int(runtime_engine.current_command_index) if runtime_engine != null else -1,
		"runtime_command_count": int(runtime_engine.command_history.size()) if runtime_engine != null else 0,
		"runtime_state_hash": runtime_hash,
		"runtime_anchor": runtime_anchor.duplicate(true),
		"full_history_room_code": full_history_room_code,
		"full_history_ready": full_history_engine_ready,
		"full_history_command_count": int(full_history_engine.command_history.size()) if full_history_engine != null else 0,
		"full_history_state_hash": full_hash,
		"full_history_live_tail_count": 0,
		"full_history_live_tail_applied_count": 0,
		"full_history_live_tail_pending_count": 0,
		"full_history_step_timeline_ready": not full_history_step_timeline.is_empty(),
		"full_history_step_timeline_entries_ready": has_full_history_step_timeline_entries(),
		"full_history_step_timeline_entry_count": int(full_history_step_timeline_entries.size()),
		"full_history_step_timeline_entries_processed_command_count": int(
			full_history_step_timeline_entries_processed_command_count
		),
		"full_history_step_timeline_entries_last_event_sequence": int(
			full_history_step_timeline_entries_last_event_sequence
		),
		"full_history_source_mode": full_history_source_mode,
		"single_full_engine_mode": bool(single_full_engine_mode),
		"full_archive_meta": full_archive_meta.duplicate(true),
		"has_full_archive_payload": false,
		"last_full_history_error": last_full_history_error,
	}

func _reset_full_history_state() -> void:
	full_history_engine = null
	full_history_engine_ready = false
	full_history_room_code = ""
	full_archive_meta = {}
	full_history_source_mode = SOURCE_MODE_NONE
	single_full_engine_mode = false
	last_full_history_error = ""
	full_history_step_timeline = {}
	full_history_step_timeline_entries.clear()
	full_history_step_timeline_entries_processed_command_count = -1
	full_history_step_timeline_entries_last_event_sequence = -1
	_clear_full_history_state_hash_cache()

func _read_step_timeline_processed_command_count(timeline: Dictionary) -> int:
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		return -1
	var meta_val = timeline.get("_build_meta", null)
	if not (meta_val is Dictionary):
		return -1
	var meta: Dictionary = meta_val
	var count_val = meta.get("processed_command_count", -1)
	if count_val is int or count_val is float:
		return int(count_val)
	return -1

func _read_step_timeline_last_event_sequence(timeline: Dictionary) -> int:
	if timeline == null or not (timeline is Dictionary) or timeline.is_empty():
		return -1
	var meta_val = timeline.get("_build_meta", null)
	if not (meta_val is Dictionary):
		return -1
	var meta: Dictionary = meta_val
	var seq_val = meta.get("last_event_sequence", -1)
	if seq_val is int or seq_val is float:
		return int(seq_val)
	return -1

func _get_cached_engine_state_hash(engine: GameEngine, is_runtime_engine: bool) -> String:
	if engine == null:
		if bool(is_runtime_engine):
			_clear_runtime_state_hash_cache()
		else:
			_clear_full_history_state_hash_cache()
		return ""
	var state = engine.get_state()
	if state == null or not state.has_method("compute_hash"):
		if bool(is_runtime_engine):
			_clear_runtime_state_hash_cache()
		else:
			_clear_full_history_state_hash_cache()
		return ""

	var signature := _build_engine_state_hash_signature(engine, state)
	if bool(is_runtime_engine):
		if _runtime_state_hash_cache_signature == signature:
			return _runtime_state_hash_cache_value
		_runtime_state_hash_cache_signature = signature
		_runtime_state_hash_cache_value = str(state.compute_hash())
		return _runtime_state_hash_cache_value

	if _full_history_state_hash_cache_signature == signature:
		return _full_history_state_hash_cache_value
	_full_history_state_hash_cache_signature = signature
	_full_history_state_hash_cache_value = str(state.compute_hash())
	return _full_history_state_hash_cache_value

func _build_engine_state_hash_signature(engine: GameEngine, state) -> Dictionary:
	return {
		"engine_id": int(engine.get_instance_id()) if engine is Object else -1,
		"state_id": int(state.get_instance_id()) if state is Object else -1,
		"current_command_index": int(engine.current_command_index),
		"command_count": int(engine.command_history.size()),
	}

func _clear_runtime_state_hash_cache() -> void:
	_runtime_state_hash_cache_signature.clear()
	_runtime_state_hash_cache_value = ""

func _clear_full_history_state_hash_cache() -> void:
	_full_history_state_hash_cache_signature.clear()
	_full_history_state_hash_cache_value = ""
