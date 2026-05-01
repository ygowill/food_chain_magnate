extends RefCounted

const ServerLogFormatClass = preload("res://autoload/net_client/server_log_format.gd")
const ServerResyncTransferBuilderClass = preload("res://autoload/net_client/server_resync_transfer_builder.gd")
const ResultClass = preload("res://core/types/result.gd")

const DEFAULT_RESYNC_REQUEST_COOLDOWN_MSEC := 1000
const RESYNC_SNAPSHOT_CHUNK_BUFFER_HEADROOM_RATIO := 0.25
const DEFAULT_RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES := 256 * 1024
const DEFAULT_RESYNC_SNAPSHOT_MAX_CHUNKS := 256
const RESYNC_DELTA_BUFFER_HEADROOM_RATIO := 0.5
const DEFAULT_RESYNC_DELTA_MAX_COMMANDS := 32
const FALLBACK_FORCE_SNAPSHOT := "force_snapshot_requested"
const FALLBACK_CURSOR_MISSING := "cursor_missing"
const FALLBACK_CURSOR_INVALID := "cursor_invalid"
const FALLBACK_CURSOR_HASH_MISMATCH := "cursor_hash_mismatch"
const FALLBACK_DELTA_GAP := "delta_gap"
const FALLBACK_DELTA_TOO_LARGE := "delta_too_large"
const FALLBACK_RECOVERY_STORE_UNHEALTHY := "recovery_store_unhealthy"
const FALLBACK_DELTA_UNAVAILABLE := "delta_unavailable"

var _net = null
var _last_request_msec_by_peer: Dictionary = {} # peer_id -> last accepted resync request msec
var _last_transfer_mode_by_peer: Dictionary = {} # peer_id -> "delta" | "snapshot"

func setup(net_client) -> void:
	_net = net_client

func build_full_snapshot_transfer(room) -> Result:
	return ServerResyncTransferBuilderClass.build_full_snapshot_transfer(
		room,
		_get_snapshot_chunk_size_bytes(),
		_get_snapshot_max_chunks()
	)

func build_archive_snapshot_transfer(
	room_code: String,
	archive: Dictionary,
	history_size: int = -1,
	state_hash: String = ""
) -> Result:
	return ServerResyncTransferBuilderClass.build_archive_snapshot_transfer(
		room_code,
		archive,
		int(history_size),
		state_hash,
		_get_snapshot_chunk_size_bytes(),
		_get_snapshot_max_chunks()
	)

func build_delta_transfer(room, resume_cursor: Dictionary) -> Result:
	return ServerResyncTransferBuilderClass.build_delta_transfer(
		room,
		resume_cursor,
		_get_delta_max_commands(),
		_get_delta_soft_limit_bytes()
	)

