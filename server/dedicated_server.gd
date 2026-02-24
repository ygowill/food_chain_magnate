# Dedicated Server 入口（Headless）
extends Node

const DEFAULT_PORT := 7000
const DEFAULT_BIND_ADDRESS := "0.0.0.0"
const DEFAULT_PLATFORM_BACKEND_URL := "http://127.0.0.1:8000"
const DEFAULT_INTERNAL_API_SECRET := "dev-internal-secret-change-in-production"
const HEARTBEAT_INTERVAL_SEC := 15.0

var _backend_url: String = ""
var _internal_api_secret: String = ""
var _game_server_id: String = ""
var _heartbeat_in_flight: bool = false
var _heartbeat_timer: Timer = null

func _ready() -> void:
	var port := DEFAULT_PORT
	var bind_address := DEFAULT_BIND_ADDRESS

	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := str(args[i])
		if a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif a.begins_with("--port="):
			port = int(a.split("=", false, 1)[1])
		elif a == "--bind" and i + 1 < args.size():
			bind_address = str(args[i + 1]).strip_edges()
		elif a.begins_with("--bind="):
			bind_address = str(a.split("=", false, 1)[1]).strip_edges()

	var r: Result = NetClient.start_server(port, bind_address)
	if not r.ok:
		GameLog.error("DedicatedServer", r.error)
		get_tree().quit(1)
		return

	_setup_heartbeat(port)
	GameLog.info("DedicatedServer", "Running. args=%s" % str(args))

func _setup_heartbeat(port: int) -> void:
	_backend_url = str(OS.get_environment("PLATFORM_BACKEND_URL")).strip_edges()
	if _backend_url.is_empty():
		_backend_url = DEFAULT_PLATFORM_BACKEND_URL
	_internal_api_secret = str(OS.get_environment("INTERNAL_API_SECRET")).strip_edges()
	if _internal_api_secret.is_empty():
		_internal_api_secret = DEFAULT_INTERNAL_API_SECRET
	_game_server_id = str(OS.get_environment("GAME_SERVER_ID")).strip_edges()
	if _game_server_id.is_empty():
		_game_server_id = _generate_game_server_id(port)

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SEC
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	_heartbeat_timer.start()

	GameLog.info(
		"DedicatedServer",
		"Heartbeat enabled backend=%s game_server_id=%s interval=%.1fs"
			% [_backend_url, _game_server_id, HEARTBEAT_INTERVAL_SEC]
	)
	_send_heartbeat()

func _generate_game_server_id(port: int) -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(8)
	return "local_%s_%d" % [bytes.hex_encode(), int(port)]

func _on_heartbeat_timeout() -> void:
	_send_heartbeat()

func _send_heartbeat() -> void:
	if _heartbeat_in_flight:
		return
	if _backend_url.is_empty() or _internal_api_secret.is_empty() or _game_server_id.is_empty():
		return

	var room_codes: Array[String] = []
	if NetClient != null and NetClient._room_manager != null and is_instance_valid(NetClient._room_manager):
		if NetClient._room_manager.rooms is Dictionary:
			for code_val in NetClient._room_manager.rooms.keys():
				var code := str(code_val).strip_edges().to_upper()
				if code.is_empty():
					continue
				room_codes.append(code)

	var base := str(_backend_url)
	if base.ends_with("/"):
		base = base.trim_suffix("/")
	var url := base + "/internal/game_servers/heartbeat"
	var body := JSON.stringify({
		"game_server_id": _game_server_id,
		"room_codes": room_codes,
	})
	var headers := [
		"Content-Type: application/json",
		"X-Internal-Secret: " + _internal_api_secret,
	]

	_heartbeat_in_flight = true
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		_heartbeat_in_flight = false
		if not room_codes.is_empty():
			GameLog.warn("DedicatedServer", "Heartbeat request_failed err=%s url=%s" % [str(err), url])
		return
	var result: Array = await http.request_completed
	http.queue_free()
	_heartbeat_in_flight = false

	var response_code: int = result[1]
	if response_code < 200 or response_code >= 300:
		if not room_codes.is_empty():
			GameLog.warn("DedicatedServer", "Heartbeat failed status=%d url=%s" % [response_code, url])
