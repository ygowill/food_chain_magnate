# NetClient：Client-only 逻辑（连接回调 + ClientHello）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：RoomState/RoomList/CommandApplied 等高频收包走 DEBUG。
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ClientResyncServiceClass = preload("res://autoload/net_client/client_resync_service.gd")
const NetClientOnlineResumeSupportClass = preload("res://autoload/net_client_online_resume_support.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const RESUME_BOOTSTRAP_MODE_FULL_ARCHIVE_SNAPSHOT := "full_archive_snapshot"
const RESUME_PHASE_DISPLAY_NAMES := {
	"setup": "开局设置",
	"restructuring": "重组结构",
	"order_of_business": "商业秩序",
	"working": "工作时间",
	"marketing": "广告行动",
	"dinnertime": "晚餐结算",
	"cleanup": "清理阶段",
	"payday": "发薪日",
	"game_over": "游戏结束",
}

var _net = null
var _resync_service = ClientResyncServiceClass.new()
var _online_resume_support = NetClientOnlineResumeSupportClass.new()
var _pending_resume_full_snapshot_payload: Dictionary = {}
var _pending_resume_full_snapshot_room_code: String = ""
var _pending_resume_full_snapshot_local_pid: int = -1

func setup(net_client) -> void:
	_net = net_client
	_configure_resync_service()
	_configure_online_resume_support()

func _configure_resync_service() -> void:
	if _resync_service == null or not is_instance_valid(_resync_service):
		_resync_service = ClientResyncServiceClass.new()
	_resync_service.setup(_net, {
		"matches_payload_room_code": Callable(self, "_matches_payload_room_code"),
		"invalidate_full_history_engine": Callable(self, "_invalidate_full_history_engine"),
		"emit_local_bootstrap_progress": Callable(self, "_emit_local_bootstrap_progress"),
		"make_local_bootstrap_progress_state": Callable(self, "_make_local_bootstrap_progress_state"),
		"consume_pending_resume_full_snapshot_payload": Callable(self, "_consume_pending_resume_full_snapshot_payload"),
		"get_pending_resume_full_snapshot_local_pid": Callable(self, "_get_pending_resume_full_snapshot_local_pid"),
		"set_pending_resume_full_snapshot_local_pid": Callable(self, "_set_pending_resume_full_snapshot_local_pid"),
		"bootstrap_resume_full_snapshot_archive": Callable(self, "_bootstrap_resume_full_snapshot_archive"),
		"emit_resume_full_history_ready": Callable(self, "_emit_resume_full_history_ready"),
		"try_bootstrap_online_client_engine_from_archive": Callable(self, "_try_bootstrap_online_client_engine_from_archive"),
		"translate_resync_delta_to_runtime": Callable(self, "_translate_resync_delta_to_runtime"),
		"get_active_resume_engine": Callable(self, "_get_active_resume_engine"),
		"sync_online_resume_progress": Callable(self, "_sync_online_resume_progress"),
		"safe_text": Callable(self, "_safe_text"),
		"short_hash": Callable(self, "_short_hash"),
	})

func _configure_online_resume_support() -> void:
	if _online_resume_support == null or not is_instance_valid(_online_resume_support):
		_online_resume_support = NetClientOnlineResumeSupportClass.new()
	_online_resume_support.setup(_net, {
		"sync_online_resume_progress": Callable(self, "_sync_online_resume_progress"),
		"get_online_client_engine_room_code": Callable(self, "_get_online_client_engine_room_code"),
		"safe_text": Callable(self, "_safe_text"),
		"net_has_signal": Callable(self, "_net_has_signal"),
	})

func on_connected_to_server() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = true
	GameLog.info(
		"NetClient",
		"Connected to server peer_id=%d url=%s"
			% [int(_net.multiplayer.get_unique_id()), _safe_text(str(NetContext.server_url))]
	)
	send_client_hello()
	_net.connected.emit()

func on_connection_failed() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = false
	GameLog.error("NetClient", "Connection failed url=%s" % _safe_text(str(NetContext.server_url)))
	_net.disconnected.emit("connection_failed")
	_net.shutdown(not _should_preserve_online_context_on_disconnect())

func on_server_disconnected() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = false
	GameLog.warn("NetClient", "Server disconnected url=%s" % _safe_text(str(NetContext.server_url)))
	_net.disconnected.emit("server_disconnected")
	_net.shutdown(not _should_preserve_online_context_on_disconnect())

func send_client_hello() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var request_id: String = _net._next_request_id()
	var profile: Dictionary = NetContext.player_profile.duplicate(true)
	var payload := {
		"request_id": request_id,
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": Globals.get_version(),
		"schema_version": Globals.SCHEMA_VERSION,
		"player_profile": profile,
	}
	if NetContext.connect_token != "":
		payload["connect_token"] = NetContext.connect_token
	if Globals != null and Globals.current_game_engine != null:
		_sync_online_resume_progress(Globals.current_game_engine)
	if NetContext != null and NetContext.has_method("build_online_resume_cursor"):
		var force_snapshot := false
		if _net != null and is_instance_valid(_net):
			force_snapshot = bool(_net._resume_force_snapshot_once)
			if force_snapshot:
				_net._resume_force_snapshot_once = false
		var resume_cursor: Dictionary = NetContext.build_online_resume_cursor(force_snapshot)
		if not resume_cursor.is_empty():
			payload["resume_cursor"] = resume_cursor
	if _net != null and is_instance_valid(_net):
		var resume_room_bootstrap: Dictionary = _net.take_pending_resume_room_bootstrap() if _net.has_method("take_pending_resume_room_bootstrap") else {}
		if not resume_room_bootstrap.is_empty():
			payload["resume_room_bootstrap"] = resume_room_bootstrap
	_net.rpc_id(1, "rpc_client_hello", payload)
	GameLog.debug(
		"NetClient",
		"TX ClientHello request_id=%s protocol=%d game_version=%s schema=%d profile_name=%s color=%d restaurant_logo_id=%d"
			% [
				request_id,
				int(NetContext.PROTOCOL_VERSION),
				str(Globals.get_version()),
				int(Globals.SCHEMA_VERSION),
				_safe_text(str(profile.get("name", ""))),
				int(profile.get("color_index", -1)),
				int(profile.get("restaurant_logo_id", -1))
			]
	)

func handle_rpc_room_state(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var previous_room_code := str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper()
	var next_room_code := str(payload.get("room_code", "")).strip_edges().to_upper()
	if not previous_room_code.is_empty() and previous_room_code != next_room_code and _net != null and is_instance_valid(_net):
		if _net.has_method("clear_pending_online_resync_state"):
			_net.clear_pending_online_resync_state()
		_set_online_client_engine_room_code("")
		_clear_online_resume_full_history_state()
	NetContext.room_state = payload.duplicate(true)
	var self_seat_val = NetContext.room_state.get("self_seat_index", null)
	if self_seat_val is int or self_seat_val is float:
		NetContext.local_player_id = int(self_seat_val)
	var self_role := str(NetContext.room_state.get("self_role", "")).strip_edges()
	NetContext.local_role = self_role
	var room_status := str(NetContext.room_state.get("status", "")).strip_edges()
	if room_status != "InGame" and room_status != "Starting":
		_set_online_client_engine_room_code("")
		_clear_online_resume_full_history_state()
	_sync_online_resume_state_from_room_state(NetContext.room_state)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state)
	GameLog.debug("NetClient", "RX RoomState %s" % _room_state_brief(NetContext.room_state))
	_net.room_state_updated.emit(NetContext.room_state)

func handle_rpc_room_list(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var request_id := str(payload.get("request_id", ""))
	var rooms_val = payload.get("rooms", null)
	if not (rooms_val is Array):
		GameLog.warn("NetClient", "RX RoomList ignored: rooms type invalid request_id=%s" % _safe_text(request_id))
		return
	NetContext.room_list = Array(rooms_val).duplicate(true)
	GameLog.debug(
		"NetClient",
		"RX RoomList request_id=%s rooms=%d" % [_safe_text(request_id), NetContext.room_list.size()]
	)
	_net.room_list_updated.emit(NetContext.room_list.duplicate(true))

func handle_rpc_game_started(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var mapping_val = payload.get("player_id_by_peer_id", null)
	if not (mapping_val is Dictionary):
		GameLog.warn("NetClient", "RX GameStarted ignored: player_id_by_peer_id type invalid")
		return
	var cfg_val = payload.get("config", null)
	if not (cfg_val is Dictionary):
		GameLog.warn("NetClient", "RX GameStarted ignored: config type invalid")
		return
	var mapping: Dictionary = Dictionary(mapping_val)
	var config: Dictionary = Dictionary(cfg_val)

	var my_peer_id := int(_net.multiplayer.get_unique_id())
	var local_pid := -1
	var payload_local_pid = payload.get("local_player_id", null)
	if payload_local_pid is int or payload_local_pid is float:
		local_pid = int(payload_local_pid)
	elif NetContext.room_state.get("self_seat_index", null) is int or NetContext.room_state.get("self_seat_index", null) is float:
		local_pid = int(NetContext.room_state.get("self_seat_index", -1))
	elif mapping.has(my_peer_id):
		local_pid = int(mapping.get(my_peer_id, -1))
	elif mapping.has(str(my_peer_id)):
		local_pid = int(mapping.get(str(my_peer_id), -1))
	NetContext.local_player_id = local_pid
	GameLog.info(
		"NetClient",
		"RX GameStarted room=%s local_peer=%d local_player_id=%d mapped_peers=%d"
			% [
				_safe_text(str(NetContext.room_state.get("room_code", "")).to_upper()),
				my_peer_id,
				local_pid,
				mapping.size()
			]
	)

	var room_code := _get_expected_online_room_code()
	var resume_bootstrap_mode := str(payload.get("resume_bootstrap_mode", "")).strip_edges()
	var existing_engine: GameEngine = _try_reuse_existing_online_client_engine(room_code, local_pid)
	if existing_engine != null:
		if resume_bootstrap_mode == RESUME_BOOTSTRAP_MODE_FULL_ARCHIVE_SNAPSHOT:
			var prepare_existing_r := _online_resume_support.prepare_single_full_engine_runtime(
				existing_engine,
				room_code,
				local_pid,
				{},
				true
			)
			if not prepare_existing_r.ok:
				GameLog.warn("NetClient", "Reuse existing resume engine prepare failed: %s" % prepare_existing_r.error)
			_emit_resume_full_history_ready()
		_net.game_started.emit(payload.duplicate(true))
		_try_apply_pending_resync_delta()
		return

	var init_r: Result = Result.failure("missing bootstrap")
	if resume_bootstrap_mode == RESUME_BOOTSTRAP_MODE_FULL_ARCHIVE_SNAPSHOT:
		_clear_online_resume_full_history_state()
		_pending_resume_full_snapshot_payload = Dictionary(payload).duplicate(true)
		_pending_resume_full_snapshot_room_code = str(room_code).strip_edges().to_upper()
		_pending_resume_full_snapshot_local_pid = int(local_pid)
		_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
			room_code,
			"waiting_snapshot",
			"正在接收恢复快照...",
			"服务器已开始下发完整存档快照，收到后将进行本地回放与日志构建。",
			18.0
		))
		return
	_clear_online_resume_full_history_state()
	init_r = _initialize_online_client_engine_from_config(config, room_code, local_pid)
	if not init_r.ok:
		GameLog.error(
			"NetClient",
			"GameStarted bootstrap failed room=%s err=%s" % [_safe_text(room_code), _safe_text(init_r.error)]
		)
		if _net != null and is_instance_valid(_net) and _net.has_signal("match_bootstrap_local_failed"):
			_net.emit_signal("match_bootstrap_local_failed", str(init_r.error))
		return

	_net.game_started.emit(payload.duplicate(true))
	_try_apply_pending_resync_delta()

func handle_rpc_command_applied(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var cmd_dict_val = payload.get("cmd", null)
	if not (cmd_dict_val is Dictionary):
		GameLog.warn("NetClient", "RX CommandApplied ignored: cmd type invalid")
		return
	var cmd_dict: Dictionary = _translate_live_command_dict_to_runtime(Dictionary(cmd_dict_val))
	var state_hash := str(payload.get("state_hash", ""))
	var perf_meta_val = payload.get("perf", null)
	var perf_meta: Dictionary = Dictionary(perf_meta_val).duplicate(true) if perf_meta_val is Dictionary else {}
	var request_id := str(perf_meta.get("request_id", "")).strip_edges()
	if _net != null and is_instance_valid(_net):
		var local_perf: Dictionary = {}
		if _net.has_method("take_pending_action_perf"):
			local_perf = _net.take_pending_action_perf(request_id)
		if not local_perf.is_empty():
			perf_meta["local_request_action_id"] = str(local_perf.get("action_id", ""))
			perf_meta["client_request_unix_ms"] = int(local_perf.get("client_request_unix_ms", perf_meta.get("client_request_unix_ms", 0)))
			perf_meta["client_request_mono_usec"] = int(local_perf.get("client_request_mono_usec", perf_meta.get("client_request_mono_usec", 0)))
			perf_meta["client_request_to_rx_ms"] = float(maxi(
				0,
				OnlinePerfTraceClass.now_mono_usec() - int(local_perf.get("client_request_mono_usec", 0))
			)) / 1000.0
		perf_meta["client_rx_unix_ms"] = OnlinePerfTraceClass.now_unix_ms()
		var server_peer_send_unix_ms := int(perf_meta.get("server_peer_send_unix_ms", 0))
		if server_peer_send_unix_ms > 0:
			perf_meta["server_to_client_ms_approx"] = int(perf_meta.get("client_rx_unix_ms", 0)) - server_peer_send_unix_ms
		if _net.has_method("enqueue_command_applied_perf_meta"):
			_net.enqueue_command_applied_perf_meta(perf_meta)
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("client.command_applied.rx", {
			"request_id": request_id,
			"action_id": str(cmd_dict.get("action_id", "")),
			"actor_id": int(cmd_dict.get("actor", -1)),
			"command_index": int(cmd_dict.get("index", -1)),
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
			"client_request_to_rx_ms": float(perf_meta.get("client_request_to_rx_ms", -1.0)),
			"server_to_client_ms_approx": int(perf_meta.get("server_to_client_ms_approx", -1)),
			"server_exec_ms": float(perf_meta.get("server_exec_ms", -1.0)),
		})
	GameLog.debug(
		"NetClient",
		"RX CommandApplied action=%s actor=%d index=%d state_hash=%s"
			% [
				_safe_text(str(cmd_dict.get("action_id", ""))),
				int(cmd_dict.get("actor", -1)),
				int(cmd_dict.get("index", -1)),
				_short_hash(state_hash)
			]
	)
	_net.command_applied.emit(cmd_dict, state_hash)

func handle_rpc_resync_archive(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		GameLog.warn("NetClient", "RX ResyncArchive ignored: archive type invalid")
		return
	_invalidate_full_history_engine("live_resync_archive")
	_resync_service.set_pending_archive(Dictionary(archive_val))
	var pending_archive := _resync_service.get_pending_archive()
	var room_code := str(payload.get("room_code", _get_expected_online_room_code())).strip_edges().to_upper()
	var deferred_resume_payload := _consume_pending_resume_full_snapshot_payload(room_code)
	if not deferred_resume_payload.is_empty():
		var bootstrap_r := _bootstrap_resume_full_snapshot_archive(
			pending_archive,
			room_code,
			_pending_resume_full_snapshot_local_pid
		)
		if not bootstrap_r.ok:
			GameLog.error("NetClient", "Resume archive bootstrap failed: %s" % bootstrap_r.error)
			_pending_resume_full_snapshot_local_pid = -1
			if _net != null and is_instance_valid(_net) and _net.has_signal("match_bootstrap_local_failed"):
				_net.emit_signal("match_bootstrap_local_failed", str(bootstrap_r.error))
			return
		_emit_resume_full_history_ready()
		_net.resync_archive_received.emit(pending_archive.duplicate(true))
		_net.game_started.emit(deferred_resume_payload)
		_try_apply_pending_resync_delta()
		return
	_try_bootstrap_online_client_engine_from_archive(pending_archive)
	GameLog.warn(
		"NetClient",
		"RX ResyncArchive snapshot keys=%s" % str(Array(pending_archive.keys()))
	)
	_net.resync_archive_received.emit(pending_archive.duplicate(true))

func handle_rpc_rewind_to_turn_start_meta(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not _matches_payload_room_code(payload, "RewindMeta"):
		return
	_invalidate_full_history_engine("rewind_to_turn_start_meta")
	var rewind_meta := _translate_rewind_meta_to_runtime(Dictionary(payload).duplicate(true))
	_set_pending_rewind_to_turn_start_meta(rewind_meta)
	var pending_meta := _get_pending_rewind_to_turn_start_meta()
	GameLog.warn(
		"NetClient",
		"RX RewindMeta request_id=%s target=%d before=%d history=%d noop=%s state_hash=%s"
			% [
				_safe_text(str(pending_meta.get("request_id", ""))),
				int(pending_meta.get("target_index", -1)),
				int(pending_meta.get("before_index", -1)),
				int(pending_meta.get("history_size", -1)),
				str(bool(pending_meta.get("noop", false))),
				_short_hash(str(pending_meta.get("state_hash", "")))
			]
	)
	_net.rewind_to_turn_start_meta_received.emit(pending_meta.duplicate(true))

func handle_rpc_resync_snapshot_manifest(payload: Dictionary) -> void:
	_resync_service.handle_snapshot_manifest(payload)

func handle_rpc_resync_snapshot_chunk(payload: Dictionary) -> void:
	_resync_service.handle_snapshot_chunk(payload)

func handle_rpc_resync_delta(payload: Dictionary) -> void:
	_resync_service.handle_delta(payload)

func handle_rpc_request_rejected(payload: Dictionary) -> void:
	var request_id := str(payload.get("request_id", ""))
	var code := str(payload.get("code", ""))
	var message := str(payload.get("message", ""))
	if _net != null and is_instance_valid(_net) and _net.has_method("take_pending_action_perf"):
		_net.take_pending_action_perf(request_id)
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("client.request_rejected.rx", {
			"request_id": request_id,
			"code": code,
			"room_code": str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper(),
			"message": message,
		})
	GameLog.warn(
		"NetClient",
		"RX RequestRejected request_id=%s code=%s message=%s"
			% [_safe_text(request_id), _safe_text(code), _safe_text(message)]
	)
	_net.request_rejected.emit(request_id, code, message)

func handle_rpc_full_archive_export_ready(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		GameLog.warn("NetClient", "RX FullArchiveExport ignored: archive type invalid")
		return
	if not _matches_payload_room_code(payload, "FullArchiveExport"):
		return
	var archive: Dictionary = Dictionary(archive_val).duplicate(true)
	GameLog.info(
		"NetClient",
		"RX FullArchiveExport request_id=%s room=%s commands=%d final_hash=%s"
			% [
				_safe_text(str(payload.get("request_id", ""))),
				_safe_text(str(payload.get("room_code", "")).to_upper()),
				Array(archive.get("commands", [])).size(),
				_short_hash(str(archive.get("final_hash", payload.get("final_hash", ""))))
			]
	)
	if _net != null and is_instance_valid(_net) and _net_has_signal("full_archive_export_ready"):
		_net.emit_signal("full_archive_export_ready", {
			"request_id": str(payload.get("request_id", "")),
			"room_code": str(payload.get("room_code", "")).strip_edges().to_upper(),
			"archive": archive,
			"final_hash": str(payload.get("final_hash", archive.get("final_hash", ""))).strip_edges(),
			"history_size": int(payload.get("history_size", Array(archive.get("commands", [])).size())),
		})

func _should_preserve_online_context_on_disconnect() -> bool:
	if _net == null or not is_instance_valid(_net):
		return false
	if not _net.has_method("should_preserve_online_context_on_disconnect"):
		return false
	return bool(_net.should_preserve_online_context_on_disconnect())

func _sync_online_resume_state_from_room_state(room_state: Dictionary) -> void:
	if NetContext == null:
		return
	if not NetContext.has_method("clear_online_resume_context"):
		return
	var room_code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	if room_code.is_empty():
		if _should_preserve_terminal_resume_record():
			return
		NetContext.clear_online_resume_context()
		return
	if not NetContext.has_method("has_online_resume_context"):
		return
	if not NetContext.has_online_resume_context():
		return
	if room_code != NetContext.get_online_resume_room_code():
		return
	if NetContext.has_method("sync_online_resume_context_from_room_state"):
		NetContext.sync_online_resume_context_from_room_state(room_state)
	elif NetContext.has_method("mark_online_resume_in_game"):
		NetContext.mark_online_resume_in_game(str(room_state.get("status", "")).strip_edges() == "InGame")

func _should_preserve_terminal_resume_record() -> bool:
	if NetContext == null:
		return false
	if not NetContext.has_method("has_online_resume_record"):
		return false
	if not NetContext.has_online_resume_record():
		return false
	if not NetContext.has_method("is_online_resume_allowed"):
		return false
	return not bool(NetContext.is_online_resume_allowed())

func _matches_payload_room_code(payload: Dictionary, channel_name: String) -> bool:
	var payload_room_code := str(payload.get("room_code", "")).strip_edges().to_upper()
	if payload_room_code.is_empty():
		GameLog.warn("NetClient", "RX %s ignored: room_code missing" % _safe_text(channel_name))
		return false
	var expected_room_code := _get_expected_online_room_code()
	if expected_room_code.is_empty():
		return true
	if payload_room_code != expected_room_code:
		GameLog.warn(
			"NetClient",
			"RX %s ignored: room mismatch expected=%s incoming=%s"
				% [_safe_text(channel_name), _safe_text(expected_room_code), _safe_text(payload_room_code)]
		)
		return false
	return true

func _get_expected_online_room_code() -> String:
	var room_code := str(NetContext.room_state.get("room_code", "")).strip_edges().to_upper()
	if not room_code.is_empty():
		return room_code
	if NetContext != null and NetContext.has_method("has_online_resume_context") and NetContext.has_online_resume_context():
		room_code = str(NetContext.get_online_resume_room_code()).strip_edges().to_upper()
		if not room_code.is_empty():
			return room_code
	return _get_connect_token_room_code_hint()

func _get_connect_token_room_code_hint() -> String:
	if NetContext == null:
		return ""
	var token := str(NetContext.connect_token).strip_edges()
	if token.is_empty():
		return ""
	var dot := token.find(".")
	if dot <= 0:
		return ""
	var encoded := token.substr(0, dot).replace("-", "+").replace("_", "/")
	var pad := encoded.length() % 4
	if pad != 0:
		encoded += "=".repeat(4 - pad)
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		return ""
	return str(Dictionary(parsed).get("room_code", "")).strip_edges().to_upper()

func _get_active_resume_engine():
	if Globals == null:
		return null
	var engine = Globals.current_game_engine
	if engine == null or not (engine is GameEngine):
		return null
	return engine

func _try_apply_pending_resync_delta() -> void:
	_resync_service.try_apply_pending_delta()

func _try_reuse_existing_online_client_engine(room_code: String, local_pid: int) -> GameEngine:
	var existing_engine = _get_active_resume_engine()
	if existing_engine == null or existing_engine.get_state() == null:
		return null
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	var reusing_for_reconnect := NetContext != null and NetContext.has_method("is_online_reconnecting") and NetContext.is_online_reconnecting()
	var reusing_for_room := not normalized_room_code.is_empty() and _get_online_client_engine_room_code() == normalized_room_code
	if not reusing_for_reconnect and not reusing_for_room:
		return null
	_mark_online_client_engine_ready(existing_engine, normalized_room_code, local_pid)
	if reusing_for_reconnect:
		GameLog.info("NetClient", "Online client reconnect ready: reusing existing engine")
	else:
		GameLog.info("NetClient", "Online client engine already ready room=%s" % _safe_text(normalized_room_code))
	return existing_engine

func _initialize_online_client_engine_from_config(config: Dictionary, room_code: String, local_pid: int) -> Result:
	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()

	var player_count := int(config.get("desired_player_count", 0))
	var seed := int(config.get("seed", 0))
	var base_dir := str(config.get("modules_v2_base_dir", "")).strip_edges()
	var base_dirs_read = ModuleDirSpecClass.parse_base_dirs(base_dir)
	if not base_dirs_read.ok:
		GameLog.warn("NetClient", "Online room modules_v2_base_dir 非 res://，已回退默认: %s" % base_dir)
		base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	var enabled_modules: Array[String] = []
	var mods_val = config.get("enabled_modules_v2", null)
	if mods_val is Array:
		for it in Array(mods_val):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			enabled_modules.append(s)

	var logo_choices: Array[int] = []
	var lc_val = config.get("restaurant_logo_choices_by_player", null)
	if lc_val is Array:
		for it2 in Array(lc_val):
			if it2 is int or it2 is float:
				logo_choices.append(int(it2))
	while logo_choices.size() < player_count:
		logo_choices.append(-1)
	var reserve_card_choices: Array[int] = []

	var engine = GameEngineClass.new()
	var config_overrides_val = config.get("game_config_overrides", null)
	if config_overrides_val is Dictionary:
		engine.set_game_config_overrides(Dictionary(config_overrides_val).duplicate(true))
	var option_overrides_val = config.get("game_option_overrides", null)
	if option_overrides_val is Dictionary:
		engine.set_game_option_overrides(Dictionary(option_overrides_val).duplicate(true))
	var init_r = engine.initialize(player_count, seed, enabled_modules, base_dir, reserve_card_choices, logo_choices)
	if not init_r.ok:
		GameLog.error(
			"NetClient",
			"Online client engine initialize failed players=%d seed=%d modules=%d base_dir=%s err=%s"
				% [player_count, seed, enabled_modules.size(), base_dir, init_r.error]
		)
		return Result.failure(str(init_r.error))

	_mark_online_client_engine_ready(engine, room_code, local_pid)
	GameLog.info(
		"NetClient",
		"Online client engine ready players=%d seed=%d modules=%d base_dir=%s"
			% [player_count, seed, enabled_modules.size(), base_dir]
	)
	return Result.success(engine)

func _try_bootstrap_online_client_engine_from_archive(archive: Dictionary) -> void:
	if archive.is_empty():
		return
	var room_code := _get_expected_online_room_code()
	var local_pid := -1
	var self_seat_val = NetContext.room_state.get("self_seat_index", null)
	if self_seat_val is int or self_seat_val is float:
		local_pid = int(self_seat_val)
	var existing_engine = _try_reuse_existing_online_client_engine(room_code, local_pid)
	if existing_engine != null:
		return
	var engine = GameEngineClass.new()
	var load_r: Result = _load_archive_for_online_client(engine, archive)
	if not load_r.ok:
		GameLog.error("NetClient", "Online client archive bootstrap failed: %s" % load_r.error)
		return
	_mark_online_client_engine_ready(engine, room_code, local_pid)
	if _is_resume_archive_room_state():
		var prepare_r := _online_resume_support.prepare_single_full_engine_runtime(
			engine,
			room_code,
			local_pid,
			_build_archive_meta(archive),
			true
		)
		if not prepare_r.ok:
			GameLog.warn("NetClient", "Online client resume archive cache prepare failed: %s" % prepare_r.error)
	GameLog.info(
		"NetClient",
		"Online client engine bootstrapped from archive room=%s commands=%d"
			% [_safe_text(room_code), int(engine.command_history.size())]
	)

func _mark_online_client_engine_ready(engine: GameEngine, room_code: String, local_pid: int) -> void:
	if engine == null or engine.get_state() == null:
		return
	OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)
	_get_online_resume_session_state().bind_runtime(engine, room_code, local_pid)
	if local_pid >= -1:
		NetContext.local_player_id = int(local_pid)
	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)
	_sync_online_resume_progress(engine)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state if NetContext != null else {})
	_set_online_client_engine_room_code(room_code)

func clear_online_resume_full_history_state() -> void:
	_clear_online_resume_full_history_state()

func get_online_resume_session_snapshot() -> Dictionary:
	return _get_online_resume_session_state().snapshot()

func get_online_resume_full_history_engine():
	return _online_resume_support.get_full_history_engine()

func ensure_online_resume_full_history_current() -> Result:
	return _online_resume_support.ensure_full_history_engine_current()

func ensure_online_resume_full_history_timeline_current(allow_incremental_append: bool = true) -> Result:
	return _online_resume_support.ensure_full_history_step_timeline_current(bool(allow_incremental_append))

func get_online_resume_full_history_step_timeline() -> Dictionary:
	return _online_resume_support.get_full_history_step_timeline()

func set_online_resume_full_history_step_timeline(timeline: Dictionary) -> void:
	_online_resume_support.set_full_history_step_timeline(timeline)

func get_online_resume_full_history_step_timeline_entries() -> Array[Dictionary]:
	return _online_resume_support.get_full_history_step_timeline_entries()

func set_online_resume_full_history_step_timeline_entries(entries: Array) -> void:
	_online_resume_support.set_full_history_step_timeline_entries(entries)

func load_archive_for_online_client(engine, archive: Dictionary) -> Result:
	if not (engine is GameEngine):
		return Result.failure("load archive failed: engine 为空")
	return _load_archive_for_online_client(engine, archive)

func record_online_resume_runtime_command_applied(cmd_dict: Dictionary, state_hash: String = "") -> void:
	var global_cmd_dict: Dictionary = _translate_runtime_command_dict_to_global(cmd_dict)
	if global_cmd_dict.is_empty():
		return
	_online_resume_support.record_online_resume_full_history_command(
		global_cmd_dict,
		state_hash,
		"runtime_command_applied"
	)

func mark_runtime_engine_as_full_history(engine) -> void:
	_online_resume_support.mark_runtime_engine_as_full_history(engine)

func map_online_resume_progress_from_engine(engine, checkpoint_id: String = "") -> Dictionary:
	return _online_resume_support.map_online_resume_progress_from_engine(engine, checkpoint_id)

func _get_online_resume_session_state():
	return _online_resume_support.get_session_state()

func _invalidate_full_history_engine(reason: String) -> void:
	_online_resume_support.invalidate_full_history_engine(reason)

func _clear_online_resume_full_history_state() -> void:
	_pending_resume_full_snapshot_payload = {}
	_pending_resume_full_snapshot_room_code = ""
	_pending_resume_full_snapshot_local_pid = -1
	_online_resume_support.clear_online_resume_full_history_state()

func _emit_resume_full_history_ready() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if not _net_has_signal("resume_full_history_ready"):
		return
	_net.emit_signal("resume_full_history_ready", _get_online_resume_session_state().snapshot())

func _emit_local_bootstrap_progress(state: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if not _net_has_signal("local_bootstrap_progress"):
		return
	_net.emit_signal("local_bootstrap_progress", Dictionary(state).duplicate(true))

func _consume_pending_resume_full_snapshot_payload(room_code: String) -> Dictionary:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if normalized_room_code.is_empty():
		return {}
	if _pending_resume_full_snapshot_room_code != normalized_room_code:
		return {}
	var payload := _pending_resume_full_snapshot_payload.duplicate(true)
	_pending_resume_full_snapshot_payload = {}
	_pending_resume_full_snapshot_room_code = ""
	return payload

func _get_pending_resume_full_snapshot_local_pid() -> int:
	return int(_pending_resume_full_snapshot_local_pid)

func _set_pending_resume_full_snapshot_local_pid(local_pid: int) -> void:
	_pending_resume_full_snapshot_local_pid = int(local_pid)

func _bootstrap_resume_full_snapshot_archive(
	archive: Dictionary,
	room_code: String,
	local_pid: int
) -> Result:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if archive.is_empty():
		return Result.failure("resume full snapshot archive missing")
	var engine = GameEngineClass.new()
	_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
		normalized_room_code,
		"archive_prepare",
		"正在校验恢复存档...",
		"正在校验存档格式并装配规则模块。",
		34.0
	))
	var load_span := OnlinePerfTraceClass.begin_span("client.resume_single_full.load_archive", {
		"room_code": normalized_room_code,
		"command_count": int(Array(archive.get("commands", [])).size()),
	})
	var load_r: Result = _load_archive_for_online_client(
		engine,
		archive,
		Callable(self, "_on_archive_load_progress").bind(normalized_room_code)
	)
	if not load_r.ok:
		OnlinePerfTraceClass.end_span(load_span, {
			"ok": false,
			"error": str(load_r.error),
			"room_code": normalized_room_code,
		})
		return load_r
	OnlinePerfTraceClass.end_span(load_span, {
		"ok": true,
		"room_code": normalized_room_code,
		"command_count": int(engine.command_history.size()),
		"current_index": int(engine.current_command_index),
	})
	_mark_online_client_engine_ready(engine, normalized_room_code, int(local_pid))
	_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
		normalized_room_code,
		"timeline_cache",
		"正在整理历史日志...",
		"正在构建历史步骤与日志缓存，进入对局后将直接复用。",
		84.0
	))
	var prepare_r := _online_resume_support.prepare_single_full_engine_runtime(
		engine,
		normalized_room_code,
		int(local_pid),
		_build_archive_meta(archive),
		true
	)
	if not prepare_r.ok:
		return Result.failure("single full-engine 准备失败: %s" % prepare_r.error)
	_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
		normalized_room_code,
		"bootstrap_ready",
		"本地恢复已完成",
		"完整历史、日志与时间线已准备完成，正在等待进入对局。",
		92.0
	))
	_pending_resume_full_snapshot_local_pid = -1
	return Result.success(engine)

