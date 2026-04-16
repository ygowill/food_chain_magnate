class_name OnlineResumeSessionState
extends RefCounted

var runtime_engine: GameEngine = null
var runtime_room_code: String = ""
var runtime_local_player_id: int = -1

var full_replay_engine: GameEngine = null
var full_replay_engine_ready: bool = false
var full_replay_room_code: String = ""
var full_archive: Dictionary = {}
var full_archive_meta: Dictionary = {}
var runtime_anchor: Dictionary = {}
var full_history_source_mode: String = "none"
var last_full_history_error: String = ""
var full_history_generation: int = 0
var full_replay_live_tail_commands: Array[Dictionary] = []
var full_replay_step_timeline: Dictionary = {}

func reset() -> void:
	clear_runtime()
	clear_full_history()

func clear_runtime() -> void:
	runtime_engine = null
	runtime_room_code = ""
	runtime_local_player_id = -1
	runtime_anchor = {}

func clear_full_history() -> void:
	_reset_full_history_state(false)

func bind_runtime(engine: GameEngine, room_code: String, local_player_id: int) -> void:
	runtime_engine = engine
	runtime_room_code = str(room_code).strip_edges().to_upper()
	runtime_local_player_id = int(local_player_id)

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
	last_full_history_error = ""
	return full_replay_engine_ready

func mark_full_history_error(message: String, generation: int) -> bool:
	if int(generation) != int(full_history_generation):
		return false
	full_replay_engine = null
	full_replay_engine_ready = false
	last_full_history_error = str(message).strip_edges()
	return true

func has_full_archive_payload() -> bool:
	return not full_archive.is_empty()

func set_full_replay_step_timeline(timeline: Dictionary) -> void:
	full_replay_step_timeline = Dictionary(timeline).duplicate(true) if (timeline is Dictionary) else {}

func get_full_replay_step_timeline() -> Dictionary:
	return full_replay_step_timeline.duplicate(true)

func has_full_replay_step_timeline() -> bool:
	return not full_replay_step_timeline.is_empty()

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
	var runtime_hash := ""
	if runtime_engine != null and runtime_engine.get_state() != null and runtime_engine.get_state().has_method("compute_hash"):
		runtime_hash = str(runtime_engine.get_state().compute_hash())
	var full_hash := ""
	if full_replay_engine != null and full_replay_engine.get_state() != null and full_replay_engine.get_state().has_method("compute_hash"):
		full_hash = str(full_replay_engine.get_state().compute_hash())
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
		"full_replay_step_timeline_ready": not full_replay_step_timeline.is_empty(),
		"full_history_source_mode": full_history_source_mode,
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
	full_history_source_mode = "none"
	last_full_history_error = ""
	full_replay_step_timeline = {}
	if not bool(preserve_live_tail):
		full_replay_live_tail_commands.clear()
