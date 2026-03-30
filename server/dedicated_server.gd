# Dedicated Server 入口（Headless）
extends Node

const DEFAULT_PORT := 7000
const DEFAULT_BIND_ADDRESS := "0.0.0.0"
const DEFAULT_PLATFORM_BACKEND_URL := "http://127.0.0.1:8000"
const DEFAULT_INTERNAL_API_SECRET := "dev-internal-secret-change-in-production"
const DEFAULT_ROOM_PERSIST_PATH := "user://dedicated_server/online_room_snapshots.json"
const HEARTBEAT_INTERVAL_SEC := 15.0
const PERSIST_INTERVAL_SEC := 2.0

const RoomPersistenceStoreClass = preload("res://server/room_persistence_store.gd")

var _backend_url: String = ""
var _internal_api_secret: String = ""
var _game_server_id: String = ""
var _heartbeat_in_flight: bool = false
var _heartbeat_timer: Timer = null
var _room_persistence_store = null
var _persist_timer: Timer = null

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

	var persist_r: Result = _setup_persistence()
	if not persist_r.ok:
		GameLog.error("DedicatedServer", persist_r.error)
		get_tree().quit(1)
		return

	_setup_heartbeat(port)
	GameLog.info("DedicatedServer", "Running. args=%s" % str(args))

func _exit_tree() -> void:
	_persist_rooms()

func _setup_persistence() -> Result:
	var snapshot_path := str(OS.get_environment("FCM_ROOM_PERSIST_PATH")).strip_edges()
	if snapshot_path.is_empty():
		snapshot_path = DEFAULT_ROOM_PERSIST_PATH
	_room_persistence_store = RoomPersistenceStoreClass.new(snapshot_path)

	if NetClient == null or NetClient._room_manager == null or not is_instance_valid(NetClient._room_manager):
		return Result.failure("DedicatedServer persistence setup failed: RoomManager missing")

	var load_r: Result = _room_persistence_store.load_snapshot()
	if not load_r.ok:
		return Result.failure("加载房间快照失败: %s" % load_r.error)
	var restore_r: Result = NetClient._room_manager.restore_from_persistence(Dictionary(load_r.value))
	if not restore_r.ok:
		return Result.failure("恢复房间快照失败: %s" % restore_r.error)

	_persist_timer = Timer.new()
	_persist_timer.one_shot = false
	_persist_timer.wait_time = PERSIST_INTERVAL_SEC
	add_child(_persist_timer)
	_persist_timer.timeout.connect(_on_persist_timeout)
	_persist_timer.start()

	var restored_rooms := int(restore_r.value.get("restored_rooms", 0)) if restore_r.value is Dictionary else 0
	GameLog.info(
		"DedicatedServer",
		"Persistence enabled path=%s restored_rooms=%d interval=%.1fs"
			% [ProjectSettings.globalize_path(snapshot_path), restored_rooms, PERSIST_INTERVAL_SEC]
	)
	_persist_rooms()
	return Result.success()

func _on_persist_timeout() -> void:
	_persist_rooms()

func _persist_rooms() -> void:
	if _room_persistence_store == null:
		return
	if NetClient == null or NetClient._room_manager == null or not is_instance_valid(NetClient._room_manager):
		return
	var save_r: Result = _room_persistence_store.save_room_manager(NetClient._room_manager)
	if not save_r.ok:
		GameLog.warn("DedicatedServer", "Persist rooms failed: %s" % save_r.error)

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
