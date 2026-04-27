class_name OnlineResumeSessionState
extends RefCounted

const SOURCE_MODE_NONE := "none"
const SOURCE_MODE_SINGLE_FULL_ENGINE := "single_full_engine"
const SOURCE_MODE_LEGACY_ARCHIVE_PAYLOAD := "archive_payload"

var runtime_engine: GameEngine = null
var runtime_room_code: String = ""
var runtime_local_player_id: int = -1

var full_replay_engine: GameEngine = null
var full_replay_engine_ready: bool = false
var full_replay_room_code: String = ""

# Legacy dual-engine compatibility state. New resume archive startup should use
# SOURCE_MODE_SINGLE_FULL_ENGINE and keep full_replay_engine == runtime_engine.
var full_archive: Dictionary = {}
var full_archive_meta: Dictionary = {}
var runtime_anchor: Dictionary = {}
var full_history_source_mode: String = SOURCE_MODE_NONE
var single_full_engine_mode: bool = false
var last_full_history_error: String = ""
var full_history_generation: int = 0
var full_replay_live_tail_commands: Array[Dictionary] = []
var full_replay_live_tail_applied_count: int = 0
var full_replay_step_timeline: Dictionary = {}
var full_replay_step_timeline_entries: Array[Dictionary] = []
var full_replay_step_timeline_entries_processed_command_count: int = -1
var _runtime_state_hash_cache_signature: Dictionary = {}
var _runtime_state_hash_cache_value: String = ""
var _full_replay_state_hash_cache_signature: Dictionary = {}
var _full_replay_state_hash_cache_value: String = ""

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
	_reset_full_history_state(false)

func bind_runtime(engine: GameEngine, room_code: String, local_player_id: int) -> void:
	runtime_engine = engine
	runtime_room_code = str(room_code).strip_edges().to_upper()
	runtime_local_player_id = int(local_player_id)
	_clear_runtime_state_hash_cache()

func begin_full_history_build(
	room_code: String,
	archive: Dictionary,
	anchor: Dictionary,
	archive_meta: Dictionary,
	source_mode: String,
	preserve_live_tail: bool = false
) -> int:
	_reset_full_history_state(bool(preserve_live_tail))
	full_replay_room_code = str(room_code).strip_edges().to_upper()
	full_archive = Dictionary(archive).duplicate(true)
	full_archive_meta = Dictionary(archive_meta).duplicate(true)
	runtime_anchor = Dictionary(anchor).duplicate(true)
	full_history_source_mode = str(source_mode).strip_edges()
	return full_history_generation

func mark_full_replay_engine_ready(engine: GameEngine, generation: int) -> bool:
	if int(generation) != int(full_history_generation):
		return false
	full_replay_engine = engine
	full_replay_engine_ready = engine != null and engine.get_state() != null
	full_replay_live_tail_applied_count = full_replay_live_tail_commands.size()
	last_full_history_error = ""
	_clear_full_replay_state_hash_cache()
	return full_replay_engine_ready

func mark_full_history_error(message: String, generation: int) -> bool:
	if int(generation) != int(full_history_generation):
		return false
	full_replay_engine = null
	full_replay_engine_ready = false
	last_full_history_error = str(message).strip_edges()
	_clear_full_replay_state_hash_cache()
	return true

func set_full_replay_step_timeline(timeline: Dictionary) -> void:
	full_replay_step_timeline = Dictionary(timeline).duplicate(false) if (timeline is Dictionary) else {}
	if full_replay_step_timeline.is_empty():
		full_replay_step_timeline_entries.clear()
		full_replay_step_timeline_entries_processed_command_count = -1

func get_full_replay_step_timeline() -> Dictionary:
	return full_replay_step_timeline.duplicate(false)

func has_full_replay_step_timeline() -> bool:
	return not full_replay_step_timeline.is_empty()

func set_full_replay_step_timeline_entries(entries: Array, processed_command_count: int = -1) -> void:
	full_replay_step_timeline_entries.clear()
	if entries is Array:
		for entry_val in entries:
			if not (entry_val is Dictionary):
				continue
			full_replay_step_timeline_entries.append(Dictionary(entry_val).duplicate(false))
	full_replay_step_timeline_entries_processed_command_count = int(processed_command_count)

func get_full_replay_step_timeline_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_val in full_replay_step_timeline_entries:
		if not (entry_val is Dictionary):
			continue
		out.append(Dictionary(entry_val).duplicate(false))
	return out

func has_full_replay_step_timeline_entries() -> bool:
	return int(full_replay_step_timeline_entries_processed_command_count) >= 0

func get_full_replay_step_timeline_entries_processed_command_count() -> int:
	return int(full_replay_step_timeline_entries_processed_command_count)