func _on_archive_load_progress(progress: Dictionary, room_code: String) -> void:
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	var stage := str(progress.get("stage", "")).strip_edges()
	if stage == "prepare":
		_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
			normalized_room_code,
			"archive_prepare",
			"正在校验恢复存档...",
			"正在校验存档格式并装配规则模块。",
			36.0
		))
		return
	if stage != "replay" and stage != "finalize":
		return
	var current := int(progress.get("current", 0))
	var total := maxi(1, int(progress.get("total", 0)))
	var ratio := clampf(float(progress.get("ratio", 0.0)), 0.0, 1.0)
	var round_number := int(progress.get("round_number", -1))
	var phase_text := _format_resume_phase_progress_text(
		str(progress.get("phase", "")),
		str(progress.get("sub_phase", ""))
	)
	var detail := "正在回放历史 %d / %d" % [current, total]
	if round_number >= 0:
		detail += "（第 %d 回合" % round_number
		if not phase_text.is_empty():
			detail += " / %s" % phase_text
		detail += "）"
	elif not phase_text.is_empty():
		detail += "（%s）" % phase_text
	_emit_local_bootstrap_progress(_make_local_bootstrap_progress_state(
		normalized_room_code,
		"archive_replay",
		"正在回放恢复存档...",
		detail,
		40.0 + 38.0 * ratio
	))