func send_prebuilt_snapshot(peer_id: int, request_id: String, room, transfer: Dictionary, source: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var manifest: Dictionary = Dictionary(transfer.get("manifest", {})).duplicate(true)
	manifest["request_id"] = request_id
	_net.rpc_id(peer_id, "rpc_resync_snapshot_manifest", manifest)
	for chunk_val in Array(transfer.get("chunks", [])):
		if not (chunk_val is Dictionary):
			continue
		_net.rpc_id(peer_id, "rpc_resync_snapshot_chunk", Dictionary(chunk_val).duplicate(true))
	GameLog.warn(
		"NetClient",
		"TX ResyncSnapshot source=%s %s %s history_size=%d state_hash=%s total_bytes=%d chunks=%d"
			% [
				ServerLogFormatClass.safe_text(source),
				ServerLogFormatClass.request_tag(peer_id, request_id),
				ServerLogFormatClass.room_brief(room),
				int(transfer.get("history_size", -1)),
				ServerLogFormatClass.short_hash(str(transfer.get("state_hash", ""))),
				int(transfer.get("payload_bytes", -1)),
				int(transfer.get("chunk_count", -1)),
			]
	)

func send_prebuilt_delta(peer_id: int, request_id: String, room, transfer: Dictionary, source: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var payload: Dictionary = Dictionary(transfer.get("payload", {})).duplicate(true)
	payload["request_id"] = request_id
	_net.rpc_id(peer_id, "rpc_resync_delta", payload)
	GameLog.warn(
		"NetClient",
		"TX ResyncDelta source=%s %s %s from=%d to=%d entries=%d final_hash=%s payload_bytes=%d"
			% [
				ServerLogFormatClass.safe_text(source),
				ServerLogFormatClass.request_tag(peer_id, request_id),
				ServerLogFormatClass.room_brief(room),
				int(transfer.get("from_sequence", -1)),
				int(transfer.get("to_sequence", -1)),
				int(transfer.get("entry_count", -1)),
				ServerLogFormatClass.short_hash(str(transfer.get("final_hash", ""))),
				int(transfer.get("payload_bytes", -1)),
			]
	)

func build_best_effort_resume_transfer(room, resume_cursor: Dictionary = {}) -> Result:
	var cursor: Dictionary = Dictionary(resume_cursor).duplicate(true)
	var force_snapshot := bool(cursor.get("force_snapshot", false))
	var fallback_reason := ""
	var fallback_reason_code := ""
	if force_snapshot:
		fallback_reason_code = FALLBACK_FORCE_SNAPSHOT
	elif cursor.is_empty():
		fallback_reason_code = FALLBACK_CURSOR_MISSING
	else:
		var delta_r: Result = build_delta_transfer(room, cursor)
		if delta_r.ok:
			return ResultClass.success({
				"mode": "delta",
				"transfer": Dictionary(delta_r.value).duplicate(true),
			})
		fallback_reason = str(delta_r.error)
		fallback_reason_code = _classify_delta_fallback_reason(fallback_reason)
	var snapshot_r: Result = build_full_snapshot_transfer(room)
	if not snapshot_r.ok:
		return snapshot_r
	return ResultClass.success({
		"mode": "snapshot",
		"transfer": Dictionary(snapshot_r.value).duplicate(true),
		"fallback_reason": fallback_reason,
		"fallback_reason_code": fallback_reason_code,
	})

func dispatch_prepared_transfer(
	peer_id: int,
	request_id: String,
	room,
	prepared_transfer: Dictionary,
	source: String
) -> Result:
	var mode := str(prepared_transfer.get("mode", "")).strip_edges()
	var transfer: Dictionary = Dictionary(prepared_transfer.get("transfer", {})).duplicate(true)
	if mode == "delta":
		send_prebuilt_delta(peer_id, request_id, room, transfer, source)
		return ResultClass.success({"mode": "delta"})
	if mode == "snapshot":
		var fallback_reason := str(prepared_transfer.get("fallback_reason", "")).strip_edges()
		var fallback_reason_code := str(prepared_transfer.get("fallback_reason_code", "")).strip_edges()
		if not fallback_reason.is_empty() or not fallback_reason_code.is_empty():
			var log_message := "Resume delta unavailable source=%s %s class=%s reason=%s" % [
				ServerLogFormatClass.safe_text(source),
				ServerLogFormatClass.request_tag(peer_id, request_id),
				ServerLogFormatClass.safe_text(fallback_reason_code),
				ServerLogFormatClass.safe_text(fallback_reason),
			]
			if fallback_reason_code == FALLBACK_RECOVERY_STORE_UNHEALTHY:
				GameLog.error("NetClient", log_message)
			else:
				GameLog.info("NetClient", log_message)
		send_prebuilt_snapshot(peer_id, request_id, room, transfer, source)
		return ResultClass.success({
			"mode": "snapshot",
			"fallback_reason_code": fallback_reason_code,
		})
	return ResultClass.failure("resume transfer mode invalid: %s" % mode)

static func _classify_delta_fallback_reason(reason: String) -> String:
	var text := str(reason).strip_edges().to_lower()
	if text.is_empty():
		return FALLBACK_DELTA_UNAVAILABLE
	if text.find("recovery store unhealthy") >= 0:
		return FALLBACK_RECOVERY_STORE_UNHEALTHY
	if text.find("hash mismatch") >= 0:
		return FALLBACK_CURSOR_HASH_MISMATCH
	if text.find("sequence invalid") >= 0:
		return FALLBACK_CURSOR_INVALID
	if text.find("cursor missing") >= 0:
		return FALLBACK_CURSOR_MISSING
	if text.find("delta gap") >= 0 or text.find("delta incomplete") >= 0:
		return FALLBACK_DELTA_GAP
	if text.find("too long") >= 0 or text.find("too large") >= 0:
		return FALLBACK_DELTA_TOO_LARGE
	return FALLBACK_DELTA_UNAVAILABLE

func send_best_effort_resume_transfer(
	peer_id: int,
	request_id: String,
	room,
	source: String,
	resume_cursor: Dictionary = {}
) -> Result:
	var prepared_r: Result = build_best_effort_resume_transfer(room, resume_cursor)
	if not prepared_r.ok:
		return prepared_r
	return dispatch_prepared_transfer(
		peer_id,
		request_id,
		room,
		Dictionary(prepared_r.value),
		source
	)

func is_request_rate_limited(peer_id: int, force_snapshot: bool = false) -> bool:
	var cooldown_msec := _get_request_cooldown_msec()
	if cooldown_msec <= 0:
		_last_request_msec_by_peer[peer_id] = int(Time.get_ticks_msec())
		return false
	var now_msec := int(Time.get_ticks_msec())
	var last_msec := int(_last_request_msec_by_peer.get(peer_id, 0))
	if last_msec > 0 and now_msec - last_msec < cooldown_msec:
		var last_mode := str(_last_transfer_mode_by_peer.get(peer_id, "")).strip_edges()
		if not force_snapshot or last_mode != "delta":
			return true
	_last_request_msec_by_peer[peer_id] = now_msec
	return false

func remember_transfer_mode(peer_id: int, mode: String) -> void:
	var normalized_mode := str(mode).strip_edges()
	if normalized_mode.is_empty():
		_last_transfer_mode_by_peer.erase(peer_id)
		return
	_last_transfer_mode_by_peer[peer_id] = normalized_mode

func forget_peer(peer_id: int) -> void:
	_last_request_msec_by_peer.erase(peer_id)
	_last_transfer_mode_by_peer.erase(peer_id)

func _get_request_cooldown_msec() -> int:
	var raw := str(OS.get_environment("RESYNC_REQUEST_COOLDOWN_MSEC")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(0, int(raw))
	return DEFAULT_RESYNC_REQUEST_COOLDOWN_MSEC

func _get_snapshot_chunk_size_bytes() -> int:
	var buffer_size := _get_outbound_buffer_size_or_default()
	var hard_cap := maxi(64, int(floor(float(buffer_size) * RESYNC_SNAPSHOT_CHUNK_BUFFER_HEADROOM_RATIO)))
	var raw := str(OS.get_environment("RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return clampi(int(raw), 64, hard_cap)
	return mini(DEFAULT_RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES, hard_cap)

func _get_snapshot_max_chunks() -> int:
	var raw := str(OS.get_environment("RESYNC_SNAPSHOT_MAX_CHUNKS")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(1, int(raw))
	return DEFAULT_RESYNC_SNAPSHOT_MAX_CHUNKS

func _get_delta_soft_limit_bytes() -> int:
	var buffer_size := _get_outbound_buffer_size_or_default()
	return maxi(1024, int(floor(float(buffer_size) * RESYNC_DELTA_BUFFER_HEADROOM_RATIO)))

func _get_delta_max_commands() -> int:
	var raw := str(OS.get_environment("RESYNC_DELTA_MAX_COMMANDS")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(0, int(raw))
	return DEFAULT_RESYNC_DELTA_MAX_COMMANDS

func _get_outbound_buffer_size_or_default() -> int:
	var buffer_size := 0
	if _net != null and is_instance_valid(_net) and _net is Object:
		var peer = (_net as Object).get("_peer")
		if peer != null and peer is Object:
			buffer_size = int((peer as Object).get("outbound_buffer_size"))
	if buffer_size <= 0:
		buffer_size = 4 * 1024 * 1024
	return buffer_size
