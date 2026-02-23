# Online：ClientHello 必须携带 connect_token（当 NetContext.connect_token 非空）
class_name OnlineClientHelloConnectTokenTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	NetContext.player_profile = {"name": "P1", "color_index": 0, "restaurant_logo_id": -1}

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)

	# Case A: no token → payload should NOT include connect_token
	NetContext.connect_token = ""
	client.send_client_hello()
	if mock_net.last_method != "rpc_client_hello":
		_reset_net_context()
		return Result.failure("ClientHello 未发送: method=%s" % str(mock_net.last_method))
	if mock_net.last_payload.has("connect_token"):
		_reset_net_context()
		return Result.failure("connect_token 为空时不应发送 connect_token 字段")

	# Case B: token present → payload MUST include connect_token
	NetContext.connect_token = "tok_123"
	client.send_client_hello()
	if not mock_net.last_payload.has("connect_token"):
		_reset_net_context()
		return Result.failure("connect_token 非空时应发送 connect_token 字段")
	if str(mock_net.last_payload.get("connect_token", "")) != "tok_123":
		_reset_net_context()
		return Result.failure("connect_token 值不一致: %s" % str(mock_net.last_payload.get("connect_token", null)))

	_reset_net_context()
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

	func _next_request_id() -> String:
		_counter += 1
		return "req_%d" % _counter

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		last_peer_id = int(peer_id)
		last_method = str(method)
		last_payload = payload.duplicate(true)

