# 联机会话层（Client/Server 共用 RPC 节点）
# 日志分级：高频链路（如轮询/命令流）使用 DEBUG，关键状态迁移使用 INFO/WARN/ERROR。
extends Node

const RoomManagerClass = preload("res://server/room_manager.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const CommandClass = preload("res://core/types/command.gd")
const ResultClass = preload("res://core/types/result.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const NetClientInternalClass = preload("res://autoload/net_client_internal.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const WEBSOCKET_BUFFER_SIZE_BYTES := 16 * 1024 * 1024
const WEBSOCKET_HEARTBEAT_INTERVAL_SEC := 15.0
const MAX_PENDING_ONLINE_PERF := 256

signal connected()
signal disconnected(reason: String)
signal room_list_updated(rooms: Array)
signal room_state_updated(room_state: Dictionary)
signal request_rejected(request_id: String, code: String, message: String)
signal game_started(payload: Dictionary)
signal match_bootstrap_local_failed(message: String)
signal local_bootstrap_progress(payload: Dictionary)
signal resume_full_history_ready(payload: Dictionary)
signal full_archive_export_ready(payload: Dictionary)
signal command_applied(cmd_dict: Dictionary, state_hash: String)
signal resync_archive_received(archive: Dictionary)
signal rewind_to_turn_start_meta_received(payload: Dictionary)
signal resync_delta_applied(payload: Dictionary)
signal resync_delta_failed(message: String)
signal server_room_directory_dirty()
signal server_round_autosave_requested(room_code: String, completed_round_number: int, state_hash: String, snapshot_kind: String)

var _peer: WebSocketMultiplayerPeer = null

var _room_manager = null
var _profile_by_peer_id: Dictionary = {} # peer_id -> profile

var _client_transport_connected: bool = false
var _request_counter: int = 0
var _pending_resync_archive: Dictionary = {}
var _pending_rewind_to_turn_start_meta: Dictionary = {}
var _pending_resync_snapshot_manifest: Dictionary = {}
var _pending_resync_snapshot_chunks: Dictionary = {}
var _pending_resync_delta: Dictionary = {}
var _resume_force_snapshot_once: bool = false
var _pending_resume_room_bootstrap: Dictionary = {}
var _online_client_engine_room_code: String = ""
var _pending_action_perf_by_request_id: Dictionary = {}
var _pending_action_perf_request_ids: Array[String] = []
var _pending_command_applied_perf_queue: Array[Dictionary] = []
var _internal = null

func _ready() -> void:
	_ensure_internal()
	_ensure_signal_connections()
	_refresh_multiplayer_peer_binding()

func _refresh_multiplayer_peer_binding() -> void:
	if not is_inside_tree():
		return
	multiplayer.multiplayer_peer = _peer if _peer != null else OfflineMultiplayerPeer.new()

func _ensure_internal() -> void:
	if _internal == null or not is_instance_valid(_internal):
		_internal = NetClientInternalClass.new()
		_internal.setup(self)

func start_server(port: int, bind_address: String = "0.0.0.0"):
	shutdown()
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = WEBSOCKET_BUFFER_SIZE_BYTES
	_peer.outbound_buffer_size = WEBSOCKET_BUFFER_SIZE_BYTES
	var err := _peer.create_server(port, bind_address)
	if err != OK:
		_peer = null
		GameLog.error("NetClient", "start_server failed bind=%s port=%d err=%s" % [bind_address, port, str(err)])
		NetContext.reset()
		return ResultClass.failure("WebSocket server create_server failed: %s" % str(err))

	_refresh_multiplayer_peer_binding()
	_room_manager = RoomManagerClass.new()
	_profile_by_peer_id = {}
	_client_transport_connected = false

	GameLog.info("NetClient", "Server started on %s:%d" % [bind_address, port])
	return ResultClass.success()

func connect_to_server(url: String, preserve_context: bool = false):
	var preserved_resume_room_bootstrap: Dictionary = {}
	if preserve_context and not _pending_resume_room_bootstrap.is_empty():
		preserved_resume_room_bootstrap = _pending_resume_room_bootstrap.duplicate(true)
	shutdown(not preserve_context)
	if preserve_context and not preserved_resume_room_bootstrap.is_empty():
		_pending_resume_room_bootstrap = preserved_resume_room_bootstrap
	var parsed := _parse_connect_token_from_url(str(url))
	var connect_url: String = str(parsed.get("url", str(url)))
	var connect_token: String = str(parsed.get("connect_token", ""))
	if connect_token.is_empty():
		GameLog.error("NetClient", "connect_to_server missing connect_token url=%s" % _safe_text(connect_url))
		if not preserve_context:
			NetContext.reset()
		return ResultClass.failure("connect_token required")
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = connect_url
	NetContext.connect_token = connect_token

	_peer = WebSocketMultiplayerPeer.new()
	_peer.inbound_buffer_size = WEBSOCKET_BUFFER_SIZE_BYTES
	_peer.outbound_buffer_size = WEBSOCKET_BUFFER_SIZE_BYTES
	var err := _peer.create_client(connect_url)
	if err != OK:
		_peer = null
		GameLog.error("NetClient", "connect_to_server failed url=%s err=%s" % [connect_url, str(err)])
		if not preserve_context:
			NetContext.reset()
		return ResultClass.failure("WebSocket client create_client failed: %s" % str(err))

	_refresh_multiplayer_peer_binding()
	_client_transport_connected = false
	GameLog.info("NetClient", "Connecting to %s" % connect_url)
	return ResultClass.success()

func _parse_connect_token_from_url(url: String) -> Dictionary:
	var out := {
		"url": str(url),
		"connect_token": "",
	}
	var s := str(url).strip_edges()
	if s.is_empty():
		return out

	var q_idx := s.find("?")
	if q_idx < 0:
		return out
	var base := s.substr(0, q_idx)
	var query := s.substr(q_idx + 1)
	if query.is_empty():
		out["url"] = base
		return out

	var parts: PackedStringArray = query.split("&", false)
	var kept: Array[String] = []
	for part in parts:
		var p := str(part).strip_edges()
		if p.is_empty():
			continue
		var kv := p.split("=", false, 1)
		var key := str(kv[0]).strip_edges()
		var value := str(kv[1]) if kv.size() >= 2 else ""
		if key == "token" or key == "connect_token":
			out["connect_token"] = value.uri_decode()
			continue
		kept.append(p)

	out["url"] = base + ("?" + "&".join(kept) if not kept.is_empty() else "")
	return out

func shutdown(reset_context: bool = true) -> void:
	var prev_mode := _mode_name(int(NetContext.mode))
	var prev_connected := _client_transport_connected
	var prev_server_url := _safe_text(str(NetContext.server_url))
	var prev_room_code := _safe_room_code(NetContext.room_state)
	var prev_room_list_count := NetContext.room_list.size() if NetContext.room_list is Array else 0
	var should_log := _peer != null \
		or prev_mode != "HOTSEAT" \
		or prev_connected \
		or prev_room_code != "-" \
		or prev_room_list_count > 0
	if _peer != null:
		_peer.close()
	_peer = null
	_room_manager = null
	_profile_by_peer_id = {}
	_client_transport_connected = false
	_pending_resync_archive = {}
	_pending_rewind_to_turn_start_meta = {}
	_pending_resync_snapshot_manifest = {}
	_pending_resync_snapshot_chunks = {}
	_pending_resync_delta = {}
	_resume_force_snapshot_once = false
	_pending_resume_room_bootstrap = {}
	_online_client_engine_room_code = ""
	_pending_action_perf_by_request_id = {}
	_pending_action_perf_request_ids.clear()
	_pending_command_applied_perf_queue.clear()
	if reset_context and _internal != null and is_instance_valid(_internal):
		_internal.clear_online_resume_full_history_state()
	_refresh_multiplayer_peer_binding()
	if reset_context:
		NetContext.reset()
	if should_log:
		GameLog.info(
			"NetClient",
			"Shutdown complete mode=%s connected=%s room=%s room_list=%d server=%s"
				% [prev_mode, str(prev_connected), prev_room_code, prev_room_list_count, prev_server_url]
		)

func is_online_client_connected() -> bool:
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT and _client_transport_connected

func should_preserve_online_context_on_disconnect() -> bool:
	if NetContext == null or not NetContext.has_method("has_online_resume_context"):
		return false
	if not NetContext.has_online_resume_context():
		return false
	return true

func mark_server_room_directory_dirty() -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	server_room_directory_dirty.emit()

func request_server_round_autosave(room_code: String, completed_round_number: int, state_hash: String = "", snapshot_kind: String = "round_end") -> void:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var normalized_room_code := str(room_code).strip_edges().to_upper()
	if normalized_room_code.is_empty():
		return
	var kind := str(snapshot_kind).strip_edges()
	if kind != "game_over":
		kind = "round_end"
	server_round_autosave_requested.emit(normalized_room_code, int(completed_round_number), str(state_hash).strip_edges(), kind)

func request_create_room(desired_player_count: int, room_password: String, config: Dictionary = {}) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"desired_player_count": desired_player_count,
		"join_policy": "password",
		"room_password": room_password,
	}
	for k in config.keys():
		payload[str(k)] = config.get(k, null)
	rpc_id(1, "rpc_create_room", payload)
	GameLog.info(
		"NetClient",
		"TX CreateRoom request_id=%s desired_player_count=%d has_password=%s config_keys=%s"
			% [
				request_id,
				desired_player_count,
				str(not room_password.is_empty()),
				str(Array(config.keys()))
			]
	)
	return request_id

func request_list_rooms() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_list_rooms", payload)
	GameLog.debug("NetClient", "TX ListRooms request_id=%s" % request_id)
	return request_id

func request_join_room(room_code: String, room_password: String) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"room_code": room_code,
		"room_password": room_password,
	}
	rpc_id(1, "rpc_join_room", payload)
	GameLog.info(
		"NetClient",
		"TX JoinRoom request_id=%s room_code=%s has_password=%s"
			% [request_id, _safe_text(str(room_code).to_upper()), str(not room_password.is_empty())]
	)
	return request_id

