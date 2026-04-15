# 联机开局 bootstrap：服务器应等待全员 ready 后再 commit，并在客户端失败时回滚 Lobby。
class_name OnlineMatchBootstrapServerFlowTest
extends RefCounted

const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	var wait_r: Result = _run_waits_for_all_ready_scenario()
	if not wait_r.ok:
		_reset_net_context()
		return wait_r
	var fail_r: Result = _run_failed_client_aborts_scenario()
	_reset_net_context()
	return fail_r

static func _run_waits_for_all_ready_scenario() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var fixture: Result = _create_fixture(7001)
	if not fixture.ok:
		return fixture
	var ctx: Dictionary = Dictionary(fixture.value)
	var server = ctx.get("server", null)
	var room = ctx.get("room", null)
	var mock_net = ctx.get("mock_net", null)
	if server == null or room == null or mock_net == null:
		return Result.failure("开局 bootstrap 测试 fixture 缺少 server/room/mock_net")

	mock_net.multiplayer.remote_sender_id = 10
	server.handle_rpc_start_game({"request_id": "r_start"})

	if _find_request_rejected(mock_net.sent, 10, "r_start", "start_game_failed") >= 0:
		return Result.failure("正常开局不应返回 start_game_failed")
	if str(room.status) != "Starting":
		return Result.failure("开局请求后房间应进入 Starting: %s" % str(room.status))
	if room.game_engine != null:
		return Result.failure("全员 ready 之前不应提前 commit game_engine")
	if not room.has_method("has_pending_start_session") or not room.has_pending_start_session():
		return Result.failure("开局请求后应存在 pending start session")
	var bootstrap_summary: Dictionary = room.get_pending_start_summary() if room.has_method("get_pending_start_summary") else {}
	if int(Dictionary(bootstrap_summary).get("total_count", 0)) != 2:
		return Result.failure("bootstrap total_count 错误: %s" % str(bootstrap_summary))
	if int(Dictionary(bootstrap_summary).get("ready_count", -1)) != 0:
		return Result.failure("bootstrap 初始 ready_count 应为 0: %s" % str(bootstrap_summary))
	var bootstrap_id := str(Dictionary(bootstrap_summary).get("id", "")).strip_edges()
	if bootstrap_id.is_empty():
		return Result.failure("开局请求后 bootstrap_id 为空")
	if _find_sent_method(mock_net.sent, 10, "rpc_game_started") < 0 or _find_sent_method(mock_net.sent, 11, "rpc_game_started") < 0:
		return Result.failure("开局准备完成后双方都应收到 rpc_game_started")

	mock_net.multiplayer.remote_sender_id = 10
	server.handle_rpc_match_bootstrap_ready({
		"request_id": "r_ready_host",
		"bootstrap_id": bootstrap_id,
	})

	if str(room.status) != "Starting":
		return Result.failure("仅房主 ready 后房间仍应保持 Starting: %s" % str(room.status))
	var host_ready_summary: Dictionary = room.get_pending_start_summary() if room.has_method("get_pending_start_summary") else {}
	if int(Dictionary(host_ready_summary).get("ready_count", -1)) != 1:
		return Result.failure("房主 ready 后 ready_count 应为 1: %s" % str(host_ready_summary))
	var host_room_state := _get_last_sent_payload(mock_net.sent, 10, "rpc_room_state")
	var player_room_state := _get_last_sent_payload(mock_net.sent, 11, "rpc_room_state")
	var host_bootstrap := Dictionary(host_room_state.get("bootstrap", {})).duplicate(true)
	var player_bootstrap := Dictionary(player_room_state.get("bootstrap", {})).duplicate(true)
	if not bool(host_bootstrap.get("self_ready", false)):
		return Result.failure("房主 ready 后，房主侧 room_state.bootstrap.self_ready 应为 true")
	if bool(player_bootstrap.get("self_ready", false)):
		return Result.failure("房主 ready 后，玩家侧 room_state.bootstrap.self_ready 应保持 false")

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_match_bootstrap_ready({
		"request_id": "r_ready_player",
		"bootstrap_id": bootstrap_id,
	})

	if str(room.status) != "InGame":
		return Result.failure("全员 ready 后房间应进入 InGame: %s" % str(room.status))
	if room.has_method("has_pending_start_session") and room.has_pending_start_session():
		return Result.failure("commit 后不应仍保留 pending start session")
	if room.game_engine == null or room.game_engine.get_state() == null:
		return Result.failure("commit 后应存在 game_engine/state")
	var final_room_state := _get_last_sent_payload(mock_net.sent, 10, "rpc_room_state")
	if str(final_room_state.get("status", "")).strip_edges() != "InGame":
		return Result.failure("commit 后最后一次 room_state 广播应为 InGame: %s" % str(final_room_state))
	if final_room_state.has("bootstrap"):
		return Result.failure("commit 后 room_state 不应继续携带 bootstrap")

	return Result.success()

