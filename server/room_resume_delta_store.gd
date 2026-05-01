extends RefCounted

var _checkpoint_id: String = ""
var _checkpoint_sequence: int = 0
var _checkpoint_state_hash: String = ""
var _checkpoint_archive: Dictionary = {}
var _delta_log: Array[Dictionary] = []
var _unhealthy_reason: String = ""
var _checkpoint_counter: int = 0

func clear() -> void:
	_checkpoint_id = ""
	_checkpoint_sequence = 0
	_checkpoint_state_hash = ""
	_checkpoint_archive = {}
	_delta_log.clear()
	_unhealthy_reason = ""

func reset_from_engine(status: String, in_game_status: String, engine, reason: String = "") -> Result:
	if status != in_game_status:
		clear()
		return Result.success()
	if engine == null:
		_unhealthy_reason = "Room engine missing"
		return Result.failure(_unhealthy_reason)
	if not engine.has_method("create_archive"):
		_unhealthy_reason = "Room engine missing create_archive"
		return Result.failure(_unhealthy_reason)

	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		_unhealthy_reason = "create_archive failed: %s" % archive_r.error
		return Result.failure(_unhealthy_reason)

	_checkpoint_counter += 1
	var suffix := str(reason).strip_edges()
	if suffix.is_empty():
		suffix = "checkpoint"
	_checkpoint_sequence = _current_sequence(engine)
	_checkpoint_state_hash = _current_state_hash(engine)
	_checkpoint_id = "%s_%d_%d" % [suffix, _checkpoint_sequence, _checkpoint_counter]
	_checkpoint_archive = Dictionary(archive_r.value).duplicate(true)
	_delta_log.clear()
	_unhealthy_reason = ""
	return Result.success({
		"checkpoint_id": _checkpoint_id,
		"sequence": _checkpoint_sequence,
		"state_hash": _checkpoint_state_hash,
	})

func get_cursor(engine) -> Dictionary:
	return {
		"checkpoint_id": _checkpoint_id,
		"last_applied_sequence": _current_sequence(engine),
		"last_state_hash": _current_state_hash(engine),
	}

func build_payload(
	room_code: String,
	status: String,
	in_game_status: String,
	engine,
	cursor: Dictionary,
	max_commands: int = 0,
	soft_limit_bytes: int = 0
) -> Result:
	if status != in_game_status:
		return Result.failure("Room is not in game")
	if engine == null:
		return Result.failure("Room engine missing")
	if not _unhealthy_reason.strip_edges().is_empty():
		return Result.failure("recovery store unhealthy: %s" % _unhealthy_reason)
	if cursor.is_empty():
		return Result.failure("resume cursor missing")
	if _checkpoint_archive.is_empty():
		var checkpoint_r: Result = reset_from_engine(status, in_game_status, engine, "resume_init")
		if not checkpoint_r.ok:
			return checkpoint_r

	var from_sequence := int(cursor.get("last_applied_sequence", -1))
	var from_hash := str(cursor.get("last_state_hash", "")).strip_edges()
	var current_sequence := _current_sequence(engine)
	var current_hash := _current_state_hash(engine)
	if from_sequence < 0 or from_sequence > current_sequence:
		return Result.failure("resume cursor sequence invalid")

	var expected_hash := ""
	if from_sequence == current_sequence:
		expected_hash = current_hash
	elif from_sequence == _checkpoint_sequence:
		expected_hash = _checkpoint_state_hash
	else:
		for item in _delta_log:
			var entry: Dictionary = Dictionary(item)
			if int(entry.get("sequence", -1)) != from_sequence:
				continue
			expected_hash = str(entry.get("post_state_hash", "")).strip_edges()
			break
	if expected_hash.is_empty():
		return Result.failure("delta gap")
	if from_hash.is_empty() or expected_hash != from_hash:
		return Result.failure("resume cursor hash mismatch")

	var entries: Array[Dictionary] = []
	for item2 in _delta_log:
		var entry2: Dictionary = Dictionary(item2)
		if int(entry2.get("sequence", -1)) <= from_sequence:
			continue
		entries.append(entry2.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("sequence", -1)) < int(b.get("sequence", -1))
	)

	if from_sequence < current_sequence:
		var expected_sequence := from_sequence + 1
		for entry3 in entries:
			if int(entry3.get("sequence", -1)) != expected_sequence:
				return Result.failure("delta gap")
			expected_sequence += 1
		if expected_sequence - 1 != current_sequence:
			return Result.failure("delta incomplete")

	if max_commands > 0 and entries.size() > max_commands:
		return Result.failure("delta too long")

	var payload := {
		"room_code": str(room_code).strip_edges().to_upper(),
		"checkpoint_id": _checkpoint_id,
		"from_sequence": from_sequence,
		"to_sequence": current_sequence,
		"final_sequence": current_sequence,
		"final_hash": current_hash,
		"entries": entries,
	}
	var payload_bytes := int(var_to_bytes(payload).size())
	if soft_limit_bytes > 0 and payload_bytes > soft_limit_bytes:
		return Result.failure("delta too large")

	return Result.success({
		"payload": payload,
		"payload_bytes": payload_bytes,
		"entry_count": entries.size(),
		"from_sequence": from_sequence,
		"to_sequence": current_sequence,
		"final_hash": current_hash,
	})

func record(
	status: String,
	in_game_status: String,
	engine,
	cmd: Command,
	post_state_hash: String = "",
	rotate_command_threshold: int = 32
) -> Result:
	if status != in_game_status or engine == null or cmd == null:
		return Result.success({
			"recorded": false,
			"reason": "room_not_recordable",
		})
	if _checkpoint_archive.is_empty():
		var checkpoint_r: Result = reset_from_engine(status, in_game_status, engine, "delta_init")
		if not checkpoint_r.ok:
			return Result.failure("record_resume_delta: checkpoint init failed: %s" % checkpoint_r.error)
	var normalized_hash := str(post_state_hash).strip_edges()
	if normalized_hash.is_empty():
		normalized_hash = _current_state_hash(engine)
	if normalized_hash.is_empty():
		_unhealthy_reason = "record_resume_delta: post_state_hash 为空"
		return Result.failure(_unhealthy_reason)
	var sequence := _current_sequence(engine)
	_delta_log.append({
		"sequence": sequence,
		"cmd": cmd.to_dict(),
		"post_state_hash": normalized_hash,
	})
	if sequence - _checkpoint_sequence >= rotate_command_threshold:
		var rotate_r: Result = reset_from_engine(status, in_game_status, engine, "delta_rotate")
		if not rotate_r.ok:
			return Result.failure("record_resume_delta: checkpoint rotate failed: %s" % rotate_r.error)
	return Result.success({
		"recorded": true,
		"sequence": sequence,
		"post_state_hash": normalized_hash,
		"delta_count": _delta_log.size(),
		"checkpoint_id": _checkpoint_id,
	})

func set_unhealthy_reason(reason: String) -> void:
	_unhealthy_reason = str(reason).strip_edges()

func get_delta_count() -> int:
	return _delta_log.size()

func get_delta_log_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in _delta_log:
		out.append(Dictionary(item).duplicate(true))
	return out

static func _current_sequence(engine) -> int:
	if engine == null:
		return 0
	var history_val = engine.get("command_history") if engine is Object else null
	return Array(history_val).size() if history_val is Array else 0

static func _current_state_hash(engine) -> String:
	if engine == null or not engine.has_method("get_state"):
		return ""
	var state = engine.get_state()
	if state == null or not state.has_method("compute_hash"):
		return ""
	return str(state.compute_hash())