func request_leave_room() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("mark_resume_terminal"):
		OnlineSessionCoordinator.mark_resume_terminal("leave_room")
	clear_pending_online_resync_state()
	_online_client_engine_room_code = ""
	if _internal != null and is_instance_valid(_internal):
		_internal.clear_online_resume_full_history_state()
	rpc_id(1, "rpc_leave_room", payload)
	GameLog.info("NetClient", "TX LeaveRoom request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)])
	NetContext.room_state = {}
	room_state_updated.emit(NetContext.room_state)
	return request_id

func request_forfeit_and_leave_room() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	if OnlineSessionCoordinator != null and OnlineSessionCoordinator.has_method("mark_resume_terminal"):
		OnlineSessionCoordinator.mark_resume_terminal("forfeit_and_leave_room")
	clear_pending_online_resync_state()
	_online_client_engine_room_code = ""
	if _internal != null and is_instance_valid(_internal):
		_internal.clear_online_resume_full_history_state()
	rpc_id(1, "rpc_forfeit_and_leave_room", payload)
	GameLog.info(
		"NetClient",
		"TX ForfeitAndLeaveRoom request_id=%s room=%s"
			% [request_id, _safe_room_code(NetContext.room_state)]
	)
	return request_id

func request_update_room_config(config_patch: Dictionary) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"config_patch": config_patch.duplicate(true),
	}
	rpc_id(1, "rpc_update_room_config", payload)
	GameLog.info(
		"NetClient",
		"TX UpdateRoomConfig request_id=%s room=%s patch_keys=%s"
			% [request_id, _safe_room_code(NetContext.room_state), str(Array(config_patch.keys()))]
	)
	return request_id

