# Online connect smoke test (Headless / Autorun)
# Purpose: verify WebSocket multiplayer transport can connect to a dedicated server.
extends Control

const DEFAULT_URL := "ws://127.0.0.1:7000"
const CONNECT_TIMEOUT_SEC := 5.0
const CREATE_ROOM_TIMEOUT_SEC := 5.0

func _ready() -> void:
	if _should_autorun():
		var code := await _run()
		get_tree().quit(code)

func _run() -> int:
	var args := OS.get_cmdline_user_args()
	var url := DEFAULT_URL
	for a in args:
		var s := str(a).strip_edges()
		if s.begins_with("--url="):
			url = str(s.split("=", false, 1)[1]).strip_edges()

	print("[OnlineConnectSmokeTest] START url=%s args=%s" % [url, str(args)])

	if NetClient == null:
		push_error("[OnlineConnectSmokeTest] FAIL: NetClient autoload missing")
		print("[OnlineConnectSmokeTest] FAIL: NetClient autoload missing")
		return 1

	var r: Result = NetClient.connect_to_server(url)
	if not r.ok:
		push_error("[OnlineConnectSmokeTest] FAIL: %s" % r.error)
		print("[OnlineConnectSmokeTest] FAIL: %s" % r.error)
		return 1

	var deadline_ms := int(Time.get_ticks_msec() + int(round(CONNECT_TIMEOUT_SEC * 1000.0)))
	while Time.get_ticks_msec() < deadline_ms:
		if NetClient.is_online_client_connected():
			break
		await get_tree().process_frame

	if not NetClient.is_online_client_connected():
		push_error("[OnlineConnectSmokeTest] FAIL: timeout (%ss)" % str(CONNECT_TIMEOUT_SEC))
		print("[OnlineConnectSmokeTest] FAIL: timeout (%ss)" % str(CONNECT_TIMEOUT_SEC))
		NetClient.shutdown()
		return 1

	# 进一步验证：创建房间应返回 room_code（避免“已连接但无法开始联机流程”的假阳性）
	await get_tree().process_frame
	await get_tree().process_frame
	NetClient.request_create_room(2, "", {})

	var deadline_room_ms := int(Time.get_ticks_msec() + int(round(CREATE_ROOM_TIMEOUT_SEC * 1000.0)))
	while Time.get_ticks_msec() < deadline_room_ms:
		var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
		if not str(room_state.get("room_code", "")).strip_edges().is_empty():
			print("[OnlineConnectSmokeTest] PASS")
			NetClient.shutdown()
			return 0
		await get_tree().process_frame

	push_error("[OnlineConnectSmokeTest] FAIL: create_room timeout (%ss)" % str(CREATE_ROOM_TIMEOUT_SEC))
	print("[OnlineConnectSmokeTest] FAIL: create_room timeout (%ss)" % str(CREATE_ROOM_TIMEOUT_SEC))
	NetClient.shutdown()
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