func _make_local_bootstrap_progress_state(
	room_code: String,
	stage_key: String,
	stage_text: String,
	detail_text: String,
	progress_value: float
) -> Dictionary:
	return {
		"room_code": str(room_code).strip_edges().to_upper(),
		"title": "正在恢复联机对局...",
		"stage": str(stage_text).strip_edges(),
		"detail": str(detail_text).strip_edges(),
		"wait_text": "",
		"show_progress": true,
		"progress_value": clampf(float(progress_value), 0.0, 100.0),
		"progress_max": 100.0,
		"stage_key": str(stage_key).strip_edges(),
	}

func _format_resume_phase_progress_text(phase: String, sub_phase: String) -> String:
	var phase_name := str(RESUME_PHASE_DISPLAY_NAMES.get(str(phase).strip_edges(), str(phase).strip_edges())).strip_edges()
	var sub_phase_name := str(sub_phase).strip_edges()
	if phase_name.is_empty():
		return sub_phase_name
	if sub_phase_name.is_empty():
		return phase_name
	return "%s / %s" % [phase_name, sub_phase_name]

func _build_archive_meta(archive: Dictionary) -> Dictionary:
	return {
		"full_command_count": int(Array(archive.get("commands", [])).size()),
		"full_final_hash": str(archive.get("final_hash", "")).strip_edges(),
		"schema_version": int(archive.get("schema_version", 0)),
		"byte_size": int(var_to_bytes(archive).size()),
	}