func request_assign_room_seat(user_id: String, seat_index: int) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"user_id": str(user_id).strip_edges(),
		"seat_index": int(seat_index),
	}
	rpc_id(1, "rpc_assign_room_seat", payload)
	GameLog.info(
		"NetClient",
		"TX AssignRoomSeat request_id=%s room=%s user_id=%s seat=%d"
			% [request_id, _safe_room_code(NetContext.room_state), _safe_text(str(user_id)), int(seat_index)]
	)
	return request_id

func request_unassign_room_seat(seat_index: int) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"user_id": "",
		"seat_index": int(seat_index),
	}
	rpc_id(1, "rpc_assign_room_seat", payload)
	GameLog.info(
		"NetClient",
		"TX UnassignRoomSeat request_id=%s room=%s seat=%d"
			% [request_id, _safe_room_code(NetContext.room_state), int(seat_index)]
	)
	return request_id

func set_pending_resume_room_bootstrap(bootstrap: Dictionary) -> void:
	_pending_resume_room_bootstrap = Dictionary(bootstrap).duplicate(true)

func take_pending_resume_room_bootstrap() -> Dictionary:
	var out: Dictionary = _pending_resume_room_bootstrap.duplicate(true)
	_pending_resume_room_bootstrap = {}
	return out

func clear_pending_resume_room_bootstrap() -> void:
	_pending_resume_room_bootstrap = {}

