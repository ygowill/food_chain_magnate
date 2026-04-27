# NetClient server helper：构造 resync snapshot/delta transfer。
extends RefCounted

const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")

static func build_full_snapshot_transfer(room, chunk_size_bytes: int, max_chunks: int) -> Result:
	if room == null:
		return Result.failure("Room missing")
	if room.game_engine == null:
		return Result.failure("Room engine missing")

	var archive_r = room.game_engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)

	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var transfer_id := "%s_%d_%d" % [
		_normalized_room_code(str(room.room_code)),
		int(room.game_engine.command_history.size()),
		int(Time.get_ticks_msec()),
	]
	var chunk_r: Result = ResyncSnapshotTransferClass.build_snapshot_transfer(
		archive,
		transfer_id,
		int(chunk_size_bytes),
		int(max_chunks)
	)
	if not chunk_r.ok:
		return Result.failure("Resync archive too large (%s)" % str(chunk_r.error))

	var state_hash := ""
	var state = room.game_engine.get_state()
	if state != null and state.has_method("compute_hash"):
		state_hash = str(state.compute_hash())

	return _snapshot_result(
		_normalized_room_code(str(room.room_code)),
		Dictionary(chunk_r.value),
		int(room.game_engine.command_history.size()),
		state_hash
	)

static func build_archive_snapshot_transfer(
	room_code: String,
	archive: Dictionary,
	history_size: int,
	state_hash: String,
	chunk_size_bytes: int,
	max_chunks: int
) -> Result:
	if archive.is_empty():
		return Result.failure("Archive missing")
	var normalized_room_code := _normalized_room_code(room_code)
	var transfer_id := "%s_resume_%d" % [
		normalized_room_code,
		int(Time.get_ticks_msec()),
	]
	var chunk_r: Result = ResyncSnapshotTransferClass.build_snapshot_transfer(
		Dictionary(archive).duplicate(true),
		transfer_id,
		int(chunk_size_bytes),
		int(max_chunks)
	)
	if not chunk_r.ok:
		return Result.failure("Resync archive too large (%s)" % str(chunk_r.error))

	return _snapshot_result(
		normalized_room_code,
		Dictionary(chunk_r.value),
		int(history_size),
		str(state_hash).strip_edges()
	)

static func build_delta_transfer(
	room,
	resume_cursor: Dictionary,
	max_commands: int,
	soft_limit_bytes: int
) -> Result:
	if room == null:
		return Result.failure("Room missing")
	if not room.has_method("build_delta_resume_payload"):
		return Result.failure("Room delta resume missing")
	return room.build_delta_resume_payload(
		Dictionary(resume_cursor).duplicate(true),
		int(max_commands),
		int(soft_limit_bytes)
	)

static func _snapshot_result(
	room_code: String,
	chunk_payload: Dictionary,
	history_size: int,
	state_hash: String
) -> Result:
	var manifest: Dictionary = Dictionary(chunk_payload.get("manifest", {})).duplicate(true)
	manifest["room_code"] = _normalized_room_code(room_code)
	return Result.success({
		"manifest": manifest,
		"chunks": Array(chunk_payload.get("chunks", [])).duplicate(true),
		"payload_bytes": int(chunk_payload.get("total_bytes", 0)),
		"chunk_count": int(chunk_payload.get("chunk_count", 0)),
		"archive_hash": str(chunk_payload.get("archive_hash", "")),
		"history_size": int(history_size),
		"state_hash": str(state_hash).strip_edges(),
	})

static func _normalized_room_code(value: String) -> String:
	var out := str(value).strip_edges().to_upper()
	if out.is_empty():
		return "-"
	return out