func _is_resume_archive_room_state() -> bool:
	if NetContext == null:
		return false
	return str(NetContext.room_state.get("room_mode", "")).strip_edges() == "resume_archive"

func _load_archive_for_online_client(engine: GameEngine, archive: Dictionary, progress_callback: Callable = Callable()) -> Result:
	if engine == null:
		return Result.failure("load archive failed: engine 为空")
	if NetContext == null:
		return engine.load_from_archive(archive, progress_callback)

	var restore_mode := false
	var previous_mode = NetContext.mode
	if int(previous_mode) == int(NetContext.Mode.ONLINE_CLIENT):
		restore_mode = true
		NetContext.mode = NetContext.Mode.HOTSEAT

	var load_r: Result = engine.load_from_archive(archive, progress_callback)

	if restore_mode:
		NetContext.mode = previous_mode
	return load_r

func _sync_online_resume_progress(engine, checkpoint_id: String = "") -> void:
	if NetContext == null:
		return
	if engine == null:
		return
	var state = engine.get_state() if engine.has_method("get_state") else null
	if state == null or not state.has_method("compute_hash"):
		return
	var mapped: Dictionary = Dictionary(map_online_resume_progress_from_engine(engine, checkpoint_id)).duplicate(true)
	if not mapped.is_empty() and NetContext.has_method("set_online_resume_progress"):
		NetContext.set_online_resume_progress(
			int(mapped.get("last_applied_sequence", 0)),
			str(mapped.get("last_state_hash", state.compute_hash())),
			str(mapped.get("checkpoint_id", checkpoint_id))
		)
		return
	if NetContext.has_method("sync_online_resume_progress_from_engine"):
		NetContext.sync_online_resume_progress_from_engine(engine, checkpoint_id)