func clear_online_resume_full_history_state() -> void:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		_internal.clear_online_resume_full_history_state()

func clear_online_resume_dual_engine_state() -> void:
	clear_online_resume_full_history_state()

func get_online_resume_session_snapshot() -> Dictionary:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return Dictionary(_internal.get_online_resume_session_snapshot()).duplicate(true)
	return {}

func get_online_resume_full_history_engine():
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return _internal.get_online_resume_full_history_engine()
	return null

func ensure_online_resume_full_history_current() -> Result:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return _internal.ensure_online_resume_full_history_current()
	return ResultClass.failure("online resume full history unavailable")

func ensure_online_resume_full_history_timeline_current(allow_incremental_append: bool = true) -> Result:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return _internal.ensure_online_resume_full_history_timeline_current(bool(allow_incremental_append))
	return ResultClass.failure("online resume full history timeline unavailable")

func get_online_resume_full_history_step_timeline() -> Dictionary:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return Dictionary(_internal.get_online_resume_full_history_step_timeline()).duplicate(false)
	return {}

func set_online_resume_full_history_step_timeline(timeline: Dictionary) -> void:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		_internal.set_online_resume_full_history_step_timeline(Dictionary(timeline).duplicate(false))

func get_online_resume_full_history_step_timeline_entries() -> Array[Dictionary]:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return _internal.get_online_resume_full_history_step_timeline_entries()
	return []

func set_online_resume_full_history_step_timeline_entries(entries: Array) -> void:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		_internal.set_online_resume_full_history_step_timeline_entries(entries)

func load_archive_for_online_client(engine, archive: Dictionary) -> Result:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return _internal.load_archive_for_online_client(engine, archive)
	if engine == null:
		return ResultClass.failure("load archive failed: engine 为空")
	return engine.load_from_archive(archive)

func record_online_resume_runtime_command_applied(cmd_dict: Dictionary, state_hash: String = "") -> void:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		_internal.record_online_resume_runtime_command_applied(cmd_dict, state_hash)

func map_online_resume_progress_from_engine(engine, checkpoint_id: String = "") -> Dictionary:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		return Dictionary(_internal.map_online_resume_progress_from_engine(engine, checkpoint_id)).duplicate(true)
	return {}