func mark_full_replay_live_tail_applied(count: int) -> void:
	full_replay_live_tail_applied_count = clampi(int(count), 0, full_replay_live_tail_commands.size())

func append_full_replay_live_tail_command(cmd_dict: Dictionary, state_hash: String = "") -> void:
	if cmd_dict.is_empty():
		return
	full_replay_live_tail_commands.append({
		"cmd_dict": Dictionary(cmd_dict).duplicate(true),
		"state_hash": str(state_hash).strip_edges(),
	})

func get_full_replay_live_tail_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_val in full_replay_live_tail_commands:
		if not (item_val is Dictionary):
			continue
		out.append(Dictionary(item_val).duplicate(true))
	return out

func snapshot() -> Dictionary:
	var runtime_hash := _get_cached_engine_state_hash(runtime_engine, true)
	var full_hash := _get_cached_engine_state_hash(full_replay_engine, false)
	return {
		"runtime_room_code": runtime_room_code,
		"runtime_local_player_id": runtime_local_player_id,
		"runtime_ready": runtime_engine != null and runtime_engine.get_state() != null,
		"runtime_current_index": int(runtime_engine.current_command_index) if runtime_engine != null else -1,
		"runtime_command_count": int(runtime_engine.command_history.size()) if runtime_engine != null else 0,
		"runtime_state_hash": runtime_hash,
		"runtime_anchor": runtime_anchor.duplicate(true),
		"full_replay_room_code": full_replay_room_code,
		"full_replay_ready": full_replay_engine_ready,
		"full_replay_command_count": int(full_replay_engine.command_history.size()) if full_replay_engine != null else 0,
		"full_replay_state_hash": full_hash,
		"full_replay_live_tail_count": full_replay_live_tail_commands.size(),
		"full_replay_live_tail_applied_count": int(full_replay_live_tail_applied_count),
		"full_replay_live_tail_pending_count": maxi(0, int(full_replay_live_tail_commands.size()) - int(full_replay_live_tail_applied_count)),
		"full_replay_step_timeline_ready": not full_replay_step_timeline.is_empty(),
		"full_replay_step_timeline_entries_ready": has_full_replay_step_timeline_entries(),
		"full_replay_step_timeline_entry_count": int(full_replay_step_timeline_entries.size()),
		"full_replay_step_timeline_entries_processed_command_count": int(
			full_replay_step_timeline_entries_processed_command_count
		),
		"full_history_source_mode": full_history_source_mode,
		"single_full_engine_mode": bool(single_full_engine_mode),
		"full_archive_meta": full_archive_meta.duplicate(true),
		"has_full_archive_payload": not full_archive.is_empty(),
		"last_full_history_error": last_full_history_error,
	}

func _reset_full_history_state(preserve_live_tail: bool) -> void:
	full_history_generation += 1
	full_replay_engine = null
	full_replay_engine_ready = false
	full_replay_room_code = ""
	full_archive = {}
	full_archive_meta = {}
	full_history_source_mode = SOURCE_MODE_NONE
	single_full_engine_mode = false
	last_full_history_error = ""
	full_replay_step_timeline = {}
	full_replay_step_timeline_entries.clear()
	full_replay_step_timeline_entries_processed_command_count = -1
	full_replay_live_tail_applied_count = 0
	_clear_full_replay_state_hash_cache()
	if not bool(preserve_live_tail):
		full_replay_live_tail_commands.clear()

func _get_cached_engine_state_hash(engine: GameEngine, is_runtime_engine: bool) -> String:
	if engine == null:
		if bool(is_runtime_engine):
			_clear_runtime_state_hash_cache()
		else:
			_clear_full_replay_state_hash_cache()
		return ""
	var state = engine.get_state()
	if state == null or not state.has_method("compute_hash"):
		if bool(is_runtime_engine):
			_clear_runtime_state_hash_cache()
		else:
			_clear_full_replay_state_hash_cache()
		return ""

	var signature := _build_engine_state_hash_signature(engine, state)
	if bool(is_runtime_engine):
		if _runtime_state_hash_cache_signature == signature:
			return _runtime_state_hash_cache_value
		_runtime_state_hash_cache_signature = signature
		_runtime_state_hash_cache_value = str(state.compute_hash())
		return _runtime_state_hash_cache_value

	if _full_replay_state_hash_cache_signature == signature:
		return _full_replay_state_hash_cache_value
	_full_replay_state_hash_cache_signature = signature
	_full_replay_state_hash_cache_value = str(state.compute_hash())
	return _full_replay_state_hash_cache_value

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

func _clear_full_replay_state_hash_cache() -> void:
	_full_replay_state_hash_cache_signature.clear()
	_full_replay_state_hash_cache_value = ""
