# Repro: online dinnertime confirm barrier race (headless client bot)
# Usage (example):
#   mkdir -p .tmp_home .godot
#   rm -f /tmp/fcm_room_code.txt
#   HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/ReproServer.log" --path . --scene res://server/dedicated_server.tscn -- --port=7000
#   HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/ReproClientHost.log" --path . --script res://tools/repro_online_dinnertime_confirm_race.gd -- --role=host --server=ws://127.0.0.1:7000 --room-file=/tmp/fcm_room_code.txt --password=123 --confirm-delay-ms=0
#   HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/ReproClientJoin.log" --path . --script res://tools/repro_online_dinnertime_confirm_race.gd -- --role=join --server=ws://127.0.0.1:7000 --room-file=/tmp/fcm_room_code.txt --password=123 --confirm-delay-ms=1500
#
# Notes:
# - Avoid preload() of scripts that reference Autoload singletons (GameLog/NetClient/etc) in --script mode.
# - This script drives the game via NetClient ActionRequest and replays CommandApplied into the local engine.
extends SceneTree

const NAME := "OnlineDinnertimeRepro"

var _role := "host"
var _server_url := "ws://127.0.0.1:7000"
var _room_file := "/tmp/fcm_room_code.txt"
var _room_password := "123"
var _confirm_delay_ms := 0
var _timeout_ms := 120_000
var _stop_round := 1

var _net_client = null
var _net_context = null
var _globals = null

var _CommandClass = null
var _CoordsClass = null

var _engine = null
var _local_pid := -1

var _action_in_flight := false
var _entered_dinnertime_ms := -1
var _entered_dinnertime_round := -1
var _sent_confirm_rounds: Dictionary = {} # round_number -> true

var _place_scan_world_min := Vector2i(0, 0)
var _place_scan_world_max := Vector2i(0, 0)
var _place_scan_initialized := false
var _place_scan_x := 0
var _place_scan_y := 0
var _place_scan_rot := 0

func _initialize() -> void:
	print("[%s] START" % NAME)
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_parse_args(args)
	print("[%s] role=%s server=%s room_file=%s confirm_delay_ms=%d timeout_ms=%d" % [
		NAME,
		_role,
		_server_url,
		_room_file,
		_confirm_delay_ms,
		_timeout_ms,
	])
	print("[%s] stop_round=%d" % [NAME, _stop_round])

	# Delay-load dependencies (see header note).
	_CommandClass = load("res://core/types/command.gd")
	_CoordsClass = load("res://core/map/map_runtime/coords.gd")
	if _CommandClass == null or _CoordsClass == null:
		push_error("[%s] FAIL load core scripts" % NAME)
		quit(1)
		return

	_net_client = _get_autoload_node("NetClient")
	_net_context = _get_autoload_node("NetContext")
	_globals = _get_autoload_node("Globals")
	if _net_client == null or _net_context == null or _globals == null:
		push_error("[%s] FAIL missing autoloads NetClient/NetContext/Globals" % NAME)
		quit(1)
		return

	# Make logs chatty for repro.
	var game_log = _get_autoload_node("GameLog")
	if game_log != null and game_log.has_method("set_min_level"):
		game_log.set_min_level(int(game_log.LEVEL_DEBUG))

	_connect_net_signals()

	var cr = _net_client.connect_to_server(_server_url)
	if cr is Result and not cr.ok:
		push_error("[%s] FAIL connect_to_server: %s" % [NAME, cr.error])
		quit(1)
		return

	var connected_ok := await _wait_until(func() -> bool:
		return bool(_net_client.is_online_client_connected()) if _net_client.has_method("is_online_client_connected") else false
	, 10_000)
	if not connected_ok:
		push_error("[%s] FAIL connect timeout" % NAME)
		quit(1)
		return

	if _role == "host":
		var req_id = _net_client.request_create_room(2, _room_password, {"seed_mode": "fixed", "seed": 12345})
		print("[%s] host create_room request_id=%s" % [NAME, str(req_id)])

		var code_ok := await _wait_until(func() -> bool:
			var rs: Dictionary = _net_context.room_state if _net_context.get("room_state") is Dictionary else {}
			return not str(rs.get("room_code", "")).strip_edges().is_empty()
		, 10_000)
		if not code_ok:
			push_error("[%s] FAIL room_code timeout" % NAME)
			quit(1)
			return

		var room_state: Dictionary = _net_context.room_state
		var room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
		print("[%s] host room_code=%s" % [NAME, room_code])
		var w := _write_text_file(_room_file, room_code)
		if not w.ok:
			push_error("[%s] FAIL write room_file: %s" % [NAME, w.error])
			quit(1)
			return

		var ready_ok := await _wait_until(func() -> bool:
			var rs2: Dictionary = _net_context.room_state if _net_context.get("room_state") is Dictionary else {}
			var players_val = rs2.get("players", null)
			if not (players_val is Array):
				return false
			return Array(players_val).size() >= 2
		, 20_000)
		if not ready_ok:
			push_error("[%s] FAIL players not ready (need 2)" % NAME)
			quit(1)
			return

		var start_id = _net_client.request_start_game()
		print("[%s] host start_game request_id=%s" % [NAME, str(start_id)])
	else:
		var code_read := await _wait_until(func() -> bool:
			return FileAccess.file_exists(_room_file)
		, 15_000)
		if not code_read:
			push_error("[%s] FAIL room_file not found: %s" % [NAME, _room_file])
			quit(1)
			return
		var room_code2 := str(_read_text_file(_room_file)).strip_edges().to_upper()
		if room_code2.is_empty():
			push_error("[%s] FAIL room_code empty from file" % NAME)
			quit(1)
			return
		var join_id = _net_client.request_join_room(room_code2, _room_password)
		print("[%s] join request_id=%s room_code=%s" % [NAME, str(join_id), room_code2])

	var started_ok := await _wait_until(func() -> bool:
		return _globals.get("current_game_engine") != null
	, 20_000)
	if not started_ok:
		push_error("[%s] FAIL game engine not initialized" % NAME)
		quit(1)
		return

	_engine = _globals.get("current_game_engine")
	if _engine == null or not _engine.has_method("get_state"):
		push_error("[%s] FAIL current_game_engine invalid" % NAME)
		quit(1)
		return

	_local_pid = int(_net_context.get("local_player_id")) if _net_context.has_method("get") else -1
	if _local_pid < 0:
		push_error("[%s] FAIL local_player_id not set (spectator?)" % NAME)
		quit(1)
		return

	print("[%s] engine ready local_pid=%d" % [NAME, _local_pid])

	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < _timeout_ms:
		_maybe_send_next_action()
		await process_frame

	push_error("[%s] FAIL timeout" % NAME)
	quit(1)