func mark_runtime_engine_as_full_history(engine) -> void:
	_ensure_internal()
	if _internal != null and is_instance_valid(_internal):
		_internal.mark_runtime_engine_as_full_history(engine)

func request_update_player_profile(profile: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	if not is_online_client_connected():
		return
	if profile is Dictionary:
		NetContext.player_profile = Dictionary(profile).duplicate(true)
	GameLog.debug(
		"NetClient",
		"TX UpdatePlayerProfile name=%s color_index=%d restaurant_logo_id=%d"
			% [
				_safe_text(str(NetContext.player_profile.get("name", ""))),
				int(NetContext.player_profile.get("color_index", -1)),
				int(NetContext.player_profile.get("restaurant_logo_id", -1))
			]
	)
	_send_client_hello()

func request_start_game() -> String:
	var request_id := _next_request_id()
	var payload := {"request_id": request_id}
	rpc_id(1, "rpc_start_game", payload)
	GameLog.info("NetClient", "TX StartGame request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)])
	return request_id

func request_match_bootstrap_ready(bootstrap_id: String) -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	var payload := {
		"request_id": request_id,
		"bootstrap_id": str(bootstrap_id).strip_edges(),
	}
	rpc_id(1, "rpc_match_bootstrap_ready", payload)
	GameLog.info(
		"NetClient",
		"TX MatchBootstrapReady request_id=%s bootstrap_id=%s room=%s"
			% [request_id, _safe_text(str(payload.get("bootstrap_id", ""))), _safe_room_code(NetContext.room_state)]
	)
	return request_id

func request_match_bootstrap_failed(bootstrap_id: String, reason: String) -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	var payload := {
		"request_id": request_id,
		"bootstrap_id": str(bootstrap_id).strip_edges(),
		"reason": str(reason).strip_edges(),
	}
	rpc_id(1, "rpc_match_bootstrap_failed", payload)
	GameLog.warn(
		"NetClient",
		"TX MatchBootstrapFailed request_id=%s bootstrap_id=%s room=%s reason=%s"
			% [
				request_id,
				_safe_text(str(payload.get("bootstrap_id", ""))),
				_safe_room_code(NetContext.room_state),
				_safe_text(str(payload.get("reason", ""))),
			]
	)
	return request_id

func request_action(action_id: String, params: Dictionary) -> String:
	var request_id := _next_request_id()
	var payload := {
		"request_id": request_id,
		"action_id": action_id,
		"params": params.duplicate(true),
	}
	if OnlinePerfTraceClass.enabled():
		var perf_meta := {
			"request_id": request_id,
			"action_id": str(action_id).strip_edges(),
			"client_request_unix_ms": OnlinePerfTraceClass.now_unix_ms(),
			"client_request_mono_usec": OnlinePerfTraceClass.now_mono_usec(),
			"client_peer_id": int(multiplayer.get_unique_id()) if multiplayer != null else 0,
			"room_code": _safe_room_code(NetContext.room_state),
			"local_player_id": int(NetContext.local_player_id),
		}
		payload["perf"] = perf_meta.duplicate(true)
		_remember_pending_action_perf(request_id, perf_meta)
		OnlinePerfTraceClass.emit_event("client.action_request.tx", {
			"request_id": request_id,
			"action_id": str(action_id).strip_edges(),
			"room_code": _safe_room_code(NetContext.room_state),
			"local_player_id": int(NetContext.local_player_id),
			"params_keys": Array(params.keys()),
		})
	rpc_id(1, "rpc_action_request", payload)
	GameLog.debug(
		"NetClient",
		"TX ActionRequest request_id=%s action=%s params_keys=%s"
			% [request_id, _safe_text(action_id), str(Array(params.keys()))]
	)
	return request_id

func request_resume_force_snapshot_once() -> void:
	_resume_force_snapshot_once = true

func request_resync(force_snapshot: bool = false) -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	if Globals != null and Globals.current_game_engine != null:
		if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
			NetContext.sync_online_resume_progress_from_engine(Globals.current_game_engine)
	var use_force_snapshot := bool(force_snapshot) or _resume_force_snapshot_once
	_resume_force_snapshot_once = false
	var payload := {"request_id": request_id}
	if NetContext != null and NetContext.has_method("build_online_resume_cursor"):
		var cursor: Dictionary = NetContext.build_online_resume_cursor(use_force_snapshot)
		if not cursor.is_empty():
			payload["resume_cursor"] = cursor
	rpc_id(1, "rpc_resync_request", payload)
	GameLog.warn(
		"NetClient",
		"TX ResyncRequest request_id=%s room=%s force_snapshot=%s"
			% [request_id, _safe_room_code(NetContext.room_state), str(use_force_snapshot)]
	)
	return request_id

func request_rewind_to_turn_start() -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	rpc_id(1, "rpc_rewind_to_turn_start", {"request_id": request_id})
	GameLog.warn(
		"NetClient",
		"TX RewindToTurnStart request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)]
	)
	return request_id

func request_full_archive_export() -> String:
	var request_id := _next_request_id()
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return request_id
	if not is_online_client_connected():
		return request_id
	rpc_id(1, "rpc_request_full_archive_export", {"request_id": request_id})
	GameLog.info(
		"NetClient",
		"TX FullArchiveExport request_id=%s room=%s" % [request_id, _safe_room_code(NetContext.room_state)]
	)
	return request_id

func take_pending_resync_archive() -> Dictionary:
	var out: Dictionary = _pending_resync_archive.duplicate(true)
	_pending_resync_archive = {}
	if not out.is_empty():
		GameLog.debug("NetClient", "take_pending_resync_archive keys=%s" % str(Array(out.keys())))
	return out

func clear_pending_resync_archive() -> void:
	if not _pending_resync_archive.is_empty():
		GameLog.debug("NetClient", "clear_pending_resync_archive keys=%s" % str(Array(_pending_resync_archive.keys())))
	_pending_resync_archive = {}

func take_pending_rewind_to_turn_start_meta() -> Dictionary:
	var out: Dictionary = _pending_rewind_to_turn_start_meta.duplicate(true)
	_pending_rewind_to_turn_start_meta = {}
	if not out.is_empty():
		GameLog.debug("NetClient", "take_pending_rewind_to_turn_start_meta keys=%s" % str(Array(out.keys())))
	return out

func clear_pending_rewind_to_turn_start_meta() -> void:
	if not _pending_rewind_to_turn_start_meta.is_empty():
		GameLog.debug(
			"NetClient",
			"clear_pending_rewind_to_turn_start_meta keys=%s"
				% str(Array(_pending_rewind_to_turn_start_meta.keys()))
		)
	_pending_rewind_to_turn_start_meta = {}

func clear_pending_online_resync_state() -> void:
	var should_log := not _pending_resync_archive.is_empty() \
		or not _pending_rewind_to_turn_start_meta.is_empty() \
		or not _pending_resync_snapshot_manifest.is_empty() \
		or not _pending_resync_snapshot_chunks.is_empty() \
		or not _pending_resync_delta.is_empty() \
		or _resume_force_snapshot_once
	if should_log:
		GameLog.debug("NetClient", "clear_pending_online_resync_state")
	clear_pending_resync_archive()
	clear_pending_rewind_to_turn_start_meta()
	_pending_resync_snapshot_manifest = {}
	_pending_resync_snapshot_chunks = {}
	_pending_resync_delta = {}
	_resume_force_snapshot_once = false

@rpc("any_peer", "reliable")
func rpc_client_hello(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_client_hello(request)

@rpc("any_peer", "reliable")
func rpc_list_rooms(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_list_rooms(request)

@rpc("any_peer", "reliable")
func rpc_create_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_create_room(request)

@rpc("any_peer", "reliable")
func rpc_join_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_join_room(request)

@rpc("any_peer", "reliable")
func rpc_update_room_config(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_update_room_config(request)

@rpc("any_peer", "reliable")
func rpc_assign_room_seat(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_assign_room_seat(request)

@rpc("any_peer", "reliable")
func rpc_leave_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_leave_room(request)

@rpc("any_peer", "reliable")
func rpc_forfeit_and_leave_room(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_forfeit_and_leave_room(request)

@rpc("any_peer", "reliable")
func rpc_start_game(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_start_game(request)

@rpc("any_peer", "reliable")
func rpc_match_bootstrap_ready(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_match_bootstrap_ready(request)

@rpc("any_peer", "reliable")
func rpc_match_bootstrap_failed(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_match_bootstrap_failed(request)

@rpc("any_peer", "reliable")
func rpc_action_request(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_action_request(request)

@rpc("any_peer", "reliable")
func rpc_resync_request(_request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_request(_request)

@rpc("any_peer", "reliable")
func rpc_rewind_to_turn_start(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_rewind_to_turn_start(request)

@rpc("any_peer", "reliable")
func rpc_request_full_archive_export(request: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_request_full_archive_export(request)

@rpc("authority", "reliable")
func rpc_room_state(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_room_state(payload)

@rpc("authority", "reliable")
func rpc_room_list(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_room_list(payload)

@rpc("authority", "reliable")
func rpc_game_started(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_game_started(payload)

@rpc("authority", "reliable")
func rpc_command_applied(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_command_applied(payload)

@rpc("authority", "reliable")
func rpc_resync_archive(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_archive(payload)

@rpc("authority", "reliable")
func rpc_rewind_to_turn_start_meta(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_rewind_to_turn_start_meta(payload)

@rpc("authority", "reliable")
func rpc_resync_snapshot_manifest(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_snapshot_manifest(payload)

@rpc("authority", "reliable")
func rpc_resync_snapshot_chunk(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_snapshot_chunk(payload)

@rpc("authority", "reliable")
func rpc_resync_delta(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_resync_delta(payload)

@rpc("authority", "reliable")
func rpc_request_rejected(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_request_rejected(payload)

@rpc("authority", "reliable")
func rpc_full_archive_export_ready(payload: Dictionary) -> void:
	_ensure_internal()
	_internal.handle_rpc_full_archive_export_ready(payload)

func _ensure_signal_connections() -> void:
	_ensure_internal()
	_internal.ensure_signal_connections()

func _on_peer_connected(peer_id: int) -> void:
	_configure_websocket_keepalive(peer_id)
	_ensure_internal()
	_internal.on_peer_connected(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_ensure_internal()
	_internal.on_peer_disconnected(peer_id)

func _on_connected_to_server() -> void:
	_configure_websocket_keepalive(1)
	_ensure_internal()
	_internal.on_connected_to_server()

func _on_connection_failed() -> void:
	_ensure_internal()
	_internal.on_connection_failed()

func _on_server_disconnected() -> void:
	_ensure_internal()
	_internal.on_server_disconnected()

func _send_client_hello() -> void:
	_ensure_internal()
	_internal.send_client_hello()

func _send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	_ensure_internal()
	_internal.send_request_rejected(peer_id, request_id, code, message)

func _broadcast_room_state(room) -> void:
	_ensure_internal()
	_internal.broadcast_room_state(room)

func _empty_room_state() -> Dictionary:
	_ensure_internal()
	return _internal.empty_room_state()

func _send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	_ensure_internal()
	_internal.send_room_list_to_peer(peer_id, request_id)

func _broadcast_room_list(request_id: String) -> void:
	_ensure_internal()
	_internal.broadcast_room_list(request_id)

func _broadcast_command_applied(room, cmd) -> void:
	_ensure_internal()
	_internal.broadcast_command_applied(room, cmd)

func _server_is_player_forfeited(state, player_id: int) -> bool:
	_ensure_internal()
	return _internal.server_is_player_forfeited(state, player_id)

func _server_pick_order_of_business_position(state) -> int:
	_ensure_internal()
	return _internal.server_pick_order_of_business_position(state)

func _server_try_auto_submit_forfeited_restructuring(room) -> bool:
	_ensure_internal()
	return _internal.server_try_auto_submit_forfeited_restructuring(room)

func _server_drain_forfeited_auto_steps(room) -> void:
	_ensure_internal()
	_internal.server_drain_forfeited_auto_steps(room)

func _remember_pending_action_perf(request_id: String, perf_meta: Dictionary) -> void:
	var rid := str(request_id).strip_edges()
	if rid.is_empty():
		return
	_pending_action_perf_by_request_id[rid] = perf_meta.duplicate(true)
	_pending_action_perf_request_ids.append(rid)
	while _pending_action_perf_request_ids.size() > MAX_PENDING_ONLINE_PERF:
		var old_id := str(_pending_action_perf_request_ids.pop_front()).strip_edges()
		if old_id.is_empty():
			continue
		_pending_action_perf_by_request_id.erase(old_id)

func take_pending_action_perf(request_id: String) -> Dictionary:
	var rid := str(request_id).strip_edges()
	if rid.is_empty():
		return {}
	var out: Dictionary = Dictionary(_pending_action_perf_by_request_id.get(rid, {})).duplicate(true)
	if _pending_action_perf_by_request_id.has(rid):
		_pending_action_perf_by_request_id.erase(rid)
	var idx := _pending_action_perf_request_ids.find(rid)
	if idx >= 0:
		_pending_action_perf_request_ids.remove_at(idx)
	return out

func enqueue_command_applied_perf_meta(perf_meta: Dictionary) -> void:
	if perf_meta == null or perf_meta.is_empty():
		return
	_pending_command_applied_perf_queue.append(perf_meta.duplicate(true))
	while _pending_command_applied_perf_queue.size() > MAX_PENDING_ONLINE_PERF:
		_pending_command_applied_perf_queue.pop_front()

func consume_next_command_applied_perf_meta() -> Dictionary:
	if _pending_command_applied_perf_queue.is_empty():
		return {}
	return Dictionary(_pending_command_applied_perf_queue.pop_front()).duplicate(true)

func _next_request_id() -> String:
	_request_counter += 1
	return "%d-%d" % [Time.get_unix_time_from_system(), _request_counter]

func _configure_websocket_keepalive(peer_id: int) -> void:
	if _peer == null:
		return
	if peer_id <= 0:
		return
	if not _peer.has_method("get_peer"):
		return
	var raw_peer = _peer.get_peer(peer_id)
	if raw_peer == null:
		return
	if not (raw_peer is WebSocketPeer):
		return
	var ws_peer: WebSocketPeer = raw_peer
	if is_equal_approx(float(ws_peer.heartbeat_interval), WEBSOCKET_HEARTBEAT_INTERVAL_SEC):
		return
	ws_peer.heartbeat_interval = WEBSOCKET_HEARTBEAT_INTERVAL_SEC
	GameLog.debug(
		"NetClient",
		"Configured WebSocket heartbeat peer=%d interval=%.1fs mode=%s"
			% [peer_id, WEBSOCKET_HEARTBEAT_INTERVAL_SEC, _mode_name(int(NetContext.mode))]
	)

func _mode_name(mode_value: int) -> String:
	match mode_value:
		NetContext.Mode.ONLINE_CLIENT:
			return "ONLINE_CLIENT"
		NetContext.Mode.ONLINE_SERVER:
			return "ONLINE_SERVER"
		_:
			return "HOTSEAT"

func _safe_text(value: String) -> String:
	var s := str(value).strip_edges()
	if s.is_empty():
		return "-"
	return s

func _safe_room_code(room_state: Dictionary) -> String:
	var code := str(room_state.get("room_code", "")).strip_edges().to_upper()
	if code.is_empty():
		return "-"
	return code
