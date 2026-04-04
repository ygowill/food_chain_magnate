class_name ServerResyncGuardTest
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var oversize_r := _run_oversize_archive_case()
	if not oversize_r.ok:
		_reset_net_context()
		return oversize_r

	var delta_r := _run_delta_case()
	if not delta_r.ok:
		_reset_net_context()
		return delta_r

	var rewind_meta_r := _run_rewind_meta_case()
	if not rewind_meta_r.ok:
		_reset_net_context()
		return rewind_meta_r

	var rate_limit_r := _run_rate_limit_case()
	_reset_net_context()
	if not rate_limit_r.ok:
		return rate_limit_r
	return Result.success()

static func _run_oversize_archive_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 128)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({"request_id": "req_oversize"})

	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") != -1:
		return Result.failure("超限 snapshot manifest 不应被发送")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") != -1:
		return Result.failure("超限 snapshot chunk 不应被发送")
	var reject_idx := _find_request_rejected(mock_net.sent, 11, "req_oversize", "resync_archive_too_large")
	if reject_idx < 0:
		return Result.failure("超限 archive 应返回 resync_archive_too_large，实际=%s" % str(mock_net.sent))
	return Result.success()

static func _run_rate_limit_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({"request_id": "req_ok"})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("首次 ResyncRequest 应发送 snapshot manifest")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("首次 ResyncRequest 应发送 snapshot chunk")
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("snapshot 主链路不应再发送旧 rpc_resync_archive")

	var before_count := mock_net.sent.size()
	server.handle_rpc_resync_request({"request_id": "req_rate_limit"})
	if mock_net.sent.size() <= before_count:
		return Result.failure("重复 ResyncRequest 应返回限流拒绝")
	var reject_idx := _find_request_rejected(mock_net.sent, 11, "req_rate_limit", "resync_rate_limited")
	if reject_idx < 0:
		return Result.failure("重复 ResyncRequest 应返回 resync_rate_limited，实际=%s" % str(mock_net.sent))
	return Result.success()