func _connect_net_signals() -> void:
	var cb_cmd := Callable(self, "_on_command_applied")
	var cb_archive := Callable(self, "_on_resync_archive_received")
	var cb_reject := Callable(self, "_on_request_rejected")
	if _net_client.command_applied.is_connected(cb_cmd) == false:
		_net_client.command_applied.connect(cb_cmd)
	if _net_client.resync_archive_received.is_connected(cb_archive) == false:
		_net_client.resync_archive_received.connect(cb_archive)
	if _net_client.request_rejected.is_connected(cb_reject) == false:
		_net_client.request_rejected.connect(cb_reject)

func _on_command_applied(cmd_dict: Dictionary, state_hash: String) -> void:
	if _engine == null:
		return
	var parsed = _CommandClass.from_dict(cmd_dict)
	if not parsed.ok:
		push_error("[%s] FAIL Command.from_dict: %s" % [NAME, parsed.error])
		quit(1)
		return
	var cmd = parsed.value
	var expected_index := int(_engine.command_history.size()) if _engine.has_method("get_command_history") else int(_engine.command_history.size())
	if int(cmd.index) != expected_index:
		print("[%s] WARN command_index mismatch local=%d server=%d (requesting resync)" % [NAME, expected_index, int(cmd.index)])
		if _net_client.has_method("request_resync"):
			_net_client.request_resync()
		return
	var r = _engine.execute_command(cmd, true)
	if not r.ok:
		push_error("[%s] FAIL replay execute_command: %s" % [NAME, r.error])
		quit(1)
		return
	_action_in_flight = false

func _on_resync_archive_received(archive: Dictionary) -> void:
	if _engine == null:
		return
	var r = _engine.load_from_archive(archive)
	if not r.ok:
		push_error("[%s] FAIL load_from_archive: %s" % [NAME, r.error])
		quit(1)
		return
	_action_in_flight = false

func _on_request_rejected(request_id: String, code: String, message: String) -> void:
	_action_in_flight = false
	print("[%s] RX RequestRejected request_id=%s code=%s message=%s" % [NAME, str(request_id), str(code), str(message)])
	if str(code) == "action_failed" and str(message).find("当前不在晚餐阶段") != -1:
		push_error("[%s] FAIL repro hit: %s" % [NAME, str(message)])
		quit(1)

