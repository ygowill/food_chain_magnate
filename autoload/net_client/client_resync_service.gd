extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")

var _net = null

var _matches_payload_room_code: Callable = Callable()
var _invalidate_full_history_engine: Callable = Callable()
var _emit_local_bootstrap_progress: Callable = Callable()
var _make_local_bootstrap_progress_state: Callable = Callable()
var _consume_pending_resume_full_snapshot_payload: Callable = Callable()
var _get_pending_resume_full_snapshot_local_pid: Callable = Callable()
var _set_pending_resume_full_snapshot_local_pid: Callable = Callable()
var _bootstrap_resume_full_snapshot_archive: Callable = Callable()
var _emit_resume_full_history_ready: Callable = Callable()
var _try_bootstrap_online_client_engine_from_archive: Callable = Callable()
var _translate_resync_delta_to_runtime: Callable = Callable()
var _get_active_resume_engine: Callable = Callable()
var _sync_online_resume_progress: Callable = Callable()
var _safe_text: Callable = Callable()
var _short_hash: Callable = Callable()

func setup(net_client, callbacks: Dictionary = {}) -> void:
	_net = net_client
	_matches_payload_room_code = callbacks.get("matches_payload_room_code", Callable())
	_invalidate_full_history_engine = callbacks.get("invalidate_full_history_engine", Callable())
	_emit_local_bootstrap_progress = callbacks.get("emit_local_bootstrap_progress", Callable())
	_make_local_bootstrap_progress_state = callbacks.get("make_local_bootstrap_progress_state", Callable())
	_consume_pending_resume_full_snapshot_payload = callbacks.get("consume_pending_resume_full_snapshot_payload", Callable())
	_get_pending_resume_full_snapshot_local_pid = callbacks.get("get_pending_resume_full_snapshot_local_pid", Callable())
	_set_pending_resume_full_snapshot_local_pid = callbacks.get("set_pending_resume_full_snapshot_local_pid", Callable())
	_bootstrap_resume_full_snapshot_archive = callbacks.get("bootstrap_resume_full_snapshot_archive", Callable())
	_emit_resume_full_history_ready = callbacks.get("emit_resume_full_history_ready", Callable())
	_try_bootstrap_online_client_engine_from_archive = callbacks.get("try_bootstrap_online_client_engine_from_archive", Callable())
	_translate_resync_delta_to_runtime = callbacks.get("translate_resync_delta_to_runtime", Callable())
	_get_active_resume_engine = callbacks.get("get_active_resume_engine", Callable())
	_sync_online_resume_progress = callbacks.get("sync_online_resume_progress", Callable())
	_safe_text = callbacks.get("safe_text", Callable())
	_short_hash = callbacks.get("short_hash", Callable())

