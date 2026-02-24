# Online connect smoke test (Headless / Autorun)
# Purpose: verify connect_token handshake + platform auto-join works against a dedicated server.
extends Control

const ConnectTokenClass = preload("res://core/utils/connect_token.gd")

const DEFAULT_URL := "ws://127.0.0.1:7000"
const CONNECT_TIMEOUT_SEC := 5.0
const ROOM_READY_TIMEOUT_SEC := 5.0

const ROOM_CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6

func _ready() -> void:
	if _should_autorun():
		var code := await _run()
		get_tree().quit(code)

func _run() -> int:
	var args := OS.get_cmdline_user_args()
	var url := DEFAULT_URL
	var secret := str(OS.get_environment("HMAC_SECRET")).strip_edges()
	for a in args:
		var s := str(a).strip_edges()
		if s.begins_with("--url="):
			url = str(s.split("=", false, 1)[1]).strip_edges()
		elif s.begins_with("--secret="):
			secret = str(s.split("=", false, 1)[1]).strip_edges()

	if secret.is_empty():
		push_error("[OnlineConnectSmokeTest] FAIL: missing HMAC_SECRET (use env HMAC_SECRET or --secret=...)")
		print("[OnlineConnectSmokeTest] FAIL: missing HMAC_SECRET (use env HMAC_SECRET or --secret=...)")
		return 1

	var room_code := _generate_room_code()
	var payload := _build_host_connect_token_payload(room_code)
	var tr: Result = ConnectTokenClass.create_token(payload, secret)
	if not tr.ok:
		push_error("[OnlineConnectSmokeTest] FAIL: create_token failed: %s" % tr.error)
		print("[OnlineConnectSmokeTest] FAIL: create_token failed: %s" % tr.error)
		return 1
	var connect_token := str(tr.value)
	var connect_url := _append_connect_token(url, connect_token)

	print("[OnlineConnectSmokeTest] START url=%s room_code=%s args=%s" % [url, room_code, str(args)])

	if NetClient == null:
		push_error("[OnlineConnectSmokeTest] FAIL: NetClient autoload missing")
		print("[OnlineConnectSmokeTest] FAIL: NetClient autoload missing")
		return 1

	var r: Result = NetClient.connect_to_server(connect_url)
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

	# 进一步验证：connect_token 应触发 server 自动创建/加入指定 room_code
	var deadline_room_ms := int(Time.get_ticks_msec() + int(round(ROOM_READY_TIMEOUT_SEC * 1000.0)))
	while Time.get_ticks_msec() < deadline_room_ms:
		var room_state: Dictionary = NetContext.room_state if NetContext != null else {}
		if str(room_state.get("room_code", "")).strip_edges().to_upper() == room_code:
			print("[OnlineConnectSmokeTest] PASS")
			NetClient.shutdown()
			return 0
		await get_tree().process_frame

	push_error("[OnlineConnectSmokeTest] FAIL: room_state not ready timeout (%ss)" % str(ROOM_READY_TIMEOUT_SEC))
	print("[OnlineConnectSmokeTest] FAIL: room_state not ready timeout (%ss)" % str(ROOM_READY_TIMEOUT_SEC))
	NetClient.shutdown()
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")

func _append_connect_token(base_url: String, connect_token: String) -> String:
	var base := str(base_url).strip_edges()
	var sep := "?" if base.find("?") < 0 else "&"
	return base + sep + "connect_token=" + str(connect_token).uri_encode()

func _generate_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in range(ROOM_CODE_LENGTH):
		out += ROOM_CODE_ALPHABET[rng.randi_range(0, ROOM_CODE_ALPHABET.length() - 1)]
	return out

func _build_host_connect_token_payload(room_code: String) -> Dictionary:
	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": Array(Globals.enabled_modules_v2, TYPE_STRING, "", null) if Globals != null else [],
		"modules_v2_base_dir": str(Globals.modules_v2_base_dir) if Globals != null else "",
	}
	return {
		"user_id": "smoke_host",
		"room_code": str(room_code).strip_edges().to_upper(),
		"role": "host",
		"seat_index": 0,
		"display_name": "SmokeHost",
		"config_json": JSON.stringify(cfg),
		"exp": int(Time.get_unix_time_from_system()) + 60,
	}