func _maybe_send_next_action() -> void:
	if _engine == null:
		return
	if _action_in_flight:
		return
	var state = _engine.get_state()
	if state == null:
		return

	var phase := str(state.phase)
	var round_num := int(state.round_number)
	if phase == "Payday":
		if round_num == _stop_round:
			if not _has_sent_dinnertime_confirm(round_num):
				push_error("[%s] FAIL entered Payday before sending confirm (round=%d local_pid=%d)" % [NAME, round_num, _local_pid])
				quit(1)
				return
			print("[%s] PASS reached Payday after confirm (round=%d local_pid=%d)" % [NAME, round_num, _local_pid])
			quit(0)
			return
		_try_play_payday(state)
		return

	if phase == "Dinnertime":
		if _entered_dinnertime_round != round_num:
			_entered_dinnertime_round = round_num
			_entered_dinnertime_ms = Time.get_ticks_msec()
			print("[%s] entered Dinnertime round=%d local_pid=%d" % [NAME, round_num, _local_pid])
		if _has_sent_dinnertime_confirm(round_num):
			return
		var elapsed := Time.get_ticks_msec() - _entered_dinnertime_ms
		if elapsed < _confirm_delay_ms:
			return
		if not _needs_dinnertime_confirm(state):
			return
		_send_action("confirm_dinnertime", {})
		_mark_sent_dinnertime_confirm(round_num)
		print("[%s] sent confirm_dinnertime round=%d local_pid=%d after_ms=%d" % [NAME, round_num, _local_pid, elapsed])
		return

	if phase == "Setup":
		_try_play_setup(state)
		return
	if phase == "Restructuring":
		_try_play_restructuring(state)
		return
	if phase == "OrderOfBusiness":
		_try_play_order_of_business(state)
		return
	if phase == "Working":
		_try_play_working(state)
		return

func _try_play_payday(state) -> void:
	if state == null:
		return
	var current := int(state.get_current_player_id())
	if current != _local_pid:
		return
	_send_action("skip", {})

func _try_play_setup(state) -> void:
	if state == null:
		return
	var current := int(state.get_current_player_id())
	if current != _local_pid:
		return
	var sub := str(state.sub_phase)
	if sub == "ReserveCards":
		_send_action("select_reserve_card", {"selected_index": 0})
		return

	var p = state.get_player(_local_pid)
	if not (p is Dictionary):
		return
	var player: Dictionary = p
	var restaurants_val = player.get("restaurants", null)
	var restaurants: Array = Array(restaurants_val) if restaurants_val is Array else []
	if restaurants.is_empty():
		var params := _next_place_restaurant_params(state)
		if params.is_empty():
			push_error("[%s] FAIL no place_restaurant position found" % NAME)
			quit(1)
			return
		_send_action("place_restaurant", params)
		return
	_send_action("skip", {})

func _try_play_restructuring(state) -> void:
	if state == null or not (state.round_state is Dictionary):
		return
	var rs: Dictionary = state.round_state
	var r_val = rs.get("restructuring", null)
	var submitted := false
	if r_val is Dictionary:
		var r: Dictionary = r_val
		var submitted_val = r.get("submitted", null)
		if submitted_val is Dictionary:
			var s: Dictionary = submitted_val
			submitted = bool(s.get(_local_pid, false)) or bool(s.get(str(_local_pid), false))
	if submitted:
		return
	_send_action("submit_restructuring", {})

func _try_play_order_of_business(state) -> void:
	if state == null or not (state.round_state is Dictionary):
		return
	var current := int(state.get_current_player_id())
	if current != _local_pid:
		return
	var rs: Dictionary = state.round_state
	var oob_val = rs.get("order_of_business", null)
	if not (oob_val is Dictionary):
		return
	var oob: Dictionary = oob_val
	var picks_val = oob.get("picks", null)
	if not (picks_val is Array):
		return
	var picks: Array = picks_val
	var pos := picks.find(-1)
	if pos < 0:
		return
	_send_action("choose_turn_order", {"position": pos})

func _try_play_working(state) -> void:
	if state == null:
		return
	var current := int(state.get_current_player_id())
	if current != _local_pid:
		return
	var last_sub := _get_last_working_sub_phase(state)
	if last_sub.is_empty():
		return
	var sub := str(state.sub_phase)
	if sub != last_sub:
		_send_action("skip_sub_phase", {})
		return
	_send_action("skip", {})

func _get_last_working_sub_phase(state) -> String:
	if state == null or not (state.round_state is Dictionary):
		return "PlaceRestaurants"
	var rs: Dictionary = state.round_state
	var order_val = rs.get("working_sub_phase_order", null)
	if not (order_val is Array):
		return "PlaceRestaurants"
	var order: Array = order_val
	if order.is_empty():
		return "PlaceRestaurants"
	return str(order[order.size() - 1])

