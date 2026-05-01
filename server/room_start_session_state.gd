extends RefCounted

var _session_id: String = ""
var _request_id: String = ""
var _started_at_ms: int = 0
var _phase: String = ""
var _engine = null
var _payload: Dictionary = {}
var _target_peer_ids: Array[int] = []
var _ready_peer_ids: Dictionary = {}
var _error: String = ""

func clear() -> void:
	_session_id = ""
	_request_id = ""
	_started_at_ms = 0
	_phase = ""
	_engine = null
	_payload = {}
	_target_peer_ids.clear()
	_ready_peer_ids = {}
	_error = ""

func has_pending() -> bool:
	return not _session_id.is_empty()

func begin(room_code: String, request_id: String, target_peer_ids: Array[int], started_at_ms: int) -> void:
	clear()
	var normalized_targets := target_peer_ids.duplicate()
	normalized_targets.sort()
	_session_id = "%s_%d" % [str(room_code).strip_edges().to_upper(), int(started_at_ms)]
	_request_id = str(request_id).strip_edges()
	_started_at_ms = int(started_at_ms)
	_phase = "preparing"
	_target_peer_ids = normalized_targets

func get_session_id() -> String:
	return _session_id

func get_request_id() -> String:
	return _request_id

func set_phase(phase: String) -> void:
	if not has_pending():
		return
	_phase = str(phase).strip_edges()

func get_target_peer_ids() -> Array[int]:
	return _target_peer_ids.duplicate()

func mark_peer_ready(peer_id: int) -> bool:
	if not has_pending():
		return false
	if not _target_peer_ids.has(peer_id):
		return false
	_ready_peer_ids[peer_id] = true
	return true

func is_peer_ready(peer_id: int) -> bool:
	return bool(_ready_peer_ids.get(peer_id, false))

func is_ready_to_commit() -> bool:
	if not has_pending():
		return false
	for peer_id in _target_peer_ids:
		if not is_peer_ready(peer_id):
			return false
	return true

func set_prepared(engine, payload: Dictionary, phase: String = "waiting_for_players") -> void:
	_engine = engine
	_payload = payload.duplicate(true)
	set_phase(phase)

func has_prepared_payload() -> bool:
	return _engine != null and is_instance_valid(_engine) and not _payload.is_empty()

func get_prepared_engine():
	return _engine

func get_payload() -> Dictionary:
	return _payload.duplicate(true)

func set_error(error: String) -> void:
	_error = str(error).strip_edges()

func get_summary() -> Dictionary:
	if not has_pending():
		return {}
	var ready_count := 0
	for peer_id in _target_peer_ids:
		if is_peer_ready(peer_id):
			ready_count += 1
	return {
		"id": _session_id,
		"phase": _phase,
		"ready_count": ready_count,
		"total_count": _target_peer_ids.size(),
		"request_id": _request_id,
		"started_at_ms": _started_at_ms,
		"error": _error,
	}