static func _run_failed_client_aborts_scenario() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var fixture: Result = _create_fixture(7002)
	if not fixture.ok:
		return fixture
	var ctx: Dictionary = Dictionary(fixture.value)
	var server = ctx.get("server", null)
	var room = ctx.get("room", null)
	var mock_net = ctx.get("mock_net", null)
	if server == null or room == null or mock_net == null:
		return Result.failure("bootstrap 失败回滚测试 fixture 缺少 server/room/mock_net")

	mock_net.multiplayer.remote_sender_id = 10
	server.handle_rpc_start_game({"request_id": "r_start"})

	if str(room.status) != "Starting":
		return Result.failure("失败回滚场景中，开局请求后房间应先进入 Starting: %s" % str(room.status))
	var bootstrap_summary: Dictionary = room.get_pending_start_summary() if room.has_method("get_pending_start_summary") else {}
	var bootstrap_id := str(Dictionary(bootstrap_summary).get("id", "")).strip_edges()
	if bootstrap_id.is_empty():
		return Result.failure("失败回滚场景缺少 bootstrap_id")

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_match_bootstrap_failed({
		"request_id": "r_failed_player",
		"bootstrap_id": bootstrap_id,
		"reason": "客户端初始化失败",
	})

	if str(room.status) != "Lobby":
		return Result.failure("客户端初始化失败后房间应回滚到 Lobby: %s" % str(room.status))
	if room.has_method("has_pending_start_session") and room.has_pending_start_session():
		return Result.failure("失败回滚后不应仍保留 pending start session")
	if room.game_engine != null:
		return Result.failure("失败回滚后不应保留 game_engine")
	if _find_request_rejected(mock_net.sent, 10, "r_start", "match_bootstrap_failed") < 0:
		return Result.failure("失败回滚后房主应收到 match_bootstrap_failed，且 request_id 应沿用 r_start")
	if _find_request_rejected(mock_net.sent, 11, "r_start", "match_bootstrap_failed") < 0:
		return Result.failure("失败回滚后玩家应收到 match_bootstrap_failed，且 request_id 应沿用 r_start")
	var room_state_after_abort := _get_last_sent_payload(mock_net.sent, 10, "rpc_room_state")
	if str(room_state_after_abort.get("status", "")).strip_edges() != "Lobby":
		return Result.failure("失败回滚后最后一次 room_state 应为 Lobby: %s" % str(room_state_after_abort))
	if room_state_after_abort.has("bootstrap"):
		return Result.failure("失败回滚后 room_state 不应继续携带 bootstrap")
	var ready_r: Result = room.can_start_game()
	if not ready_r.ok:
		return Result.failure("失败回滚后房间应仍可再次开始游戏: %s" % ready_r.error)

	return Result.success()

static func _create_fixture(seed: int) -> Result:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rm = RoomManagerClass.new(rng)
	var mock_net := _MockNetClient.new(rm)
	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var config := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}
	var create_r: Result = rm.create_room(10, {"name": "Host", "color_index": 1, "restaurant_logo_id": 0}, "pw", config)
	if not create_r.ok:
		return Result.failure("create_room 失败: %s" % create_r.error)
	var room_val = Dictionary(create_r.value).get("room", null)
	var room_code := str(Dictionary(create_r.value).get("room_code", "")).strip_edges()
	if room_val == null or room_code.is_empty():
		return Result.failure("create_room 未返回 room/room_code")
	var join_r: Result = rm.join_room(11, {"name": "P2", "color_index": 2, "restaurant_logo_id": 1}, room_code, "pw")
	if not join_r.ok:
		return Result.failure("join_room 失败: %s" % join_r.error)
	return Result.success({
		"room_manager": rm,
		"mock_net": mock_net,
		"server": server,
		"room": room_val,
		"room_code": room_code,
	})

static func _get_last_sent_payload(sent: Array[Dictionary], peer_id: int, method: String) -> Dictionary:
	for i in range(sent.size() - 1, -1, -1):
		var item: Dictionary = Dictionary(sent[i])
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != str(method):
			continue
		var payload_val = item.get("payload", null)
		if not (payload_val is Dictionary):
			return {}
		return Dictionary(payload_val).duplicate(true)
	return {}

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

	var outbound_buffer_size: int = 16 * 1024 * 1024

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var sent: Array[Dictionary] = []
	var _peer = _MockPeer.new()
	var dirty_count: int = 0

	func _init(room_manager) -> void:
		_room_manager = room_manager

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": Dictionary(payload).duplicate(true),
		})

	func mark_server_room_directory_dirty() -> void:
		dirty_count += 1
