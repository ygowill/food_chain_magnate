# Online client：resync/rewind payload 必须与当前房间一致，避免旧房间数据串入新会话
class_name OnlineClientResyncRoomIsolationTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode := NetContext.mode
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "ISO01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.connect_token = ""
	NetContext.online_resume_state = {}

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)

	client.handle_rpc_rewind_to_turn_start_meta({
		"request_id": "rewind_wrong_room",
		"room_code": "ISO02",
		"target_index": 1,
		"before_index": 3,
		"history_size": 2,
		"state_hash": "hash_wrong_room",
		"noop": false,
	})
	if not mock_net.rewind_meta_payloads.is_empty():
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("wrong-room rewind meta 不应透传: %s" % str(mock_net.rewind_meta_payloads))
	if not mock_net._pending_rewind_to_turn_start_meta.is_empty():
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("wrong-room rewind meta 不应缓存")

	client.handle_rpc_resync_snapshot_manifest({
		"request_id": "snapshot_wrong_room",
		"room_code": "ISO02",
		"transfer_id": "iso_transfer_wrong",
		"chunk_count": 2,
		"chunk_size": 64,
		"total_bytes": 128,
		"archive_hash": "hash_wrong_room",
	})
	if not mock_net._pending_resync_snapshot_manifest.is_empty():
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("wrong-room snapshot manifest 不应缓存")

	client.handle_rpc_resync_delta({
		"request_id": "delta_wrong_room",
		"room_code": "ISO02",
		"checkpoint_id": "cp_wrong_room",
		"from_sequence": 0,
		"to_sequence": 0,
		"final_sequence": 0,
		"final_hash": "",
		"entries": [],
	})
	if not mock_net._pending_resync_delta.is_empty():
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("wrong-room delta 不应缓存")
	if not mock_net.delta_applied_payloads.is_empty() or not mock_net.delta_failures.is_empty():
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("wrong-room delta 不应触发回放事件")

	NetContext.room_state = {}
	NetContext.connect_token = _build_connect_token_hint("TOKEN01")

	client.handle_rpc_resync_snapshot_manifest({
		"request_id": "snapshot_right_room",
		"room_code": "TOKEN01",
		"transfer_id": "iso_transfer_right",
		"chunk_count": 2,
		"chunk_size": 64,
		"total_bytes": 128,
		"archive_hash": "hash_right_room",
	})
	if str(mock_net._pending_resync_snapshot_manifest.get("room_code", "")) != "TOKEN01":
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("connect_token hint 未允许正确房间 snapshot manifest")

	client.handle_rpc_rewind_to_turn_start_meta({
		"request_id": "rewind_right_room",
		"room_code": "TOKEN01",
		"target_index": 0,
		"before_index": 1,
		"history_size": 1,
		"state_hash": "hash_right_room",
		"noop": true,
	})
	if mock_net.rewind_meta_payloads.size() != 1:
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("connect_token hint 未允许正确房间 rewind meta")

	client.handle_rpc_resync_delta({
		"request_id": "delta_right_room",
		"room_code": "TOKEN01",
		"checkpoint_id": "cp_right_room",
		"from_sequence": 0,
		"to_sequence": 0,
		"final_sequence": 0,
		"final_hash": "",
		"entries": [],
	})
	if str(mock_net._pending_resync_delta.get("room_code", "")) != "TOKEN01":
		_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
		return Result.failure("connect_token hint 未允许正确房间 delta")

	_restore(prev_mode, prev_room_state, prev_connect_token, prev_resume_state)
	return Result.success()

static func _build_connect_token_hint(room_code: String) -> String:
	var payload := {"room_code": str(room_code).strip_edges().to_upper()}
	var encoded := Marshalls.raw_to_base64(JSON.stringify(payload).to_utf8_buffer())
	encoded = encoded.replace("+", "-").replace("/", "_")
	return "%s.signature" % encoded

static func _restore(
	prev_mode,
	prev_room_state: Dictionary,
	prev_connect_token: String,
	prev_resume_state: Dictionary
) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.connect_token = prev_connect_token
	NetContext.online_resume_state = prev_resume_state.duplicate(true)

class _MockNet:
	extends RefCounted

	signal rewind_to_turn_start_meta_received(payload: Dictionary)
	signal resync_delta_applied(payload: Dictionary)
	signal resync_delta_failed(message: String)

	var _pending_rewind_to_turn_start_meta: Dictionary = {}
	var _pending_resync_snapshot_manifest: Dictionary = {}
	var _pending_resync_snapshot_chunks: Dictionary = {}
	var _pending_resync_delta: Dictionary = {}
	var rewind_meta_payloads: Array[Dictionary] = []
	var delta_applied_payloads: Array[Dictionary] = []
	var delta_failures: Array[String] = []

	func _init() -> void:
		rewind_to_turn_start_meta_received.connect(func(payload: Dictionary) -> void:
			rewind_meta_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_delta_applied.connect(func(payload: Dictionary) -> void:
			delta_applied_payloads.append(Dictionary(payload).duplicate(true))
		)
		resync_delta_failed.connect(func(message: String) -> void:
			delta_failures.append(str(message))
		)