func _get_runtime_global_command_start_index() -> int:
	var session = _get_online_resume_session_state()
	if session.runtime_engine == null:
		return -1
	if Globals == null or Globals.current_game_engine != session.runtime_engine:
		return -1
	return int(session.runtime_anchor.get("global_command_start_index", -1))

func _translate_runtime_command_dict_to_global(cmd_dict: Dictionary) -> Dictionary:
	var translated: Dictionary = Dictionary(cmd_dict).duplicate(true)
	var global_start := _get_runtime_global_command_start_index()
	if global_start < 0:
		return translated
	var index_val = translated.get("index", null)
	if index_val is int or index_val is float:
		translated["index"] = int(index_val) + global_start
	return translated

func _translate_live_command_dict_to_runtime(cmd_dict: Dictionary) -> Dictionary:
	var translated: Dictionary = Dictionary(cmd_dict).duplicate(true)
	var global_start := _get_runtime_global_command_start_index()
	if global_start < 0:
		return translated
	var index_val = translated.get("index", null)
	if index_val is int or index_val is float:
		translated["index"] = int(index_val) - global_start
	return translated

func _translate_rewind_meta_to_runtime(payload: Dictionary) -> Dictionary:
	var translated: Dictionary = Dictionary(payload).duplicate(true)
	var global_start := _get_runtime_global_command_start_index()
	if global_start < 0:
		return translated
	if translated.get("target_index", null) is int or translated.get("target_index", null) is float:
		translated["target_index"] = int(translated.get("target_index", -1)) - global_start
	if translated.get("before_index", null) is int or translated.get("before_index", null) is float:
		translated["before_index"] = int(translated.get("before_index", -1)) - global_start
	if translated.get("history_size", null) is int or translated.get("history_size", null) is float:
		translated["history_size"] = int(translated.get("history_size", 0)) - global_start
	return translated

