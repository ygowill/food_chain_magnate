# Online：ClientHello 必须携带 connect_token（当 NetContext.connect_token 非空）
class_name OnlineClientHelloConnectTokenTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

	NetContext.player_profile = {"name": "P1", "color_index": 0, "restaurant_logo_id": -1}
	var prev_engine = Globals.current_game_engine

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)

	# Case A: no token → payload should NOT include connect_token
	NetContext.connect_token = ""
	client.send_client_hello()
	if mock_net.last_method != "rpc_client_hello":
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("ClientHello 未发送: method=%s" % str(mock_net.last_method))
	if mock_net.last_payload.has("connect_token"):
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("connect_token 为空时不应发送 connect_token 字段")

	# Case B: token present → payload MUST include connect_token
	NetContext.connect_token = "tok_123"
	client.send_client_hello()
	if not mock_net.last_payload.has("connect_token"):
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("connect_token 非空时应发送 connect_token 字段")
	if str(mock_net.last_payload.get("connect_token", "")) != "tok_123":
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("connect_token 值不一致: %s" % str(mock_net.last_payload.get("connect_token", null)))

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("测试 engine 初始化失败: %s" % init_r.error)
	Globals.set_current_game_engine(engine)
	NetContext.set_online_resume_context("ROOM01", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_resume_progress(0, "hash_before_hello", "cp_test")
	mock_net._resume_force_snapshot_once = true
	client.send_client_hello()
	if not mock_net.last_payload.has("resume_cursor"):
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("联机恢复场景下 ClientHello 应携带 resume_cursor")
	var resume_cursor: Dictionary = Dictionary(mock_net.last_payload.get("resume_cursor", {}))
	if int(resume_cursor.get("last_applied_sequence", -1)) != 0:
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("resume_cursor.last_applied_sequence 错误: %s" % str(resume_cursor))
	if str(resume_cursor.get("checkpoint_id", "")) != "cp_test":
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("resume_cursor.checkpoint_id 错误: %s" % str(resume_cursor))
	if not bool(resume_cursor.get("force_snapshot", false)):
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("一次性 force_snapshot 标记应透传到 ClientHello")
	if mock_net._resume_force_snapshot_once:
		_reset_net_context()
		Globals.current_game_engine = prev_engine
		return Result.failure("ClientHello 发送后应消费掉一次性 force_snapshot 标记")

	_reset_net_context()
	Globals.current_game_engine = prev_engine
	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

class _MockNet:
	extends RefCounted

	var last_peer_id: int = -1
	var last_method: String = ""
	var last_payload: Dictionary = {}
	var _counter: int = 0
	var _resume_force_snapshot_once: bool = false

	func _next_request_id() -> String:
		_counter += 1
		return "req_%d" % _counter

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		last_peer_id = int(peer_id)
		last_method = str(method)
		last_payload = payload.duplicate(true)