static func _run_delta_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null:
		return Result.failure("delta case 缺少 room")
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var initial_hash := ""
	if room.has_method("get_resume_cursor"):
		var cursor0: Dictionary = room.get_resume_cursor()
		initial_hash = str(cursor0.get("last_state_hash", ""))
	if initial_hash.is_empty():
		return Result.failure("delta case 缺少初始 checkpoint hash")

	var actor := int(room.game_engine.get_state().get_current_player_id())
	var cmd := CommandClass.create("select_reserve_card", actor, {"selected_index": 0})
	var exec_r: Result = room.game_engine.execute_command(cmd)
	if not exec_r.ok:
		return Result.failure("delta case 执行命令失败: %s" % exec_r.error)
	server.broadcast_command_applied(room, cmd)
	mock_net.sent.clear()

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_resync_request({
		"request_id": "req_delta",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": initial_hash,
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_delta") < 0:
		return Result.failure("匹配 cursor 时应优先发送 rpc_resync_delta，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") >= 0:
		return Result.failure("匹配 cursor 时不应回退到 snapshot archive")

	mock_net.sent.clear()
	server.handle_rpc_resync_request({
		"request_id": "req_force_snapshot",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": initial_hash,
			"force_snapshot": true,
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("force_snapshot 时应允许立即回退到 snapshot manifest，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("force_snapshot 时应允许立即发送 snapshot chunk，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("force_snapshot fallback 不应再发送旧 rpc_resync_archive")
	if _find_request_rejected(mock_net.sent, 11, "req_force_snapshot", "resync_rate_limited") >= 0:
		return Result.failure("force_snapshot fallback 不应被 resync_rate_limited 拒绝")

	server._last_resync_request_msec_by_peer.erase(11)
	mock_net.sent.clear()
	server.handle_rpc_resync_request({
		"request_id": "req_snapshot_fallback",
		"resume_cursor": {
			"checkpoint_id": "cp_initial",
			"last_applied_sequence": 0,
			"last_state_hash": "mismatched_hash",
		},
	})
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_manifest") < 0:
		return Result.failure("hash 不匹配时应回退到 snapshot manifest，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_snapshot_chunk") < 0:
		return Result.failure("hash 不匹配时应发送 snapshot chunk，实际=%s" % str(mock_net.sent))
	if _find_sent_method(mock_net.sent, 11, "rpc_resync_archive") >= 0:
		return Result.failure("hash 不匹配 fallback 不应再发送旧 rpc_resync_archive")
	return Result.success()

static func _run_rewind_meta_case() -> Result:
	var setup_r := _build_in_game_room_setup()
	if not setup_r.ok:
		return setup_r
	var setup: Dictionary = Dictionary(setup_r.value)
	var room = setup.get("room", null)
	if room == null:
		return Result.failure("rewind meta case 缺少 room")
	var mock_net := _MockNetClient.new(setup.get("room_manager", null), 16 * 1024 * 1024)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var state = room.game_engine.get_state()
	if state == null:
		return Result.failure("rewind meta case 缺少 state")
	var current_actor := int(state.get_current_player_id())
	var peer_id := -1
	for peer_key in Dictionary(room.player_id_by_peer_id).keys():
		if int(room.player_id_by_peer_id.get(peer_key, -1)) != current_actor:
			continue
		peer_id = int(peer_key)
		break
	if peer_id <= 0:
		return Result.failure("rewind meta case 找不到当前玩家 peer actor=%d map=%s" % [current_actor, str(room.player_id_by_peer_id)])
	mock_net.multiplayer.remote_sender_id = peer_id
	server.handle_rpc_rewind_to_turn_start({"request_id": "req_rewind"})

	for target_peer_id in Array(room.get_peer_ids()):
		var pid := int(target_peer_id)
		if _find_sent_method(mock_net.sent, pid, "rpc_rewind_to_turn_start_meta") < 0:
			return Result.failure("rewind 应广播 rpc_rewind_to_turn_start_meta 给 peer=%d: %s" % [pid, str(mock_net.sent)])
		if _find_sent_method(mock_net.sent, pid, "rpc_resync_archive") >= 0:
			return Result.failure("rewind 元数据不应再复用旧 rpc_resync_archive: %s" % str(mock_net.sent))

	for item in mock_net.sent:
		var sent_item: Dictionary = Dictionary(item)
		if str(sent_item.get("method", "")) != "rpc_rewind_to_turn_start_meta":
			continue
		var payload_val = sent_item.get("payload", null)
		if not (payload_val is Dictionary):
			return Result.failure("rewind meta payload 类型错误: %s" % str(sent_item))
		var payload: Dictionary = Dictionary(payload_val)
		if payload.has("archive"):
			return Result.failure("rewind meta payload 不应再包在 archive 字段内: %s" % str(payload))
		if str(payload.get("request_id", "")) != "req_rewind":
			return Result.failure("rewind meta request_id 错误: %s" % str(payload))
	return Result.success()

static func _build_in_game_room_setup() -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var room_manager = RoomManagerClass.new(rng)
	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var host_profile := {
		"name": "Host",
		"color_index": 0,
		"restaurant_logo_id": -1,
		"user_id": "u_host_resync_guard",
	}
	var create_r: Result = room_manager.create_room(10, host_profile, "", config)
	if not create_r.ok:
		return Result.failure("create_room 失败: %s" % create_r.error)
	var create_payload: Dictionary = Dictionary(create_r.value)
	var room_code := str(create_payload.get("room_code", "")).strip_edges().to_upper()
	var room = create_payload.get("room", null)
	if room == null:
		return Result.failure("create_room 返回缺少 room")

	var join_r: Result = room_manager.join_room(11, {
		"name": "P2",
		"color_index": 1,
		"restaurant_logo_id": -1,
		"user_id": "u_p2_resync_guard",
	}, room_code, "")
	if not join_r.ok:
		return Result.failure("join_room 失败: %s" % join_r.error)

	var start_r: Result = room.start_game()
	if not start_r.ok:
		return Result.failure("start_game 失败: %s" % start_r.error)

	return Result.success({
		"room_manager": room_manager,
		"room": room,
		"room_code": room_code,
	})

static func _find_sent_method(sent: Array[Dictionary], peer_id: int, method: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		return i
	return -1

static func _find_request_rejected(sent: Array[Dictionary], peer_id: int, request_id: String, code: String) -> int:
	for i in range(sent.size()):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_request_rejected":
			continue
		var payload_val = item.get("payload", null)
		if not (payload_val is Dictionary):
			continue
		var payload: Dictionary = Dictionary(payload_val)
		if str(payload.get("request_id", "")) != str(request_id):
			continue
		if str(payload.get("code", "")) != str(code):
			continue
		return i
	return -1

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

class _MockMultiplayer:
	extends RefCounted

	var remote_sender_id: int = 0

	func get_remote_sender_id() -> int:
		return int(remote_sender_id)

class _MockPeer:
	extends RefCounted

	var outbound_buffer_size: int = 0

	func _init(buffer_size: int) -> void:
		outbound_buffer_size = int(buffer_size)

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var _peer = null
	var sent: Array[Dictionary] = []

	func _init(room_manager, buffer_size: int) -> void:
		_room_manager = room_manager
		_peer = _MockPeer.new(buffer_size)

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})