func _next_place_restaurant_params(state) -> Dictionary:
	if state == null:
		return {}
	if not _place_scan_initialized:
		_place_scan_world_min = _CoordsClass.get_world_min(state)
		_place_scan_world_max = _CoordsClass.get_world_max(state)
		_place_scan_x = int(_place_scan_world_min.x)
		_place_scan_y = int(_place_scan_world_min.y)
		_place_scan_rot = 0
		_place_scan_initialized = true

	if _place_scan_y > _place_scan_world_max.y:
		return {}
	var params := {
		"position": [_place_scan_x, _place_scan_y],
		"rotation": _place_scan_rot,
	}
	_place_scan_rot += 1
	if _place_scan_rot >= 4:
		_place_scan_rot = 0
		_place_scan_x += 1
		if _place_scan_x > _place_scan_world_max.x:
			_place_scan_x = int(_place_scan_world_min.x)
			_place_scan_y += 1
	return params

func _needs_dinnertime_confirm(state) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return false
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get("Dinnertime", null)
	if not (list_val is Array):
		return false
	var list: Array = list_val
	if list.size() == 1 and (list[0] is String) and str(list[0]) == "confirm_dinnertime":
		return true
	for item_val in list:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != "confirm_dinnertime":
			continue
		var pid_val = item.get("player_id", -1)
		var pid := -1
		if pid_val is int:
			pid = int(pid_val)
		elif pid_val is float and float(pid_val) == floor(float(pid_val)):
			pid = int(pid_val)
		if pid == _local_pid:
			return true
	return false

func _send_action(action_id: String, params: Dictionary) -> void:
	if _net_client == null:
		return
	var rid = _net_client.request_action(action_id, params)
	_action_in_flight = true
	print("[%s] TX action=%s request_id=%s" % [NAME, action_id, str(rid)])

func _wait_until(check: Callable, timeout_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		if check.is_valid() and bool(check.call()):
			return true
		await process_frame
	return false

func _get_autoload_node(name: String):
	if name.is_empty():
		return null
	if root == null:
		return null
	return root.get_node_or_null(name)

func _write_text_file(path: String, text: String) -> Result:
	var p := str(path).strip_edges()
	if p.is_empty():
		return Result.failure("path 为空")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return Result.failure("无法写入文件: %s" % p)
	f.store_string(str(text))
	f.close()
	return Result.success()

func _read_text_file(path: String) -> String:
	var p := str(path).strip_edges()
	if p.is_empty():
		return ""
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return str(s)

func _parse_args(args: Array) -> void:
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a.begins_with("--role="):
			_role = a.split("=", false, 1)[1]
			i += 1
			continue
		if a == "--role" and i + 1 < args.size():
			_role = str(args[i + 1])
			i += 2
			continue
		if a.begins_with("--server="):
			_server_url = a.split("=", false, 1)[1]
			i += 1
			continue
		if a == "--server" and i + 1 < args.size():
			_server_url = str(args[i + 1])
			i += 2
			continue
		if a.begins_with("--room-file="):
			_room_file = a.split("=", false, 1)[1]
			i += 1
			continue
		if a == "--room-file" and i + 1 < args.size():
			_room_file = str(args[i + 1])
			i += 2
			continue
		if a.begins_with("--password="):
			_room_password = a.split("=", false, 1)[1]
			i += 1
			continue
		if a == "--password" and i + 1 < args.size():
			_room_password = str(args[i + 1])
			i += 2
			continue
		if a.begins_with("--confirm-delay-ms="):
			_confirm_delay_ms = int(a.split("=", false, 1)[1])
			i += 1
			continue
		if a == "--confirm-delay-ms" and i + 1 < args.size():
			_confirm_delay_ms = int(args[i + 1])
			i += 2
			continue
		if a.begins_with("--timeout-ms="):
			_timeout_ms = int(a.split("=", false, 1)[1])
			i += 1
			continue
		if a == "--timeout-ms" and i + 1 < args.size():
			_timeout_ms = int(args[i + 1])
			i += 2
			continue
		if a.begins_with("--stop-round="):
			_stop_round = int(a.split("=", false, 1)[1])
			i += 1
			continue
		if a == "--stop-round" and i + 1 < args.size():
			_stop_round = int(args[i + 1])
			i += 2
			continue
		i += 1

func _has_sent_dinnertime_confirm(round_number: int) -> bool:
	if _sent_confirm_rounds.has(round_number):
		return bool(_sent_confirm_rounds.get(round_number, false))
	return false

func _mark_sent_dinnertime_confirm(round_number: int) -> void:
	_sent_confirm_rounds[round_number] = true