func _translate_resync_delta_to_runtime(payload: Dictionary) -> Dictionary:
	var translated: Dictionary = Dictionary(payload).duplicate(true)
	var global_start := _get_runtime_global_command_start_index()
	if global_start < 0:
		return translated
	if translated.get("from_sequence", null) is int or translated.get("from_sequence", null) is float:
		translated["from_sequence"] = int(translated.get("from_sequence", 0)) - global_start
	if translated.get("to_sequence", null) is int or translated.get("to_sequence", null) is float:
		translated["to_sequence"] = int(translated.get("to_sequence", 0)) - global_start
	if translated.get("final_sequence", null) is int or translated.get("final_sequence", null) is float:
		translated["final_sequence"] = int(translated.get("final_sequence", 0)) - global_start
	var entries_val = translated.get("entries", null)
	if entries_val is Array:
		var mapped_entries: Array[Dictionary] = []
		for item_val in Array(entries_val):
			if not (item_val is Dictionary):
				mapped_entries.append({})
				continue
			var entry: Dictionary = Dictionary(item_val).duplicate(true)
			if entry.get("sequence", null) is int or entry.get("sequence", null) is float:
				entry["sequence"] = int(entry.get("sequence", 0)) - global_start
			var cmd_val = entry.get("cmd", null)
			if cmd_val is Dictionary:
				entry["cmd"] = _translate_live_command_dict_to_runtime(Dictionary(cmd_val))
			mapped_entries.append(entry)
		translated["entries"] = mapped_entries
	return translated