func handle_snapshot_manifest(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var manifest: Dictionary = Dictionary(payload).duplicate(true)
	if not bool(_matches_payload_room_code.call(manifest, "ResyncSnapshot manifest")):
		return
	_invalidate_full_history_engine.call("live_resync_snapshot")
	var transfer_id := str(manifest.get("transfer_id", "")).strip_edges()
	var chunk_count := int(manifest.get("chunk_count", 0))
	if transfer_id.is_empty() or chunk_count <= 0:
		GameLog.warn("NetClient", "RX ResyncSnapshot manifest ignored: invalid manifest")
		return
	set_pending_snapshot_manifest(manifest)
	set_pending_snapshot_chunks({})
	var room_code := str(manifest.get("room_code", "")).strip_edges().to_upper()
	var chunk_count_progress := maxi(1, chunk_count)
	_emit_local_bootstrap_progress.call(_make_local_bootstrap_progress_state.call(
		room_code,
		"snapshot_manifest",
		"正在接收恢复快照...",
		"正在接收完整存档快照分片：0 / %d。" % chunk_count_progress,
		18.0
	))
	GameLog.warn(
		"NetClient",
		"RX ResyncSnapshot manifest request_id=%s transfer_id=%s chunks=%d total_bytes=%d"
			% [
				_safe(str(manifest.get("request_id", ""))),
				_safe(transfer_id),
				chunk_count,
				int(manifest.get("total_bytes", -1)),
			]
	)

func handle_snapshot_chunk(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var manifest := get_pending_snapshot_manifest()
	if manifest.is_empty():
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: manifest missing")
		return
	var transfer_id := str(payload.get("transfer_id", "")).strip_edges()
	if transfer_id != str(manifest.get("transfer_id", "")).strip_edges():
		GameLog.warn(
			"NetClient",
			"RX ResyncSnapshot chunk ignored: transfer mismatch current=%s incoming=%s"
				% [_safe(str(manifest.get("transfer_id", ""))), _safe(transfer_id)]
		)
		return
	var chunk_index := int(payload.get("chunk_index", -1))
	var chunk_count := int(manifest.get("chunk_count", 0))
	if chunk_index < 0 or chunk_index >= chunk_count:
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: index invalid=%d" % chunk_index)
		return
	var bytes_val = payload.get("bytes", null)
	if not (bytes_val is PackedByteArray):
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: bytes invalid index=%d" % chunk_index)
		return
	var chunks := get_pending_snapshot_chunks()
	var chunk_bytes: PackedByteArray = bytes_val
	chunks[chunk_index] = chunk_bytes
	set_pending_snapshot_chunks(chunks)
	var room_code := str(manifest.get("room_code", "")).strip_edges().to_upper()
	var received_count := int(chunks.size())
	var chunk_ratio := float(received_count) / float(maxi(1, chunk_count))
	_emit_local_bootstrap_progress.call(_make_local_bootstrap_progress_state.call(
		room_code,
		"snapshot_download",
		"正在接收恢复快照...",
		"正在接收完整存档快照分片：%d / %d。" % [received_count, chunk_count],
		18.0 + 14.0 * chunk_ratio
	))
	if chunks.size() < chunk_count:
		return

	var assemble_r: Result = ResyncSnapshotTransferClass.assemble_snapshot(manifest, chunks)
	clear_pending_snapshot_state()
	if not assemble_r.ok:
		_emit_delta_failure("snapshot 恢复失败：分片组装失败（%s）" % assemble_r.error)
		return
	var archive: Dictionary = Dictionary(assemble_r.value).duplicate(true)
	set_pending_archive(archive)
	var deferred_resume_payload := Dictionary(_consume_pending_resume_full_snapshot_payload.call(room_code)).duplicate(true)
	if not deferred_resume_payload.is_empty():
		var local_pid := int(_get_pending_resume_full_snapshot_local_pid.call())
		var bootstrap_r: Result = _bootstrap_resume_full_snapshot_archive.call(archive, room_code, local_pid)
		if not bootstrap_r.ok:
			GameLog.error("NetClient", "Resume snapshot bootstrap failed: %s" % bootstrap_r.error)
			_set_pending_resume_full_snapshot_local_pid.call(-1)
			if _net != null and is_instance_valid(_net) and _net.has_signal("match_bootstrap_local_failed"):
				_net.emit_signal("match_bootstrap_local_failed", str(bootstrap_r.error))
			return
		_emit_resume_full_history_ready.call()
		_net.resync_archive_received.emit(archive.duplicate(true))
		_net.game_started.emit(deferred_resume_payload)
		try_apply_pending_delta()
	else:
		_try_bootstrap_online_client_engine_from_archive.call(archive)
		_net.resync_archive_received.emit(archive.duplicate(true))
	GameLog.warn(
		"NetClient",
		"RX ResyncSnapshot assembled transfer_id=%s chunks=%d total_bytes=%d"
			% [
				_safe(transfer_id),
				chunk_count,
				int(manifest.get("total_bytes", -1)),
			]
	)

func handle_delta(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var delta_payload: Dictionary = Dictionary(_translate_resync_delta_to_runtime.call(Dictionary(payload).duplicate(true))).duplicate(true)
	if not bool(_matches_payload_room_code.call(delta_payload, "ResyncDelta")):
		return
	if _get_active_resume_engine.call() == null:
		set_pending_delta(delta_payload)
		GameLog.warn(
			"NetClient",
			"RX ResyncDelta buffered from=%d to=%d entries=%d"
				% [
					int(delta_payload.get("from_sequence", -1)),
					int(delta_payload.get("to_sequence", -1)),
					Array(delta_payload.get("entries", [])).size()
				]
		)
		return
	apply_delta(delta_payload)

func try_apply_pending_delta() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var pending_delta := get_pending_delta()
	if pending_delta.is_empty():
		return
	var engine = _get_active_resume_engine.call()
	if engine == null:
		return
	var payload: Dictionary = pending_delta.duplicate(true)
	set_pending_delta({})
	apply_delta(payload)

func get_pending_archive() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var archive_val = (_net as Object).get("_pending_resync_archive")
	if archive_val is Dictionary:
		return Dictionary(archive_val)
	return {}

func set_pending_archive(archive: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_archive", Dictionary(archive).duplicate(true))

func get_pending_snapshot_manifest() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var manifest_val = (_net as Object).get("_pending_resync_snapshot_manifest")
	if manifest_val is Dictionary:
		return Dictionary(manifest_val)
	return {}

func set_pending_snapshot_manifest(manifest: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_snapshot_manifest", Dictionary(manifest).duplicate(true))

func get_pending_snapshot_chunks() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var chunks_val = (_net as Object).get("_pending_resync_snapshot_chunks")
	if chunks_val is Dictionary:
		return Dictionary(chunks_val)
	return {}

func set_pending_snapshot_chunks(chunks: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_snapshot_chunks", Dictionary(chunks).duplicate(true))

func clear_pending_snapshot_state() -> void:
	set_pending_snapshot_manifest({})
	set_pending_snapshot_chunks({})

func get_pending_delta() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var pending_val = (_net as Object).get("_pending_resync_delta")
	if pending_val is Dictionary:
		return Dictionary(pending_val)
	return {}

func set_pending_delta(payload: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_delta", Dictionary(payload).duplicate(true))

func apply_delta(payload: Dictionary) -> void:
	var engine = _get_active_resume_engine.call()
	if engine == null:
		_emit_delta_failure("delta 恢复失败：当前没有可恢复的 engine")
		return
	var entries_val = payload.get("entries", null)
	if not (entries_val is Array):
		_emit_delta_failure("delta 恢复失败：entries 类型错误")
		return

	var from_sequence := int(payload.get("from_sequence", -1))
	var final_sequence := int(payload.get("final_sequence", payload.get("to_sequence", -1)))
	var final_hash := str(payload.get("final_hash", "")).strip_edges()
	var checkpoint_id := str(payload.get("checkpoint_id", "")).strip_edges()
	var entries: Array = Array(entries_val)
	var current_sequence: int = int(engine.command_history.size())
	var state = engine.get_state()
	var current_hash := str(state.compute_hash()) if state != null and state.has_method("compute_hash") else ""

	if current_sequence != from_sequence:
		if current_sequence == final_sequence and not final_hash.is_empty() and current_hash == final_hash:
			_sync_online_resume_progress.call(engine, checkpoint_id)
			_net.resync_delta_applied.emit({
				"from_sequence": from_sequence,
				"final_sequence": final_sequence,
				"final_hash": final_hash,
				"entry_count": entries.size(),
				"checkpoint_id": checkpoint_id,
			})
			return
		_emit_delta_failure(
			"delta 恢复失败：本地序列与服务端基线不一致（local=%d server=%d）"
				% [current_sequence, from_sequence]
		)
		return

	for item in entries:
		if not (item is Dictionary):
			_emit_delta_failure("delta 恢复失败：entry 类型错误")
			return
		var entry: Dictionary = Dictionary(item)
		var expected_sequence: int = current_sequence + 1
		var entry_sequence := int(entry.get("sequence", -1))
		if entry_sequence != expected_sequence:
			_emit_delta_failure(
				"delta 恢复失败：序列不连续（expected=%d actual=%d）"
					% [expected_sequence, entry_sequence]
			)
			return
		var cmd_val = entry.get("cmd", null)
		if not (cmd_val is Dictionary):
			_emit_delta_failure("delta 恢复失败：cmd 类型错误")
			return
		var parsed: Result = CommandClass.from_dict(Dictionary(cmd_val))
		if not parsed.ok:
			_emit_delta_failure("delta 恢复失败：命令解析失败：%s" % parsed.error)
			return
		var cmd = parsed.value
		if int(cmd.index) != current_sequence:
			_emit_delta_failure(
				"delta 恢复失败：cmd.index 不匹配（expected=%d actual=%d）"
					% [current_sequence, int(cmd.index)]
			)
			return
		var exec_r: Result = engine.execute_command(cmd, true)
		if not exec_r.ok:
			_emit_delta_failure("delta 恢复失败：命令回放失败：%s" % exec_r.error)
			return
		current_sequence = engine.command_history.size()
		state = engine.get_state()
		current_hash = str(state.compute_hash()) if state != null and state.has_method("compute_hash") else ""
		var entry_hash := str(entry.get("post_state_hash", "")).strip_edges()
		if not entry_hash.is_empty() and current_hash != entry_hash:
			_emit_delta_failure(
				"delta 恢复失败：state_hash 不匹配（local=%s server=%s）"
					% [_short(current_hash), _short(entry_hash)]
			)
			return

	if final_sequence >= 0 and current_sequence != final_sequence:
		_emit_delta_failure(
			"delta 恢复失败：最终序列不匹配（local=%d server=%d）"
				% [current_sequence, final_sequence]
		)
		return
	if not final_hash.is_empty() and current_hash != final_hash:
		_emit_delta_failure(
			"delta 恢复失败：最终 hash 不匹配（local=%s server=%s）"
				% [_short(current_hash), _short(final_hash)]
		)
		return

	_sync_online_resume_progress.call(engine, checkpoint_id)
	GameLog.warn(
		"NetClient",
		"RX ResyncDelta applied from=%d to=%d entries=%d final_hash=%s"
			% [from_sequence, current_sequence, entries.size(), _short(current_hash)]
	)
	_net.resync_delta_applied.emit({
		"from_sequence": from_sequence,
		"final_sequence": current_sequence,
		"final_hash": current_hash,
		"entry_count": entries.size(),
		"checkpoint_id": checkpoint_id,
	})

func _emit_delta_failure(message: String) -> void:
	if _net != null and is_instance_valid(_net):
		if _net.has_method("request_resume_force_snapshot_once"):
			_net.request_resume_force_snapshot_once()
		_net.resync_delta_failed.emit(str(message))
	GameLog.warn("NetClient", str(message))

func _safe(value: String) -> String:
	if _safe_text.is_valid():
		return str(_safe_text.call(value))
	var out := str(value).strip_edges()
	return "-" if out.is_empty() else out

func _short(hash_value: String) -> String:
	if _short_hash.is_valid():
		return str(_short_hash.call(hash_value))
	var h := str(hash_value).strip_edges()
	if h.is_empty():
		return "-"
	if h.length() <= 12:
		return h
	return "%s..." % h.substr(0, 12)