func _get_online_client_engine_room_code() -> String:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return ""
	if not _net_has_property("_online_client_engine_room_code"):
		return ""
	return str((_net as Object).get("_online_client_engine_room_code")).strip_edges().to_upper()

func _set_online_client_engine_room_code(room_code: String) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	if not _net_has_property("_online_client_engine_room_code"):
		return
	(_net as Object).set("_online_client_engine_room_code", str(room_code).strip_edges().to_upper())

func _net_has_property(property_name: String) -> bool:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return false
	for item in (_net as Object).get_property_list():
		if not (item is Dictionary):
			continue
		if str(Dictionary(item).get("name", "")) == property_name:
			return true
	return false

func _net_has_signal(signal_name: String) -> bool:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return false
	return (_net as Object).has_signal(signal_name)

func _get_pending_rewind_to_turn_start_meta() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var meta_val = (_net as Object).get("_pending_rewind_to_turn_start_meta")
	if meta_val is Dictionary:
		return Dictionary(meta_val)
	return {}

func _set_pending_rewind_to_turn_start_meta(payload: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_rewind_to_turn_start_meta", Dictionary(payload).duplicate(true))

func _safe_text(value: String) -> String:
	var out := str(value).strip_edges()
	if out.is_empty():
		return "-"
	return out

func _short_hash(hash_value: String) -> String:
	var h := str(hash_value).strip_edges()
	if h.is_empty():
		return "-"
	if h.length() <= 12:
		return h
	return "%s..." % h.substr(0, 12)

func _room_state_brief(room_state: Dictionary) -> String:
	var room_code := _safe_text(str(room_state.get("room_code", "")).to_upper())
	var status := _safe_text(str(room_state.get("status", "")))
	var host_peer_id := int(room_state.get("host_peer_id", 0))
	var players := 0
	var spectators := 0
	var players_val = room_state.get("players", null)
	if players_val is Array:
		players = Array(players_val).size()
	var spectators_val = room_state.get("spectators", null)
	if spectators_val is Array:
		spectators = Array(spectators_val).size()
	return "room=%s status=%s host=%d players=%d spectators=%d" % [
		room_code,
		status,
		host_peer_id,
		players,
		spectators
	]
