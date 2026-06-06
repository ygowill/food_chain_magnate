# NetClient：Server-only 逻辑（room 管理 + 广播 + forfeit 自动推进）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：广播与逐命令同步等热路径走 DEBUG，异常/回灌/拒绝请求保留 WARN/ERROR。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const GameStartedPayloadsClass = preload("res://autoload/net_client/game_started_payloads.gd")
const ServerDisconnectGraceServiceClass = preload("res://autoload/net_client/server_disconnect_grace_service.gd")
const ServerLogFormatClass = preload("res://autoload/net_client/server_log_format.gd")
const ServerMatchFinalizePayloadBuilderClass = preload("res://autoload/net_client/server_match_finalize_payload_builder.gd")
const ServerResyncServiceClass = preload("res://autoload/net_client/server_resync_service.gd")
const GameOverWinnerRulesClass = preload("res://core/rules/game_over_winner_rules.gd")
const ResultClass = preload("res://core/types/result.gd")
const DEFAULT_PLATFORM_BACKEND_URL := "http://127.0.0.1:8000"
const DEFAULT_INTERNAL_API_SECRET := "dev-internal-secret-change-in-production"
const DEFAULT_RESTAURANT_LOGO_COUNT := 6
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"
const DEFAULT_DISCONNECT_GRACE_PERIOD_SEC := 120.0

var _net = null
var _disconnect_grace_service = ServerDisconnectGraceServiceClass.new()
var _resync_service = ServerResyncServiceClass.new()
var connect_token_secret_override: String = ""
var disconnect_grace_period_sec_override: float = -1.0

func setup(net_client) -> void:
	_net = net_client
	_disconnect_grace_service.setup(net_client, {
		"get_grace_period_sec": Callable(self, "_get_disconnect_grace_period_sec"),
		"resolve_actor_id_for_peer": Callable(self, "_resolve_actor_id_for_peer"),
		"mark_room_directory_dirty": Callable(self, "_mark_room_directory_dirty"),
		"broadcast_room_state": Callable(self, "broadcast_room_state"),
		"broadcast_room_list": Callable(self, "broadcast_room_list"),
		"broadcast_command_applied": Callable(self, "broadcast_command_applied"),
		"drain_forfeited_auto_steps": Callable(self, "server_drain_forfeited_auto_steps"),
		"try_finalize_match": Callable(self, "_try_finalize_match_if_game_over"),
		"is_player_forfeited": Callable(self, "server_is_player_forfeited"),
	})
	_resync_service.setup(net_client)

func _get_connect_token_secret() -> String:
	if not connect_token_secret_override.is_empty():
		return str(connect_token_secret_override)
	return str(OS.get_environment("HMAC_SECRET"))

func _get_disconnect_grace_period_sec() -> float:
	if disconnect_grace_period_sec_override >= 0.0:
		return float(disconnect_grace_period_sec_override)
	var raw := str(OS.get_environment("DISCONNECT_GRACE_PERIOD_SEC")).strip_edges()
	if not raw.is_empty() and raw.is_valid_float():
		return maxf(0.0, float(raw))
	return DEFAULT_DISCONNECT_GRACE_PERIOD_SEC

func _get_platform_backend_url() -> String:
	var url := str(OS.get_environment("PLATFORM_BACKEND_URL")).strip_edges()
	if url.is_empty():
		return DEFAULT_PLATFORM_BACKEND_URL
	return url

func _get_internal_api_secret() -> String:
	var secret := str(OS.get_environment("INTERNAL_API_SECRET")).strip_edges()
	if secret.is_empty():
		return DEFAULT_INTERNAL_API_SECRET
	return secret

func _mark_room_directory_dirty() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if not _net.has_method("mark_server_room_directory_dirty"):
		return
	_net.mark_server_room_directory_dirty()

func _handle_replaced_peer(payload: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var replaced_peer_id := int(payload.get("replaced_peer_id", 0))
	if replaced_peer_id <= 0:
		return
	_resync_service.forget_peer(replaced_peer_id)
	_net._profile_by_peer_id.erase(replaced_peer_id)
	_net.rpc_id(replaced_peer_id, "rpc_room_state", empty_room_state())

func _schedule_finalize_retry(room_code: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var tree = _net.get_tree()
	if tree == null or not (tree is SceneTree):
		return
	var timer = (tree as SceneTree).create_timer(5.0)
	timer.timeout.connect(Callable(self, "_retry_finalize_room").bind(str(room_code).strip_edges().to_upper()))

func _retry_finalize_room(room_code: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if _net._room_manager == null or not (_net._room_manager.rooms is Dictionary):
		return
	var room = _net._room_manager.rooms.get(str(room_code).strip_edges().to_upper(), null)
	if room == null:
		return
	_try_finalize_match_if_game_over(room)

func _try_finalize_match_if_game_over(room) -> void:
	if room == null or room.game_engine == null:
		return
	var state = room.game_engine.get_state()
	if state == null:
		return
	if str(state.phase) != DefsClass.PHASE_GAME_OVER:
		return

	if int(room.ended_at_unix_sec) <= 0:
		room.ended_at_unix_sec = int(Time.get_unix_time_from_system())
	if str(room.ended_at_iso).strip_edges().is_empty():
		room.ended_at_iso = Time.get_datetime_string_from_system()

	var status_changed := false
	if str(room.status) != "Ended":
		room.status = "Ended"
		status_changed = true
		if room.has_method("_touch"):
			room._touch()
	if status_changed:
		broadcast_room_state(room)
		broadcast_room_list("")

	if bool(room.match_finalize_reported) or bool(room.match_finalize_in_flight):
		return
	room.match_finalize_in_flight = true
	call_deferred("_post_finalize_match", room)

func _post_finalize_match(room) -> void:
	if room == null:
		return
	if room.game_engine == null:
		room.match_finalize_in_flight = false
		return

	var backend_url := _get_platform_backend_url()
	var internal_secret := _get_internal_api_secret()
	if backend_url.is_empty() or internal_secret.is_empty():
		room.match_finalize_in_flight = false
		GameLog.warn(
			"NetClient",
			"Finalize skipped due to backend/internal secret missing room=%s"
				% _safe_text(str(room.room_code))
		)
		_schedule_finalize_retry(str(room.room_code))
		return

	var state = room.game_engine.get_state()
	if state == null:
		room.match_finalize_in_flight = false
		return

	var winner_player_id := -1
	var winner_r: Result = GameOverWinnerRulesClass.pick_winner_player_id(state)
	if winner_r.ok:
		winner_player_id = int(winner_r.value)
	else:
		GameLog.warn(
			"NetClient",
			"Finalize winner fallback room=%s err=%s"
				% [_safe_text(str(room.room_code)), winner_r.error]
		)

	var started_unix := int(room.started_at_unix_sec)
	var ended_unix := int(room.ended_at_unix_sec)
	if ended_unix <= 0:
		ended_unix = int(Time.get_unix_time_from_system())
	if started_unix <= 0:
		started_unix = ended_unix
	var duration_sec := maxi(0, ended_unix - started_unix)
	var started_at := str(room.started_at_iso).strip_edges()
	if started_at.is_empty():
		started_at = Time.get_datetime_string_from_system()
	var ended_at := str(room.ended_at_iso).strip_edges()
	if ended_at.is_empty():
		ended_at = Time.get_datetime_string_from_system()

	var participants := ServerMatchFinalizePayloadBuilderClass.build_finalize_participants(room, state, winner_player_id)
	var summary_payload := ServerMatchFinalizePayloadBuilderClass.build_match_summary_payload(state)
	var summary_json := JSON.stringify(summary_payload)

	var game_version := str(ProjectSettings.get_setting("application/config/version", "0.0.0")).strip_edges()
	if game_version.is_empty():
		game_version = "0.0.0"
	var schema_version := ""
	var final_hash := str(state.compute_hash()) if state.has_method("compute_hash") else ""
	var replay_archive_json := ""
	var replay_size_bytes: Variant = null
	var replay_checksum := ""

	var archive_r = room.game_engine.create_archive()
	if archive_r.ok and archive_r.value is Dictionary:
		var archive: Dictionary = Dictionary(archive_r.value)
		replay_archive_json = JSON.stringify(archive)
		schema_version = str(archive.get("schema_version", ""))
		game_version = str(archive.get("game_version", game_version)).strip_edges()
		final_hash = str(archive.get("final_hash", final_hash)).strip_edges()
		replay_size_bytes = replay_archive_json.to_utf8_buffer().size()
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(replay_archive_json.to_utf8_buffer())
		replay_checksum = ctx.finish().hex_encode()
	else:
		GameLog.warn(
			"NetClient",
			"Finalize without replay archive room=%s err=%s"
				% [_safe_text(str(room.room_code)), archive_r.error]
		)

	var seed_text := str(room.config.get("seed", "")).strip_edges()
	if seed_text.is_empty():
		seed_text = str(int(state.seed))

	var payload := {
		"room_code": str(room.room_code),
		"status": "completed",
		"started_at": started_at,
		"ended_at": ended_at,
		"duration_sec": duration_sec,
		"player_count": int(room.get_player_count()) if room.has_method("get_player_count") else participants.size(),
		"seed": seed_text,
		"schema_version": schema_version,
		"game_version": game_version,
		"final_hash": final_hash,
		"summary_json": summary_json,
		"participants": participants,
	}
	if not replay_archive_json.is_empty():
		payload["replay_archive_json"] = replay_archive_json
	if replay_size_bytes != null:
		payload["replay_size_bytes"] = int(replay_size_bytes)
	if not replay_checksum.is_empty():
		payload["replay_checksum"] = replay_checksum

	var base := str(backend_url)
	if base.ends_with("/"):
		base = base.trim_suffix("/")
	var url := base + "/internal/matches/finalize"
	var headers := [
		"Content-Type: application/json",
		"X-Internal-Secret: " + internal_secret,
	]

	if _net == null or not is_instance_valid(_net):
		room.match_finalize_in_flight = false
		return
	if not (_net is Node):
		room.match_finalize_in_flight = false
		GameLog.warn(
			"NetClient",
			"Finalize skipped: transport is not a Node room=%s"
				% _safe_text(str(room.room_code))
		)
		return

	var http := HTTPRequest.new()
	_net.add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()
		room.match_finalize_in_flight = false
		GameLog.error(
			"NetClient",
			"Finalize request_failed room=%s err=%s"
				% [_safe_text(str(room.room_code)), str(err)]
		)
		_schedule_finalize_retry(str(room.room_code))
		return
	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = int(result[1])
	var response_text := PackedByteArray(result[3]).get_string_from_utf8()
	if response_code < 200 or response_code >= 300:
		room.match_finalize_in_flight = false
		GameLog.error(
			"NetClient",
			"Finalize failed room=%s status=%d body=%s"
				% [_safe_text(str(room.room_code)), response_code, _safe_text(response_text)]
		)
		_schedule_finalize_retry(str(room.room_code))
		return

	var parsed = JSON.parse_string(response_text)
	var match_id := ""
	if parsed is Dictionary:
		match_id = str(Dictionary(parsed).get("match_id", "")).strip_edges()

	room.match_finalize_in_flight = false
	room.match_finalize_reported = true
	room.finalized_match_id = match_id
	GameLog.warn(
		"NetClient",
		"Finalize success room=%s match_id=%s participants=%d history=%d"
			% [
				_safe_text(str(room.room_code)),
				_safe_text(match_id),
				participants.size(),
				int(room.game_engine.command_history.size()) if room.game_engine != null else -1,
			]
	)

func _safe_text(value: String) -> String:
	return ServerLogFormatClass.safe_text(value)

func _short_hash(hash_value: String) -> String:
	return ServerLogFormatClass.short_hash(hash_value)

func _request_tag(peer_id: int, request_id: String) -> String:
	return ServerLogFormatClass.request_tag(peer_id, request_id)

func _room_brief(room) -> String:
	return ServerLogFormatClass.room_brief(room)

func _command_brief(cmd) -> String:
	return ServerLogFormatClass.command_brief(cmd)

func _dinnertime_pending_brief(state) -> String:
	if state == null or not (state.round_state is Dictionary):
		return "-"
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return "-"
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return "[]"
	var list: Array = list_val
	var parts: Array[String] = []
	for item_val in list:
		if item_val is String:
			parts.append(str(item_val))
			continue
		if item_val is Dictionary:
			var item: Dictionary = item_val
			parts.append("%s:%s" % [str(item.get("kind", "?")), str(item.get("player_id", "?"))])
			continue
		parts.append(str(typeof(item_val)))
		if parts.size() >= 6:
			break
	var suffix := "..." if list.size() > parts.size() else ""
	return "len=%d [%s%s]" % [list.size(), ", ".join(parts), suffix]

func _dinnertime_confirmed_brief(state) -> String:
	if state == null or not (state.round_state is Dictionary):
		return "-"
	var rs: Dictionary = state.round_state
	var v = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if not (v is Array):
		return "-"
	var arr: Array = v
	var parts: Array[String] = []
	for i in range(min(arr.size(), 12)):
		parts.append("1" if bool(arr[i]) else "0")
	var suffix := "..." if arr.size() > parts.size() else ""
	return "%d[%s%s]" % [arr.size(), "".join(parts), suffix]

func on_peer_connected(peer_id: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode == NetContext.Mode.ONLINE_SERVER:
		GameLog.info("NetClient", "Peer connected: peer=%d known_profiles=%d" % [peer_id, _net._profile_by_peer_id.size()])

func on_peer_disconnected(peer_id: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	GameLog.warn("NetClient", "Peer disconnected: peer=%d" % peer_id)

	_resync_service.forget_peer(peer_id)
	_net._profile_by_peer_id.erase(peer_id)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	var room_status := str(room.status) if room != null else ""
	var pending_start_notify_peer_ids: Array[int] = []
	var pending_start_request_id := ""
	var pending_start_reason := ""
	if room != null and room_status == "Starting" and room.has_method("has_pending_start_session") and room.has_pending_start_session():
		pending_start_reason = "有玩家掉线，本次开局已取消"
		if room.has_method("get_pending_start_summary"):
			var bootstrap_summary: Dictionary = room.get_pending_start_summary()
			pending_start_request_id = str(bootstrap_summary.get("request_id", "")).strip_edges()
		if room.has_method("get_pending_start_target_peer_ids"):
			pending_start_notify_peer_ids = Array(room.get_pending_start_target_peer_ids())
		pending_start_notify_peer_ids.erase(peer_id)
		if room.has_method("abort_prepared_start_game"):
			room.abort_prepared_start_game(pending_start_reason)
		room_status = str(room.status)
	var in_game := room != null and room_status == "InGame"
	var preserve_room_on_disconnect := room != null and (room_status == "InGame" or room_status == "Lobby")
	var disconnect_target: Dictionary = _disconnect_grace_service.resolve_target(room, peer_id)
	var actor_id := -1
	if room != null and (room.player_id_by_peer_id is Dictionary):
		if room.player_id_by_peer_id.has(peer_id):
			actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
			room.player_id_by_peer_id.erase(peer_id)
		elif room.player_id_by_peer_id.has(str(peer_id)):
			actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
			room.player_id_by_peer_id.erase(str(peer_id))

	var removed := false
	var rr = _net._room_manager.disconnect_peer(peer_id) if preserve_room_on_disconnect else _net._room_manager.leave_room(peer_id)
	if rr.ok:
		removed = bool(rr.value.get("removed", false))
	else:
		GameLog.error(
			"NetClient",
			"disconnect handling failed peer=%d preserve_room=%s err=%s %s"
				% [peer_id, str(preserve_room_on_disconnect), rr.error, _room_brief(room)]
		)

	# 房间已被清理（无任何在线成员）：直接关闭对局，不再执行 forfeit/auto step。
	# 否则，服务器会在无人在线时继续自动推进（直到 safety limit）。
	if removed and room != null and room.game_engine != null:
		if room.game_engine.has_method("dispose"):
			room.game_engine.dispose()
		room.game_engine = null

	if not removed and room != null and not disconnect_target.is_empty():
		_disconnect_grace_service.schedule(room, disconnect_target)

	if rr.ok and room != null and not removed:
		_mark_room_directory_dirty()
		broadcast_room_state(room)
		broadcast_room_list("")

	if not pending_start_reason.is_empty():
		_notify_request_rejected_to_peers(
			pending_start_notify_peer_ids,
			pending_start_request_id,
			"match_bootstrap_failed",
			pending_start_reason
		)
		GameLog.info("NetClient", "Disconnect handled keep-room peer=%d removed=%s %s" % [peer_id, str(removed), _room_brief(room)])
	elif rr.ok and room != null and not removed:
		GameLog.info("NetClient", "Disconnect handled keep-room peer=%d removed=%s %s" % [peer_id, str(removed), _room_brief(room)])
	elif rr.ok and removed:
		_mark_room_directory_dirty()
		broadcast_room_list("")
		GameLog.info("NetClient", "Disconnect handled room removed peer=%d" % peer_id)

func send_request_rejected(peer_id: int, request_id: String, code: String, message: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	GameLog.warn(
		"NetClient",
		"TX RequestRejected %s code=%s message=%s"
			% [_request_tag(peer_id, request_id), _safe_text(code), _safe_text(message)]
	)
	_net.rpc_id(peer_id, "rpc_request_rejected", {
		"request_id": request_id,
		"code": code,
		"message": message,
	})

func _notify_request_rejected_to_peers(peer_ids: Array[int], request_id: String, code: String, message: String) -> void:
	var sent_peer_ids: Dictionary = {}
	for peer_id_val in peer_ids:
		var peer_id := int(peer_id_val)
		if peer_id <= 0 or sent_peer_ids.has(peer_id):
			continue
		sent_peer_ids[peer_id] = true
		send_request_rejected(peer_id, request_id, code, message)

func _get_pending_start_request_id(room, fallback: String = "") -> String:
	if room == null:
		return str(fallback).strip_edges()
	if room.has_method("get_pending_start_request_id"):
		var request_id := str(room.get_pending_start_request_id()).strip_edges()
		if not request_id.is_empty():
			return request_id
	if room.has_method("get_pending_start_summary"):
		var summary: Dictionary = room.get_pending_start_summary()
		var request_id_from_summary := str(summary.get("request_id", "")).strip_edges()
		if not request_id_from_summary.is_empty():
			return request_id_from_summary
	return str(fallback).strip_edges()

func _abort_pending_start_session(room, request_id: String, reason: String, peer_ids: Array[int], code: String = "match_bootstrap_failed") -> void:
	if room == null:
		_notify_request_rejected_to_peers(peer_ids, request_id, code, reason)
		return
	if room.has_method("abort_prepared_start_game"):
		room.abort_prepared_start_game(reason)
	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	_notify_request_rejected_to_peers(peer_ids, request_id, code, reason)

func broadcast_room_state(room) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null:
		return
	var targets := Array(room.get_peer_ids())
	for peer_id in targets:
		var state: Dictionary = room.to_room_state_dict_for_peer(int(peer_id)) if room.has_method("to_room_state_dict_for_peer") else room.to_room_state_dict()
		_net.rpc_id(peer_id, "rpc_room_state", state)
	GameLog.debug("NetClient", "TX RoomState %s recipients=%d" % [_room_brief(room), targets.size()])

func empty_room_state() -> Dictionary:
	return {
		"room_code": "",
		"room_mode": "normal",
		"host_peer_id": 0,
		"host_seat_index": -1,
		"players": [],
		"waiting_members": [],
		"spectators": [],
		"password_required": false,
		"allow_spectators": true,
		"config": {},
		"status": "Lobby",
		"self_seat_index": -1,
		"self_role": "",
	}

func send_room_list_to_peer(peer_id: int, request_id: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var rooms: Array[Dictionary] = []
	if _net._room_manager != null and _net._room_manager.has_method("list_room_summaries"):
		rooms = _net._room_manager.list_room_summaries()
	_net.rpc_id(peer_id, "rpc_room_list", {
		"request_id": request_id,
		"rooms": rooms,
	})
	GameLog.debug(
		"NetClient",
		"TX RoomList %s rooms=%d" % [_request_tag(peer_id, request_id), rooms.size()]
	)

func broadcast_room_list(request_id: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var targets := 0
	for peer_id_val in _net._profile_by_peer_id.keys():
		targets += 1
		send_room_list_to_peer(int(peer_id_val), request_id)
	GameLog.debug("NetClient", "TX BroadcastRoomList request_id=%s recipients=%d" % [_safe_text(request_id), targets])

func handle_rpc_client_hello(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var protocol_version := int(request.get("protocol_version", 0))
	var game_version := str(request.get("game_version", ""))
	var schema_version := int(request.get("schema_version", 0))
	var profile_preview: Dictionary = Dictionary(request.get("player_profile", {}))
	GameLog.info(
		"NetClient",
		"RX ClientHello %s protocol=%d game_version=%s schema=%d profile_name=%s color=%d restaurant_logo_id=%d"
			% [
				_request_tag(peer_id, request_id),
				protocol_version,
				_safe_text(game_version),
				schema_version,
				_safe_text(str(profile_preview.get("name", ""))),
				int(profile_preview.get("color_index", -1)),
				int(profile_preview.get("restaurant_logo_id", -1))
			]
	)
	if protocol_version != NetContext.PROTOCOL_VERSION:
		send_request_rejected(peer_id, request_id, "protocol_version_mismatch", "Protocol version mismatch")
		return

	var secret := _get_connect_token_secret().strip_edges()
	var connect_token := str(request.get("connect_token", "")).strip_edges()
	var token_payload: Dictionary = {}
	var resume_cursor: Dictionary = {}
	var resume_room_bootstrap: Dictionary = {}
	if secret.is_empty():
		send_request_rejected(peer_id, request_id, "server_misconfigured", "HMAC_SECRET is not configured")
		return
	if connect_token.is_empty():
		send_request_rejected(peer_id, request_id, "missing_connect_token", "connect_token required")
		return
	var vr: Result = ConnectTokenClass.verify_token(connect_token, secret)
	if not vr.ok:
		send_request_rejected(peer_id, request_id, "invalid_connect_token", vr.error)
		return
	if not (vr.value is Dictionary):
		send_request_rejected(peer_id, request_id, "invalid_connect_token", "connect_token payload type invalid")
		return
	token_payload = Dictionary(vr.value)
	var resume_cursor_val = request.get("resume_cursor", null)
	if resume_cursor_val is Dictionary:
		resume_cursor = Dictionary(resume_cursor_val).duplicate(true)
	var resume_room_bootstrap_val = request.get("resume_room_bootstrap", null)
	if resume_room_bootstrap_val is Dictionary:
		resume_room_bootstrap = Dictionary(resume_room_bootstrap_val).duplicate(true)

	var profile: Dictionary = profile_preview
	var token_user_id := ""
	if not token_payload.is_empty():
		token_user_id = str(token_payload.get("user_id", "")).strip_edges()
		var display_name := str(token_payload.get("display_name", "")).strip_edges()
		if not display_name.is_empty():
			profile["name"] = display_name

	var normalized_profile := {
		"name": str(profile.get("name", "玩家")),
		"color_index": int(profile.get("color_index", 0)),
		"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
	}
	if not token_user_id.is_empty():
		normalized_profile["user_id"] = token_user_id
	_net._profile_by_peer_id[peer_id] = normalized_profile

	if not token_payload.is_empty():
		var jr: Result = _platform_auto_join(peer_id, request_id, normalized_profile, token_payload, resume_cursor, resume_room_bootstrap)
		if not jr.ok:
			_net._profile_by_peer_id.erase(peer_id)
			var join_error_code := "platform_join_failed"
			if str(jr.error).strip_edges() == "generation_conflict":
				join_error_code = "generation_conflict"
			send_request_rejected(peer_id, request_id, join_error_code, jr.error)
			return

	# 允许已在房间中的客户端更新自己的 profile（昵称/颜色/logo）。
	# 重要：不新增 @rpc 方法，避免 dedicated server 与客户端版本不一致时触发 checksum mismatch。
	var room = _net._room_manager.get_room_by_peer(peer_id) if _net._room_manager != null else null
	if room != null and room.has_method("update_peer_profile"):
		var ur = room.update_peer_profile(peer_id, Dictionary(normalized_profile))
		if ur.ok:
			broadcast_room_state(room)
			broadcast_room_list("")
		else:
			GameLog.warn(
				"NetClient",
				"ClientHello profile update skipped %s err=%s %s"
					% [_request_tag(peer_id, request_id), ur.error, _room_brief(room)]
			)
	send_room_list_to_peer(peer_id, "")
	GameLog.info(
		"NetClient",
		"ClientHello accepted %s in_room=%s known_profiles=%d"
			% [_request_tag(peer_id, request_id), str(room != null), _net._profile_by_peer_id.size()]
	)

func _platform_auto_join(
	peer_id: int,
	request_id: String,
	profile: Dictionary,
	token_payload: Dictionary,
	resume_cursor: Dictionary = {},
	resume_room_bootstrap: Dictionary = {}
) -> Result:
	if _net == null or not is_instance_valid(_net):
		return ResultClass.failure("NetClient missing")
	if _net._room_manager == null or not is_instance_valid(_net._room_manager):
		return ResultClass.failure("RoomManager missing")

	var room_code := str(token_payload.get("room_code", "")).strip_edges().to_upper()
	var role := str(token_payload.get("role", "")).strip_edges()
	if room_code.is_empty():
		return ResultClass.failure("connect_token missing room_code")
	if role != "host" and role != "player" and role != "spectator":
		return ResultClass.failure("connect_token invalid role: %s" % role)

	var rm = _net._room_manager
	var existing_room = rm.rooms.get(room_code, null) if (rm.rooms is Dictionary) else null
	var token_config: Dictionary = {}
	var token_generation := -1
	var cfg_json := str(token_payload.get("config_json", "")).strip_edges()
	if not cfg_json.is_empty():
		var parsed: Variant = JSON.parse_string(cfg_json)
		if not (parsed is Dictionary):
			return ResultClass.failure("connect_token config_json 类型错误（期望 JSON Dictionary）")
		token_config = Dictionary(parsed)
	var token_room_mode := str(token_config.get("room_mode", "")).strip_edges()
	var is_resume_room := token_room_mode == "resume_archive"
	var token_generation_val = token_payload.get("generation", null)
	if token_generation_val is int:
		token_generation = int(token_generation_val)
	elif token_generation_val is float:
		var generation_f: float = float(token_generation_val)
		if generation_f == floor(generation_f):
			token_generation = int(generation_f)
	if existing_room != null and existing_room.has_method("is_resume_archive_room"):
		is_resume_room = bool(existing_room.is_resume_archive_room())
	var prepared_resume_transfer: Dictionary = {}
	if existing_room != null and str(existing_room.status) == "InGame":
		var prepared_r: Result = _resync_service.build_best_effort_resume_transfer(existing_room, resume_cursor)
		if not prepared_r.ok:
			return ResultClass.failure(prepared_r.error)
		prepared_resume_transfer = Dictionary(prepared_r.value).duplicate(true)
	var r: Result
	if role == "host":
		var seat_index_val = token_payload.get("seat_index", null)
		var seat_index := -1
		if seat_index_val is int:
			seat_index = int(seat_index_val)
		elif seat_index_val is float:
			var f: float = float(seat_index_val)
			if f == floor(f):
				seat_index = int(f)
		if seat_index < 0 and not is_resume_room:
			return ResultClass.failure("connect_token missing seat_index")

		var config: Dictionary = token_config.duplicate(true)
		var join_policy := str(token_payload.get("join_policy", "public")).strip_edges()
		var password_hash := str(token_payload.get("password_hash", "")).strip_edges()

		if existing_room == null:
			if is_resume_room:
				if not rm.has_method("create_resume_room_with_code"):
					return ResultClass.failure("RoomManager.create_resume_room_with_code missing")
				var archive_val = resume_room_bootstrap.get("archive", null)
				if not (archive_val is Dictionary):
					return ResultClass.failure("resume room bootstrap archive missing")
				r = rm.create_resume_room_with_code(peer_id, profile, room_code, config, Dictionary(archive_val), join_policy, password_hash, token_generation)
			else:
				if not rm.has_method("create_room_with_code"):
					return ResultClass.failure("RoomManager.create_room_with_code missing")
				r = rm.create_room_with_code(peer_id, profile, room_code, config, join_policy, password_hash, token_generation)
		elif str(existing_room.status) == "InGame":
			if not rm.has_method("reconnect_player"):
				return ResultClass.failure("RoomManager.reconnect_player missing")
			var user_id := str(token_payload.get("user_id", "")).strip_edges()
			if seat_index < 0 and is_resume_room and existing_room.has_method("find_seat_index_for_user_id"):
				seat_index = int(existing_room.find_seat_index_for_user_id(user_id))
			r = rm.reconnect_player(peer_id, profile, room_code, seat_index, user_id, "host", token_generation)
		else:
			var host_uid := str(token_payload.get("user_id", "")).strip_edges()
			if seat_index < 0 and is_resume_room:
				if not rm.has_method("join_room_as_waiting_member"):
					return ResultClass.failure("RoomManager.join_room_as_waiting_member missing")
				r = rm.join_room_as_waiting_member(peer_id, profile, room_code, "host", token_generation)
			else:
				var host_seat_taken: bool = existing_room != null and existing_room._seat_profile_by_seat_index is Dictionary and existing_room._seat_profile_by_seat_index.has(seat_index)
				if host_seat_taken:
					if not rm.has_method("reclaim_room_seat"):
						return ResultClass.failure("RoomManager.reclaim_room_seat missing")
					r = rm.reclaim_room_seat(peer_id, profile, room_code, seat_index, host_uid, "host", token_generation)
				else:
					if not rm.has_method("join_room_with_seat"):
						return ResultClass.failure("RoomManager.join_room_with_seat missing")
					r = rm.join_room_with_seat(peer_id, profile, room_code, seat_index, "host", token_generation)
	elif role == "player":
		var seat_index_val2 = token_payload.get("seat_index", null)
		var seat_index2 := -1
		if seat_index_val2 is int:
			seat_index2 = int(seat_index_val2)
		elif seat_index_val2 is float:
			var f2: float = float(seat_index_val2)
			if f2 == floor(f2):
				seat_index2 = int(f2)
		if seat_index2 < 0 and not is_resume_room:
			return ResultClass.failure("connect_token missing seat_index")

		if existing_room != null and str(existing_room.status) == "InGame":
			if not rm.has_method("reconnect_player"):
				return ResultClass.failure("RoomManager.reconnect_player missing")
			var user_id2 := str(token_payload.get("user_id", "")).strip_edges()
			if seat_index2 < 0 and is_resume_room and existing_room.has_method("find_seat_index_for_user_id"):
				seat_index2 = int(existing_room.find_seat_index_for_user_id(user_id2))
			r = rm.reconnect_player(peer_id, profile, room_code, seat_index2, user_id2, "player", token_generation)
		else:
			var player_uid := str(token_payload.get("user_id", "")).strip_edges()
			if seat_index2 < 0 and is_resume_room:
				if not rm.has_method("join_room_as_waiting_member"):
					return ResultClass.failure("RoomManager.join_room_as_waiting_member missing")
				r = rm.join_room_as_waiting_member(peer_id, profile, room_code, "player", token_generation)
			else:
				var player_seat_taken: bool = existing_room != null and existing_room._seat_profile_by_seat_index is Dictionary and existing_room._seat_profile_by_seat_index.has(seat_index2)
				if player_seat_taken:
					if not rm.has_method("reclaim_room_seat"):
						return ResultClass.failure("RoomManager.reclaim_room_seat missing")
					r = rm.reclaim_room_seat(peer_id, profile, room_code, seat_index2, player_uid, "player", token_generation)
				else:
					if not rm.has_method("join_room_with_seat"):
						return ResultClass.failure("RoomManager.join_room_with_seat missing")
					r = rm.join_room_with_seat(peer_id, profile, room_code, seat_index2, "player", token_generation)
	else:
		if not rm.has_method("spectate_room"):
			return ResultClass.failure("RoomManager.spectate_room missing")
		r = rm.spectate_room(peer_id, profile, room_code)

	if not r.ok:
		return r

	var payload: Dictionary = Dictionary(r.value) if (r.value is Dictionary) else {}
	_handle_replaced_peer(payload)
	var room = payload.get("room", null)
	if room == null:
		return ResultClass.failure("platform auto join missing room")
	var actual_role := str(payload.get("role", "")).strip_edges()
	if not actual_role.is_empty() and actual_role != role:
		return ResultClass.failure("platform auto join role mismatch: token=%s actual=%s" % [role, actual_role])

	# 断线重连：若 actor_id 对应的 pending forfeit 仍在 grace window 内，则清理。
	if role == "host" or role == "player":
		var seat_index_val3 = token_payload.get("seat_index", null)
		var seat_index3 := -1
		if seat_index_val3 is int:
			seat_index3 = int(seat_index_val3)
		elif seat_index_val3 is float:
			var f3: float = float(seat_index_val3)
			if f3 == floor(f3):
				seat_index3 = int(f3)
		if seat_index3 >= 0:
			if str(room.status).strip_edges() == "Lobby":
				_disconnect_grace_service.clear_lobby_seat(room_code, seat_index3)
			else:
				_disconnect_grace_service.clear_actor(room_code, seat_index3)
		elif is_resume_room and str(room.status).strip_edges() == "Lobby":
			var waiting_user_id := str(token_payload.get("user_id", "")).strip_edges()
			if not waiting_user_id.is_empty():
				_disconnect_grace_service.clear_waiting_member(room_code, waiting_user_id)

	# InGame：自动下发 GameStarted + chunked snapshot（与 JoinRoom in-game 行为对齐）
	if str(room.status) == "InGame" and room.game_engine != null:
		if prepared_resume_transfer.is_empty():
			var prepared_fallback_r: Result = _resync_service.build_best_effort_resume_transfer(room, resume_cursor)
			if not prepared_fallback_r.ok:
				return ResultClass.failure(prepared_fallback_r.error)
			prepared_resume_transfer = Dictionary(prepared_fallback_r.value).duplicate(true)
		var game_started_payload := GameStartedPayloadsClass.build_for_room_peer(room, peer_id)
		_net.rpc_id(peer_id, "rpc_game_started", game_started_payload)
		var resume_r: Result = _resync_service.dispatch_prepared_transfer(
			peer_id,
			request_id,
			room,
			prepared_resume_transfer,
			"platform_auto_join",
		)
		if not resume_r.ok:
			return ResultClass.failure(resume_r.error)

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"Platform auto join ok %s role=%s room=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(role), _safe_text(room_code), _room_brief(room)]
	)
	return ResultClass.success({"room_code": room_code, "role": role})

func handle_rpc_list_rooms(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	GameLog.debug("NetClient", "RX ListRooms %s" % _request_tag(peer_id, request_id))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before ListRooms")
		return

	send_room_list_to_peer(peer_id, request_id)

func handle_rpc_create_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	var desired_player_count := int(request.get("desired_player_count", 0))
	GameLog.info(
		"NetClient",
		"RX CreateRoom %s desired_player_count=%d has_password=%s keys=%s"
			% [
				_request_tag(peer_id, request_id),
				desired_player_count,
				str(not str(request.get("room_password", "")).is_empty()),
				str(Array(request.keys()))
			]
	)
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before CreateRoom")
		return

	if desired_player_count < Globals.MIN_PLAYERS or desired_player_count > Globals.MAX_PLAYERS:
		send_request_rejected(peer_id, request_id, "invalid_player_count", "desired_player_count out of range")
		return

	var room_password := str(request.get("room_password", ""))
	var config := {
		"desired_player_count": desired_player_count,
		"seed_mode": "random",
		"seed": 0,
		"allow_spectators": true,
		"enabled_modules_v2": Array(Globals.enabled_modules_v2, TYPE_STRING, "", null),
		"modules_v2_base_dir": str(Globals.modules_v2_base_dir),
	}

	if request.has("seed_mode"):
		var sm := str(request.get("seed_mode", "")).strip_edges()
		if sm != "random" and sm != "fixed":
			send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		config["seed_mode"] = sm
	if request.has("seed"):
		var sv = request.get("seed", null)
		if not (sv is int or sv is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		config["seed"] = int(sv)
	if str(config.get("seed_mode", "random")) == "fixed":
		if not request.has("seed"):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
			return

	if request.has("allow_spectators"):
		var av = request.get("allow_spectators", null)
		if not (av is bool):
			send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		config["allow_spectators"] = bool(av)

	if request.has("enabled_modules_v2"):
		var mv = request.get("enabled_modules_v2", null)
		if not (mv is Array):
			send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
			return
		var mods: Array[String] = []
		for it in Array(mv):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			mods.append(s)
		config["enabled_modules_v2"] = mods

	if request.has("modules_v2_base_dir"):
		var bd := str(request.get("modules_v2_base_dir", "")).strip_edges()
		if bd.is_empty():
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		var bd_read = ModuleDirSpecClass.parse_base_dirs(bd)
		if not bd_read.ok:
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir must use res:// paths")
			return
		config["modules_v2_base_dir"] = bd

	# seed_mode=random：由 server 固定生成 seed，以便大厅展示与可复现。
	if str(config.get("seed_mode", "random")) == "random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		config["seed"] = int(rng.randi())

	var cr = _net._room_manager.create_room(peer_id, profile, room_password, config)
	if not cr.ok:
		send_request_rejected(peer_id, request_id, "create_room_failed", cr.error)
		return

	var room = Dictionary(cr.value).get("room", null)
	if room == null:
		send_request_rejected(peer_id, request_id, "create_room_failed", "Missing room in result")
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"CreateRoom success %s %s seed_mode=%s seed=%d modules=%d"
			% [
				_request_tag(peer_id, request_id),
				_room_brief(room),
				_safe_text(str(config.get("seed_mode", ""))),
				int(config.get("seed", 0)),
				Array(config.get("enabled_modules_v2", [])).size()
			]
	)

func handle_rpc_join_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var profile: Dictionary = Dictionary(_net._profile_by_peer_id.get(peer_id, {}))
	var room_code := str(request.get("room_code", "")).strip_edges().to_upper()
	GameLog.info(
		"NetClient",
		"RX JoinRoom %s room_code=%s has_password=%s"
			% [
				_request_tag(peer_id, request_id),
				_safe_text(room_code),
				str(not str(request.get("room_password", "")).is_empty())
			]
	)
	if profile.is_empty():
		send_request_rejected(peer_id, request_id, "missing_client_hello", "ClientHello required before JoinRoom")
		return

	var room_password := str(request.get("room_password", ""))
	var in_game_resync_snapshot_transfer: Dictionary = {}
	if _net._room_manager != null and _net._room_manager.rooms is Dictionary:
		var target_room = _net._room_manager.rooms.get(room_code, null)
		if target_room != null and str(target_room.status) == "InGame":
			var transfer_r: Result = _resync_service.build_full_snapshot_transfer(target_room)
			if not transfer_r.ok:
				send_request_rejected(peer_id, request_id, "join_room_failed", transfer_r.error)
				return
			in_game_resync_snapshot_transfer = Dictionary(transfer_r.value)

	var jr = _net._room_manager.join_room(peer_id, profile, room_code, room_password)
	if not jr.ok:
		send_request_rejected(peer_id, request_id, "join_room_failed", jr.error)
		return

	var join_payload: Dictionary = Dictionary(jr.value) if jr.value is Dictionary else {}
	_handle_replaced_peer(join_payload)
	var room = join_payload.get("room", null)
	if room == null:
		send_request_rejected(peer_id, request_id, "join_room_failed", "Missing room in result")
		return

	var role := str(join_payload.get("role", "player"))
	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"JoinRoom success %s role=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(role), _room_brief(room)]
	)
	if str(room.status) == "InGame" and room.game_engine != null:
		var payload := GameStartedPayloadsClass.build_for_room_peer(room, peer_id)
		_net.rpc_id(peer_id, "rpc_game_started", payload)
		var transfer_to_send := in_game_resync_snapshot_transfer
		if transfer_to_send.is_empty():
			var transfer_r2: Result = _resync_service.build_full_snapshot_transfer(room)
			if not transfer_r2.ok:
				send_request_rejected(peer_id, request_id, "join_room_failed", transfer_r2.error)
				return
			transfer_to_send = Dictionary(transfer_r2.value)
		_resync_service.send_prebuilt_snapshot(peer_id, request_id, room, transfer_to_send, "join_room")

func handle_rpc_update_room_config(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var patch_keys: Array = []
	var patch_preview = request.get("config_patch", null)
	if patch_preview is Dictionary:
		patch_keys = Array(Dictionary(patch_preview).keys())
	GameLog.debug(
		"NetClient",
		"RX UpdateRoomConfig %s patch_keys=%s"
			% [_request_tag(peer_id, request_id), str(patch_keys)]
	)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		send_request_rejected(peer_id, request_id, "not_host", "Only host can update config")
		return

	var patch_raw = request.get("config_patch", null)
	if not (patch_raw is Dictionary):
		send_request_rejected(peer_id, request_id, "invalid_params", "config_patch must be Dictionary")
		return
	var patch: Dictionary = Dictionary(patch_raw)
	if room.has_method("is_resume_archive_room") and room.is_resume_archive_room():
		send_request_rejected(peer_id, request_id, "update_config_failed", "Resume 房间暂不支持修改配置")
		return

	if patch.has("desired_player_count"):
		var v = patch.get("desired_player_count", null)
		if not (v is int or v is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count must be int")
			return
		var n := int(v)
		if n < Globals.MIN_PLAYERS or n > Globals.MAX_PLAYERS:
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count out of range")
			return
		if n < int(room.get_player_count()):
			send_request_rejected(peer_id, request_id, "invalid_params", "desired_player_count < current players")
			return
		patch["desired_player_count"] = n

	if patch.has("seed_mode"):
		var sm := str(patch.get("seed_mode", "")).strip_edges()
		if sm != "random" and sm != "fixed":
			send_request_rejected(peer_id, request_id, "invalid_params", "seed_mode must be 'random' or 'fixed'")
			return
		patch["seed_mode"] = sm

	if patch.has("seed"):
		var sv = patch.get("seed", null)
		if not (sv is int or sv is float):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed must be int")
			return
		patch["seed"] = int(sv)

	if patch.has("allow_spectators"):
		var av = patch.get("allow_spectators", null)
		if not (av is bool):
			send_request_rejected(peer_id, request_id, "invalid_params", "allow_spectators must be bool")
			return
		patch["allow_spectators"] = bool(av)

	if patch.has("enabled_modules_v2"):
		var mv = patch.get("enabled_modules_v2", null)
		if not (mv is Array):
			send_request_rejected(peer_id, request_id, "invalid_params", "enabled_modules_v2 must be Array")
			return
		var mods: Array[String] = []
		for it in Array(mv):
			var s := str(it).strip_edges()
			if s.is_empty():
				continue
			mods.append(s)
		patch["enabled_modules_v2"] = mods

	if patch.has("modules_v2_base_dir"):
		var bd := str(patch.get("modules_v2_base_dir", "")).strip_edges()
		if bd.is_empty():
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir is empty")
			return
		var bd_read = ModuleDirSpecClass.parse_base_dirs(bd)
		if not bd_read.ok:
			send_request_rejected(peer_id, request_id, "invalid_params", "modules_v2_base_dir must use res:// paths")
			return
		patch["modules_v2_base_dir"] = bd

	if patch.has("restaurant_logo_choices_by_player"):
		if str(room.status) != "Lobby":
			send_request_rejected(peer_id, request_id, "invalid_state", "Room is not in Lobby")
			return
		var logos_val = patch.get("restaurant_logo_choices_by_player", null)
		if not (logos_val is Array):
			send_request_rejected(peer_id, request_id, "invalid_params", "restaurant_logo_choices_by_player must be Array")
			return
		var logos_src: Array = Array(logos_val)
		var logo_limit := DEFAULT_RESTAURANT_LOGO_COUNT
		var normalized_logos: Array[int] = []
		for i in range(logos_src.size()):
			var it = logos_src[i]
			if not (it is int or it is float):
				send_request_rejected(peer_id, request_id, "invalid_params", "restaurant_logo_choices_by_player item must be int")
				return
			var lid := int(it)
			if lid < -1 or lid >= maxi(1, logo_limit):
				send_request_rejected(peer_id, request_id, "invalid_params", "restaurant_logo_id out of range")
				return
			normalized_logos.append(lid)
		patch["restaurant_logo_choices_by_player"] = normalized_logos

		var seated_players := int(room.get_player_count()) if room.has_method("get_player_count") else 0
		if not room.has_method("set_player_logo_by_seat"):
			send_request_rejected(peer_id, request_id, "not_supported", "Room does not support seat logo assignment")
			return
		for seat_index in range(seated_players):
			var seat_logo_id := -1
			if seat_index < normalized_logos.size():
				seat_logo_id = int(normalized_logos[seat_index])
			var sr: Result = room.set_player_logo_by_seat(seat_index, seat_logo_id)
			if not sr.ok:
				send_request_rejected(peer_id, request_id, "invalid_params", sr.error)
				return

	# seed_mode=random：保持一个 server 选定的 seed（不在 StartGame 时再重掷），便于大厅展示/复现。
	var old_seed_mode := str(room.config.get("seed_mode", "random")).strip_edges()
	var new_seed_mode := old_seed_mode
	if patch.has("seed_mode"):
		new_seed_mode = str(patch.get("seed_mode", "random")).strip_edges()

	if new_seed_mode == "fixed":
		if not patch.has("seed"):
			send_request_rejected(peer_id, request_id, "invalid_params", "seed required when seed_mode=fixed")
			return
	elif new_seed_mode == "random":
		var seed_cur := int(room.config.get("seed", 0))
		if old_seed_mode != "random":
			seed_cur = 0
		if seed_cur <= 0:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			seed_cur = int(rng.randi())
		patch["seed"] = seed_cur

	var ur = room.update_config(patch)
	if not ur.ok:
		send_request_rejected(peer_id, request_id, "update_config_failed", ur.error)
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.debug(
		"NetClient",
		"UpdateRoomConfig success %s %s patch_keys=%s"
			% [_request_tag(peer_id, request_id), _room_brief(room), str(Array(patch.keys()))]
	)

func handle_rpc_assign_room_seat(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		send_request_rejected(peer_id, request_id, "not_host", "Only host can assign seats")
		return
	if str(room.status) != "Lobby":
		send_request_rejected(peer_id, request_id, "assign_seat_failed", "Room is not in Lobby")
		return
	if not room.has_method("is_resume_archive_room") or not room.is_resume_archive_room():
		send_request_rejected(peer_id, request_id, "assign_seat_failed", "Room does not support manual seat assignment")
		return

	var seat_index_val = request.get("seat_index", null)
	if not (seat_index_val is int or seat_index_val is float):
		send_request_rejected(peer_id, request_id, "invalid_params", "seat_index must be int")
		return
	var seat_index := int(seat_index_val)
	var user_id := str(request.get("user_id", "")).strip_edges()

	var sr: Result
	if user_id.is_empty():
		if not _net._room_manager.has_method("unassign_room_seat"):
			send_request_rejected(peer_id, request_id, "assign_seat_failed", "RoomManager.unassign_room_seat missing")
			return
		sr = _net._room_manager.unassign_room_seat(str(room.room_code), seat_index)
	else:
		if not _net._room_manager.has_method("assign_waiting_member_to_seat"):
			send_request_rejected(peer_id, request_id, "assign_seat_failed", "RoomManager.assign_waiting_member_to_seat missing")
			return
		sr = _net._room_manager.assign_waiting_member_to_seat(str(room.room_code), user_id, seat_index)
	if not sr.ok:
		send_request_rejected(peer_id, request_id, "assign_seat_failed", sr.error)
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"AssignRoomSeat success %s room=%s user_id=%s seat=%d"
			% [_request_tag(peer_id, request_id), _safe_text(str(room.room_code)), _safe_text(user_id), seat_index]
	)

func handle_rpc_leave_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	GameLog.info("NetClient", "RX LeaveRoom %s %s" % [_request_tag(peer_id, request_id), _room_brief(room)])

	var pending_start_notify_peer_ids: Array[int] = []
	var pending_start_reason := ""
	var pending_start_request_id := ""
	if room != null and str(room.status) == "Starting" and room.has_method("has_pending_start_session") and room.has_pending_start_session():
		pending_start_reason = "有玩家离开房间，本次开局已取消"
		if room.has_method("get_pending_start_summary"):
			var bootstrap_summary: Dictionary = room.get_pending_start_summary()
			pending_start_request_id = str(bootstrap_summary.get("request_id", "")).strip_edges()
		if room.has_method("get_pending_start_target_peer_ids"):
			pending_start_notify_peer_ids = Array(room.get_pending_start_target_peer_ids())
		pending_start_notify_peer_ids.erase(peer_id)
		if room.has_method("abort_prepared_start_game"):
			room.abort_prepared_start_game(pending_start_reason)

	var lr = _net._room_manager.leave_room(peer_id)
	if not lr.ok:
		send_request_rejected(peer_id, request_id, "leave_room_failed", lr.error)
		return

	var removed := bool(lr.value.get("removed", false))
	if room != null and not removed:
		_mark_room_directory_dirty()
		broadcast_room_state(room)
	elif removed:
		_mark_room_directory_dirty()
	broadcast_room_list("")

	_net.rpc_id(peer_id, "rpc_room_state", empty_room_state())
	if not pending_start_reason.is_empty():
		_notify_request_rejected_to_peers(
			pending_start_notify_peer_ids,
			pending_start_request_id,
			"match_bootstrap_failed",
			pending_start_reason
		)
	GameLog.info(
		"NetClient",
		"LeaveRoom success %s removed=%s previous_room=%s"
			% [_request_tag(peer_id, request_id), str(removed), _room_brief(room)]
	)

func _resolve_actor_id_for_peer(room, peer_id: int) -> int:
	if room == null or not (room.player_id_by_peer_id is Dictionary):
		return -1
	if room.player_id_by_peer_id.has(peer_id):
		return int(room.player_id_by_peer_id.get(peer_id, -1))
	if room.player_id_by_peer_id.has(str(peer_id)):
		return int(room.player_id_by_peer_id.get(str(peer_id), -1))
	return -1

func _finalize_forfeit_and_leave_room_request(peer_id: int, request_id: String, room, leave_result: Result) -> void:
	var removed := false
	if leave_result != null and leave_result.ok and leave_result.value is Dictionary:
		removed = bool(Dictionary(leave_result.value).get("removed", false))

	if removed and room != null and room.game_engine != null:
		if room.game_engine.has_method("dispose"):
			room.game_engine.dispose()
		room.game_engine = null

	_mark_room_directory_dirty()
	if room != null and not removed:
		broadcast_room_state(room)
	broadcast_room_list("")
	_net.rpc_id(peer_id, "rpc_room_state", empty_room_state())
	GameLog.info(
		"NetClient",
		"ForfeitAndLeaveRoom success %s removed=%s previous_room=%s"
			% [_request_tag(peer_id, request_id), str(removed), _room_brief(room)]
	)

func handle_rpc_forfeit_and_leave_room(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	GameLog.info("NetClient", "RX ForfeitAndLeaveRoom %s %s" % [_request_tag(peer_id, request_id), _room_brief(room)])

	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return

	var room_status := str(room.status)
	if room_status == "InGame":
		if room.game_engine == null:
			send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
			return

		var actor_id := _resolve_actor_id_for_peer(room, peer_id)
		if actor_id >= 0:
			var state = room.game_engine.get_state()
			if not server_is_player_forfeited(state, actor_id):
				var cmd = CommandClass.create("forfeit_player", actor_id, {})
				var fr = room.game_engine.execute_command(cmd)
				if not fr.ok:
					send_request_rejected(peer_id, request_id, "action_failed", fr.error)
					return
				_disconnect_grace_service.clear_actor(str(room.room_code), actor_id)
				broadcast_command_applied(room, cmd)
				server_drain_forfeited_auto_steps(room)
				_try_finalize_match_if_game_over(room)
		else:
			GameLog.info(
				"NetClient",
				"ForfeitAndLeaveRoom spectator exit %s %s"
					% [_request_tag(peer_id, request_id), _room_brief(room)]
			)

	var lr = _net._room_manager.leave_room(peer_id)
	if not lr.ok:
		send_request_rejected(peer_id, request_id, "leave_room_failed", lr.error)
		return

	_finalize_forfeit_and_leave_room_request(peer_id, request_id, room, lr)

func handle_rpc_start_game(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	GameLog.info("NetClient", "RX StartGame %s" % _request_tag(peer_id, request_id))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if int(room.host_peer_id) != int(peer_id):
		send_request_rejected(peer_id, request_id, "not_host", "Only host can start game")
		return
	if str(room.status) == "Starting" and room.has_method("has_pending_start_session") and room.has_pending_start_session():
		var pending_request_id := _get_pending_start_request_id(room, "")
		if not pending_request_id.is_empty() and pending_request_id == request_id:
			GameLog.info(
				"NetClient",
				"Duplicate StartGame ignored %s %s"
					% [_request_tag(peer_id, request_id), _room_brief(room)]
			)
			return
		send_request_rejected(peer_id, request_id, "start_game_failed", "Game start already in progress")
		return

	if not room.has_method("begin_start_game_session") or not room.has_method("prepare_start_game") or not room.has_method("commit_prepared_start_game"):
		send_request_rejected(peer_id, request_id, "start_game_failed", "Room bootstrap lifecycle missing")
		return

	var begin_r: Result = room.begin_start_game_session(request_id)
	if not begin_r.ok:
		send_request_rejected(peer_id, request_id, "start_game_failed", begin_r.error)
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")

	var resume_start_snapshot_transfer: Dictionary = {}
	var prepare_r: Result = room.prepare_start_game()
	if not prepare_r.ok:
		var failed_peer_ids: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
		_abort_pending_start_session(room, request_id, prepare_r.error, failed_peer_ids, "start_game_failed")
		return

	if room.has_method("is_resume_archive_room") and room.is_resume_archive_room():
		if not room.has_method("build_effective_resume_start_archive"):
			var failed_peer_ids_3: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
			_abort_pending_start_session(room, request_id, "Room.build_effective_resume_start_archive missing", failed_peer_ids_3, "start_game_failed")
			return
		var effective_resume_r: Result = room.build_effective_resume_start_archive()
		if not effective_resume_r.ok:
			var failed_peer_ids_4: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
			_abort_pending_start_session(room, request_id, effective_resume_r.error, failed_peer_ids_4, "start_game_failed")
			return
		var effective_resume_val = effective_resume_r.value
		if not (effective_resume_val is Dictionary):
			var failed_peer_ids_5: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
			_abort_pending_start_session(room, request_id, "resume start archive type invalid", failed_peer_ids_5, "start_game_failed")
			return
		var effective_resume_info: Dictionary = effective_resume_val
		var resume_archive: Dictionary = Dictionary(effective_resume_info.get("archive", {})).duplicate(true)
		if resume_archive.is_empty():
			var failed_peer_ids_6: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
			_abort_pending_start_session(room, request_id, "resume start archive missing", failed_peer_ids_6, "start_game_failed")
			return
		var resume_hash := str(effective_resume_info.get("final_hash", resume_archive.get("final_hash", ""))).strip_edges()
		var history_size := int(effective_resume_info.get("history_size", -1))
		var transfer_r: Result = _resync_service.build_archive_snapshot_transfer(
			str(room.room_code),
			resume_archive,
			history_size,
			resume_hash
		)
		if not transfer_r.ok:
			var failed_peer_ids_2: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
			_abort_pending_start_session(room, request_id, transfer_r.error, failed_peer_ids_2, "start_game_failed")
			return
		resume_start_snapshot_transfer = Dictionary(transfer_r.value).duplicate(true)
	if room.has_method("set_pending_start_phase"):
		room.set_pending_start_phase("waiting_for_players")

	_mark_room_directory_dirty()
	broadcast_room_state(room)

	var payload_val: Dictionary = Dictionary(prepare_r.value)
	var payload := {
		"player_id_by_peer_id": Dictionary(payload_val.get("player_id_by_peer_id", {})),
		"config": Dictionary(payload_val.get("config", {})),
	}

	for pid in room.get_peer_ids():
		var per_peer_payload := payload.duplicate(true)
		per_peer_payload["local_player_id"] = room.get_seat_index_for_peer(int(pid)) if room.has_method("get_seat_index_for_peer") else -1
		GameStartedPayloadsClass.mark_resume_archive_bootstrap(per_peer_payload, room)
		_net.rpc_id(int(pid), "rpc_game_started", per_peer_payload)
		if not resume_start_snapshot_transfer.is_empty():
			_resync_service.send_prebuilt_snapshot(int(pid), request_id, room, resume_start_snapshot_transfer, "start_game_resume_archive")
	GameLog.warn(
		"NetClient",
		"StartGame prepared %s %s mapped_players=%d waiting_for_ready=%d"
			% [
				_request_tag(peer_id, request_id),
				_room_brief(room),
				Dictionary(payload.get("player_id_by_peer_id", {})).size(),
				Array(room.get_pending_start_target_peer_ids()).size() if room.has_method("get_pending_start_target_peer_ids") else 0,
			]
	)

func handle_rpc_match_bootstrap_ready(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var bootstrap_id := str(request.get("bootstrap_id", "")).strip_edges()
	var room = _net._room_manager.get_room_by_peer(peer_id)
	GameLog.info(
		"NetClient",
		"RX MatchBootstrapReady %s bootstrap_id=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(bootstrap_id), _room_brief(room)]
	)
	if room == null or str(room.status) != "Starting":
		return
	if not room.has_method("has_pending_start_session") or not room.has_pending_start_session():
		return
	if room.has_method("get_pending_start_session_id") and str(room.get_pending_start_session_id()) != bootstrap_id:
		return
	if not room.has_method("mark_pending_start_peer_ready") or not room.mark_pending_start_peer_ready(peer_id):
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)

	if not room.has_method("is_pending_start_ready_to_commit") or not room.is_pending_start_ready_to_commit():
		return

	var start_request_id := _get_pending_start_request_id(room, request_id)
	if room.has_method("set_pending_start_phase"):
		room.set_pending_start_phase("committing")
	_mark_room_directory_dirty()
	broadcast_room_state(room)

	var commit_r: Result = room.commit_prepared_start_game()
	if not commit_r.ok:
		var failed_peer_ids: Array[int] = Array(room.get_peer_ids())
		_abort_pending_start_session(room, start_request_id, commit_r.error, failed_peer_ids, "match_bootstrap_failed")
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.warn(
		"NetClient",
		"Match bootstrap committed %s %s"
			% [_request_tag(peer_id, request_id), _room_brief(room)]
	)

func handle_rpc_match_bootstrap_failed(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var bootstrap_id := str(request.get("bootstrap_id", "")).strip_edges()
	var reason := str(request.get("reason", "")).strip_edges()
	if reason.is_empty():
		reason = "客户端初始化失败"
	var room = _net._room_manager.get_room_by_peer(peer_id)
	GameLog.warn(
		"NetClient",
		"RX MatchBootstrapFailed %s bootstrap_id=%s reason=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(bootstrap_id), _safe_text(reason), _room_brief(room)]
	)
	if room == null or str(room.status) != "Starting":
		return
	if not room.has_method("has_pending_start_session") or not room.has_pending_start_session():
		return
	if room.has_method("get_pending_start_session_id") and str(room.get_pending_start_session_id()) != bootstrap_id:
		return

	var failed_peer_ids: Array[int] = Array(room.get_pending_start_target_peer_ids()) if room.has_method("get_pending_start_target_peer_ids") else Array(room.get_peer_ids())
	var start_request_id := _get_pending_start_request_id(room, request_id)
	_abort_pending_start_session(room, start_request_id, reason, failed_peer_ids, "match_bootstrap_failed")

func handle_rpc_action_request(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var action_id := str(request.get("action_id", "")).strip_edges()
	var perf_request_val = request.get("perf", null)
	var perf_request: Dictionary = Dictionary(perf_request_val).duplicate(true) if perf_request_val is Dictionary else {}
	var server_rx_unix_ms := OnlinePerfTraceClass.now_unix_ms()
	var params_preview = request.get("params", null)
	var params_keys: Array = Array(Dictionary(params_preview).keys()) if params_preview is Dictionary else []
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("server.action_request.rx", {
			"request_id": request_id,
			"peer_id": peer_id,
			"action_id": action_id,
			"params_keys": params_keys,
			"client_request_unix_ms": int(perf_request.get("client_request_unix_ms", 0)),
			"client_to_server_ms_approx": server_rx_unix_ms - int(perf_request.get("client_request_unix_ms", server_rx_unix_ms)),
		})
	GameLog.debug(
		"NetClient",
		"RX ActionRequest %s action=%s params_keys=%s"
			% [_request_tag(peer_id, request_id), _safe_text(action_id), str(params_keys)]
	)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return
	if room.has_method("has_pending_rollback_proposal") and bool(room.has_pending_rollback_proposal()):
		send_request_rejected(peer_id, request_id, "rollback_proposal_pending", "Rollback proposal pending")
		return

	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "actor_missing", "No player mapping for peer")
		return

	if action_id.is_empty():
		send_request_rejected(peer_id, request_id, "invalid_params", "action_id is empty")
		return
	var params_val = request.get("params", null)
	var params: Dictionary = {}
	if params_val is Dictionary:
		params = Dictionary(params_val)

	var state = room.game_engine.get_state()
	if action_id == "confirm_dinnertime":
		GameLog.info(
			"NetClient",
			"RX confirm_dinnertime %s actor=%d phase=%s pending=%s confirmed=%s %s"
				% [
					_request_tag(peer_id, request_id),
					actor_id,
					_safe_text(str(state.phase)) if state != null else "-",
					_dinnertime_pending_brief(state),
					_dinnertime_confirmed_brief(state),
					_room_brief(room),
				]
		)
	if server_is_player_forfeited(state, actor_id):
		send_request_rejected(peer_id, request_id, "forfeited_readonly", "Player has forfeited (spectator, read-only)")
		return

	var cmd = CommandClass.create(action_id, actor_id, params)
	var exec_start_mono_usec := OnlinePerfTraceClass.now_mono_usec()
	var exec_start_unix_ms := OnlinePerfTraceClass.now_unix_ms()
	var r = room.game_engine.execute_command(cmd)
	var exec_end_unix_ms := OnlinePerfTraceClass.now_unix_ms()
	var perf_meta := {
		"request_id": request_id,
		"action_id": action_id,
		"peer_id": peer_id,
		"actor_id": actor_id,
		"room_code": str(room.room_code).strip_edges().to_upper(),
		"client_request_unix_ms": int(perf_request.get("client_request_unix_ms", 0)),
		"server_rx_unix_ms": server_rx_unix_ms,
		"server_exec_start_unix_ms": exec_start_unix_ms,
		"server_exec_end_unix_ms": exec_end_unix_ms,
		"server_exec_ms": float(maxi(0, OnlinePerfTraceClass.now_mono_usec() - exec_start_mono_usec)) / 1000.0,
	}
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("server.action_request.execute", {
			"request_id": request_id,
			"peer_id": peer_id,
			"actor_id": actor_id,
			"action_id": action_id,
			"room_code": str(room.room_code).strip_edges().to_upper(),
			"server_exec_ms": float(perf_meta.get("server_exec_ms", -1.0)),
			"ok": bool(r.ok),
		})
	if not r.ok:
		if action_id == "confirm_dinnertime":
			var phase := _safe_text(str(state.phase)) if state != null else "-"
			GameLog.warn(
				"NetClient",
				"confirm_dinnertime rejected %s actor=%d phase=%s err=%s pending=%s confirmed=%s %s"
					% [
						_request_tag(peer_id, request_id),
						actor_id,
						phase,
						_safe_text(str(r.error)),
						_dinnertime_pending_brief(state),
						_dinnertime_confirmed_brief(state),
						_room_brief(room),
					]
			)
		send_request_rejected(peer_id, request_id, "action_failed", r.error)
		return

	var state_hash := ""
	var state_after = room.game_engine.get_state()
	if state_after != null and state_after.has_method("compute_hash"):
		state_hash = str(state_after.compute_hash())
	if action_id == "confirm_dinnertime":
		GameLog.info(
			"NetClient",
			"confirm_dinnertime applied %s actor=%d phase=%s pending=%s confirmed=%s state_hash=%s %s"
				% [
					_request_tag(peer_id, request_id),
					actor_id,
					_safe_text(str(state_after.phase)) if state_after != null else "-",
					_dinnertime_pending_brief(state_after),
					_dinnertime_confirmed_brief(state_after),
					_short_hash(state_hash),
					_room_brief(room),
				]
		)
	GameLog.debug(
		"NetClient",
		"ActionRequest applied %s %s %s state_hash=%s"
			% [_request_tag(peer_id, request_id), _command_brief(cmd), _room_brief(room), _short_hash(state_hash)]
	)
	broadcast_command_applied(room, cmd, perf_meta)
	server_drain_forfeited_auto_steps(room)
	_try_finalize_match_if_game_over(room)

func handle_rpc_resync_request(_request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(_request.get("request_id", ""))
	var resume_cursor_val = _request.get("resume_cursor", null)
	var resume_cursor: Dictionary = Dictionary(resume_cursor_val).duplicate(true) if resume_cursor_val is Dictionary else {}
	var force_snapshot := bool(resume_cursor.get("force_snapshot", false))
	GameLog.warn("NetClient", "RX ResyncRequest %s" % _request_tag(peer_id, request_id))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return
	if _resync_service.is_request_rate_limited(peer_id, force_snapshot):
		send_request_rejected(peer_id, request_id, "resync_rate_limited", "Resync requested too frequently")
		return
	var resume_r: Result = _resync_service.send_best_effort_resume_transfer(
		peer_id,
		request_id,
		room,
		"resync_request",
		resume_cursor
	)
	if not resume_r.ok:
		var error_code := "resync_archive_too_large" if str(resume_r.error).begins_with("Resync archive too large") else "resync_failed"
		send_request_rejected(peer_id, request_id, error_code, resume_r.error)
		return
	var resume_payload: Dictionary = Dictionary(resume_r.value)
	_resync_service.remember_transfer_mode(peer_id, str(resume_payload.get("mode", "")))

func _broadcast_rollback_meta(peer_id: int, request_id: String, room, payload: Dictionary, actor_id: int, fallback_reason: String) -> void:
	var reason := str(payload.get("reason", fallback_reason)).strip_edges()
	if reason.is_empty():
		reason = str(fallback_reason).strip_edges()
	var out := {
		"request_id": request_id,
		"room_code": str(room.room_code).strip_edges().to_upper(),
		"target_index": int(payload.get("target_index", -1)),
		"before_index": int(payload.get("before_index", payload.get("current_index", -1))),
		"history_size": int(payload.get("history_size", -1)),
		"state_hash": str(payload.get("state_hash", "")),
		"noop": bool(payload.get("noop", false)),
		"player_id": actor_id,
		"reason": reason,
	}
	if payload.has("rolled_back_index"):
		out["rolled_back_index"] = int(payload.get("rolled_back_index", -1))
	if payload.has("rolled_back_action_id"):
		out["rolled_back_action_id"] = str(payload.get("rolled_back_action_id", "")).strip_edges()
	if payload.has("proposal_id"):
		out["proposal_id"] = str(payload.get("proposal_id", "")).strip_edges()
	if payload.has("proposer_player_id"):
		out["proposer_player_id"] = int(payload.get("proposer_player_id", -1))
	GameLog.warn(
		"NetClient",
		"Rollback prepared %s reason=%s actor=%d target=%d before=%d history=%d noop=%s state_hash=%s %s"
			% [
				_request_tag(peer_id, request_id),
				_safe_text(str(out.get("reason", ""))),
				actor_id,
				int(out.get("target_index", -1)),
				int(out.get("before_index", -1)),
				int(out.get("history_size", -1)),
				str(bool(out.get("noop", false))),
				_short_hash(str(out.get("state_hash", ""))),
				_room_brief(room)
			]
	)

	# 广播元数据：各客户端本地 rewind + truncate，避免发送大 archive 导致 WebSocket buffer 溢出。
	if room.has_method("get_peer_ids"):
		for pid in Array(room.get_peer_ids()):
			var target_peer_id := int(pid)
			if target_peer_id <= 0:
				continue
			_net.rpc_id(target_peer_id, "rpc_rollback_meta", out)
	else:
		_net.rpc_id(peer_id, "rpc_rollback_meta", out)

func handle_rpc_rewind_to_turn_start(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	GameLog.warn("NetClient", "RX RewindToTurnStart %s" % _request_tag(peer_id, request_id))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	# Spectator：只读，不允许发起回退（避免影响对局）
	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot request rewind")
		return

	# 非同时阶段仅允许当前玩家；同时阶段使用发起 peer 对应的玩家作为回退主体。
	var state = room.game_engine.get_state()
	if state == null:
		send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	if not OnlinePhaseInteractionClass.can_player_request_rewind_in_online_phase(state, actor_id):
		send_request_rejected(peer_id, request_id, "not_current_player", "Only the acting player can request rewind")
		return

	if not room.has_method("rewind_to_current_player_turn_start"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rewind")
		return

	var rr = room.rewind_to_current_player_turn_start(false, actor_id)
	if not rr.ok:
		send_request_rejected(peer_id, request_id, "rewind_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		send_request_rejected(peer_id, request_id, "rewind_failed", "rewind result type invalid")
		return

	_broadcast_rollback_meta(peer_id, request_id, room, Dictionary(rr.value), actor_id, "rewind_turn_start")

	broadcast_room_state(room)

func handle_rpc_rollback_last_command(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	GameLog.warn("NetClient", "RX RollbackLastCommand %s" % _request_tag(peer_id, request_id))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return

	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot request rollback")
		return

	var state = room.game_engine.get_state()
	if state == null:
		send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	var current_index := int(room.game_engine.current_command_index)
	if current_index < 0 or current_index >= int(room.game_engine.command_history.size()):
		send_request_rejected(peer_id, request_id, "rollback_failed", "No command to rollback")
		return
	var cmd_val = room.game_engine.command_history[current_index]
	if not (cmd_val is Command):
		send_request_rejected(peer_id, request_id, "rollback_failed", "Last command type invalid")
		return
	var cmd: Command = cmd_val
	if int(cmd.actor) != actor_id:
		send_request_rejected(peer_id, request_id, "not_last_actor", "Only the player who made the last command can roll it back")
		return
	if str(cmd.action_id) == ActionIdsClass.END_TURN or str(cmd.action_id) == ActionIdsClass.SKIP:
		send_request_rejected(peer_id, request_id, "turn_already_ended", "Ended turns require a rollback proposal")
		return
	if not room.has_method("rollback_last_command_for_player"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rollback")
		return

	var rr = room.rollback_last_command_for_player(false, actor_id)
	if not rr.ok:
		send_request_rejected(peer_id, request_id, "rollback_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		send_request_rejected(peer_id, request_id, "rollback_failed", "rollback result type invalid")
		return

	_broadcast_rollback_meta(peer_id, request_id, room, Dictionary(rr.value), actor_id, "undo_last_command")
	broadcast_room_state(room)

func handle_rpc_request_rollback_proposal(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var target_index := int(request.get("target_index", -999))
	GameLog.warn("NetClient", "RX RollbackProposal %s target=%d" % [_request_tag(peer_id, request_id), target_index])
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return
	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot propose rollback")
		return
	if not room.has_method("create_rollback_proposal"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rollback proposal")
		return

	var proposal_r: Result = room.create_rollback_proposal(
		request_id,
		peer_id,
		actor_id,
		target_index,
		str(request.get("reason", "proposal_rollback")).strip_edges()
	)
	if not proposal_r.ok:
		send_request_rejected(peer_id, request_id, "rollback_proposal_failed", proposal_r.error)
		return
	broadcast_room_state(room)
	var proposal: Dictionary = Dictionary(proposal_r.value) if proposal_r.value is Dictionary else {}
	if Array(proposal.get("required_player_ids", [])).is_empty():
		_execute_approved_rollback_proposal(peer_id, request_id, str(proposal.get("proposal_id", request_id)), room, proposal)

func handle_rpc_vote_rollback_proposal(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var proposal_id := str(request.get("proposal_id", "")).strip_edges()
	var approve := bool(request.get("approve", false))
	GameLog.warn(
		"NetClient",
		"RX RollbackProposalVote %s proposal=%s approve=%s"
			% [_request_tag(peer_id, request_id), _safe_text(proposal_id), str(approve)]
	)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot vote rollback")
		return
	if not room.has_method("vote_rollback_proposal"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rollback proposal vote")
		return

	var vote_r: Result = room.vote_rollback_proposal(proposal_id, actor_id, approve)
	if not vote_r.ok:
		send_request_rejected(peer_id, request_id, "rollback_vote_failed", vote_r.error)
		return
	var proposal: Dictionary = Dictionary(vote_r.value) if vote_r.value is Dictionary else {}
	var status := str(proposal.get("status", "pending")).strip_edges()
	if status == "rejected":
		broadcast_room_state(room)
		return
	if status != "approved":
		broadcast_room_state(room)
		return
	_execute_approved_rollback_proposal(peer_id, request_id, proposal_id, room, proposal)

func _execute_approved_rollback_proposal(peer_id: int, request_id: String, proposal_id: String, room, proposal: Dictionary) -> void:
	if room == null or room.game_engine == null:
		return
	var before_index := int(proposal.get("before_index", -1))
	if int(room.game_engine.current_command_index) != before_index:
		if room.has_method("clear_pending_rollback_proposal"):
			room.clear_pending_rollback_proposal()
		broadcast_room_state(room)
		send_request_rejected(peer_id, request_id, "rollback_proposal_stale", "Rollback proposal is stale")
		return
	var target_index := int(proposal.get("target_index", -1))
	var proposer_pid := int(proposal.get("proposer_player_id", -1))
	var rr: Result = room.rollback_to_command_index(target_index, false, proposer_pid, "proposal_rollback")
	if not rr.ok:
		if room.has_method("clear_pending_rollback_proposal"):
			room.clear_pending_rollback_proposal()
		broadcast_room_state(room)
		send_request_rejected(peer_id, request_id, "rollback_failed", rr.error)
		return
	if rr.value is Dictionary:
		var payload: Dictionary = Dictionary(rr.value).duplicate(true)
		payload["proposal_id"] = proposal_id
		payload["proposer_player_id"] = proposer_pid
		_broadcast_rollback_meta(peer_id, proposal_id, room, payload, proposer_pid, "proposal_rollback")
	broadcast_room_state(room)

func handle_rpc_request_full_archive_export(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	GameLog.info("NetClient", "RX FullArchiveExport %s" % _request_tag(peer_id, request_id))
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, request_id, "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, request_id, "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, request_id, "engine_missing", "Room engine missing")
		return
	if not room.has_method("build_full_authority_archive_export"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room.build_full_authority_archive_export missing")
		return

	var export_r: Result = room.build_full_authority_archive_export()
	if not export_r.ok:
		send_request_rejected(peer_id, request_id, "full_archive_export_failed", export_r.error)
		return
	if not (export_r.value is Dictionary):
		send_request_rejected(peer_id, request_id, "full_archive_export_failed", "export result type invalid")
		return
	var export_info: Dictionary = Dictionary(export_r.value)
	var archive: Dictionary = Dictionary(export_info.get("archive", {})).duplicate(true)
	if archive.is_empty():
		send_request_rejected(peer_id, request_id, "full_archive_export_failed", "archive missing")
		return

	_net.rpc_id(peer_id, "rpc_full_archive_export_ready", {
		"request_id": request_id,
		"room_code": str(export_info.get("room_code", room.room_code)).strip_edges().to_upper(),
		"archive": archive,
		"history_size": int(export_info.get("history_size", Array(archive.get("commands", [])).size())),
		"final_hash": str(export_info.get("final_hash", archive.get("final_hash", ""))).strip_edges(),
	})
	GameLog.info(
		"NetClient",
		"FullArchiveExport ready %s room=%s commands=%d final_hash=%s"
			% [
				_request_tag(peer_id, request_id),
				_safe_text(str(export_info.get("room_code", room.room_code)).to_upper()),
				Array(archive.get("commands", [])).size(),
				_short_hash(str(export_info.get("final_hash", archive.get("final_hash", ""))))
			]
	)

func broadcast_command_applied(room, cmd, perf_meta: Dictionary = {}) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null or cmd == null:
		return
	if room.game_engine == null:
		return
	var state_hash := ""
	var state = room.game_engine.get_state()
	if state != null and state.has_method("compute_hash"):
		state_hash = str(state.compute_hash())
	var payload := {
		"cmd": cmd.to_dict(),
		"state_hash": state_hash,
	}
	if room.has_method("record_resume_delta"):
		var delta_record_r: Result = room.record_resume_delta(cmd, state_hash)
		if not delta_record_r.ok:
			GameLog.error(
				"NetClient",
				"Resume delta record failed room=%s cmd=%s hash=%s error=%s"
					% [
						ServerLogFormatClass.safe_text(str(room.room_code).to_upper()),
						ServerLogFormatClass.safe_text(str(cmd.action_id)),
						ServerLogFormatClass.short_hash(state_hash),
						ServerLogFormatClass.safe_text(delta_record_r.error),
					]
			)
	_maybe_request_round_end_autosave(room, cmd, state, state_hash)
	var targets := Array(room.get_peer_ids())
	var broadcast_start_mono_usec := OnlinePerfTraceClass.now_mono_usec()
	var broadcast_fields := Dictionary(perf_meta).duplicate(true)
	if not broadcast_fields.is_empty():
		broadcast_fields["state_hash"] = state_hash
		broadcast_fields["recipient_count"] = targets.size()
	for pid in targets:
		var per_peer_payload := payload.duplicate(true)
		if not broadcast_fields.is_empty():
			var per_peer_perf := broadcast_fields.duplicate(true)
			per_peer_perf["target_peer_id"] = int(pid)
			per_peer_perf["server_peer_send_unix_ms"] = OnlinePerfTraceClass.now_unix_ms()
			per_peer_payload["perf"] = per_peer_perf
		_net.rpc_id(int(pid), "rpc_command_applied", per_peer_payload)
	if OnlinePerfTraceClass.enabled():
		OnlinePerfTraceClass.emit_event("server.command_applied.tx", {
			"request_id": str(broadcast_fields.get("request_id", "")),
			"action_id": str(cmd.action_id),
			"actor_id": int(cmd.actor),
			"room_code": str(room.room_code).strip_edges().to_upper(),
			"recipient_count": targets.size(),
			"server_broadcast_ms": float(maxi(0, OnlinePerfTraceClass.now_mono_usec() - broadcast_start_mono_usec)) / 1000.0,
		})
	GameLog.debug(
		"NetClient",
		"TX CommandApplied %s state_hash=%s recipients=%d %s"
			% [_command_brief(cmd), _short_hash(state_hash), targets.size(), _room_brief(room)]
	)

func _maybe_request_round_end_autosave(room, cmd, state, state_hash: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null or cmd == null or state == null:
		return
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		if not _net.has_method("request_server_round_autosave"):
			return
		var game_over_room_code := str(room.room_code).strip_edges().to_upper()
		if game_over_room_code.is_empty():
			return
		var final_round_number := int(state.round_number)
		if str(cmd.phase) == DefsClass.PHASE_CLEANUP and final_round_number > 1:
			final_round_number -= 1
		if final_round_number <= 0:
			final_round_number = 1
		_net.request_server_round_autosave(game_over_room_code, final_round_number, str(state_hash).strip_edges(), "game_over")
		return
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return
	if not _command_phase_can_complete_round(str(cmd.phase)):
		return
	var completed_round_number := int(state.round_number) - 1
	if completed_round_number <= 0:
		return
	if not _net.has_method("request_server_round_autosave"):
		return
	var room_code := str(room.room_code).strip_edges().to_upper()
	if room_code.is_empty():
		return
	_net.request_server_round_autosave(room_code, completed_round_number, str(state_hash).strip_edges(), "round_end")

func _command_phase_can_complete_round(command_phase: String) -> bool:
	match str(command_phase).strip_edges():
		DefsClass.PHASE_DINNERTIME:
			return true
		DefsClass.PHASE_PAYDAY:
			return true
		DefsClass.PHASE_MARKETING:
			return true
		DefsClass.PHASE_CLEANUP:
			return true
		_:
			return false

func server_is_player_forfeited(state, player_id: int) -> bool:
	if state == null:
		return false
	if player_id < 0 or player_id >= state.players.size():
		return false
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return false
	return bool(Dictionary(p_val).get("forfeited", false))

func server_pick_order_of_business_position(state) -> int:
	if state == null or not (state.round_state is Dictionary):
		return -1
	var oob_val = Dictionary(state.round_state).get("order_of_business", null)
	if not (oob_val is Dictionary):
		return -1
	var oob: Dictionary = oob_val
	var picks_val = oob.get("picks", null)
	if not (picks_val is Array):
		return -1
	var picks: Array = picks_val
	for pos in range(picks.size() - 1, -1, -1):
		if int(picks[pos]) == -1:
			return pos
	return -1

func server_try_auto_submit_forfeited_restructuring(room) -> bool:
	if room == null or room.game_engine == null:
		return false
	var state = room.game_engine.get_state()
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return false
	if int(state.round_number) <= 1:
		return false
	if not (state.round_state is Dictionary):
		return false
	var r_val = Dictionary(state.round_state).get("restructuring", null)
	if not (r_val is Dictionary):
		return false
	var r: Dictionary = r_val
	var submitted_val = r.get("submitted", null)
	if not (submitted_val is Dictionary):
		return false
	var submitted: Dictionary = submitted_val

	var any := false
	for pid in range(state.players.size()):
		if not server_is_player_forfeited(state, pid):
			continue
		if bool(submitted.get(pid, false)):
			continue
		var cmd = CommandClass.create("submit_restructuring", pid, {})
		var exec_r = room.game_engine.execute_command(cmd)
		if not exec_r.ok:
			GameLog.error("NetClient", "auto submit_restructuring failed: %s" % exec_r.error)
			return any
		GameLog.debug("NetClient", "Auto submit_restructuring actor=%d %s" % [pid, _room_brief(room)])
		broadcast_command_applied(room, cmd)
		any = true
	return any

func server_try_auto_select_forfeited_reserve_cards(room) -> bool:
	if room == null or room.game_engine == null:
		return false
	var state = room.game_engine.get_state()
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_SETUP or str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
		return false

	var any := false
	for pid in range(state.players.size()):
		if not server_is_player_forfeited(state, pid):
			continue
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			continue
		var player: Dictionary = player_val
		if _server_has_selected_reserve_card(player):
			continue
		var cmd = CommandClass.create("select_reserve_card", pid, {"selected_index": 0})
		var exec_r = room.game_engine.execute_command(cmd)
		if not exec_r.ok:
			GameLog.error("NetClient", "auto select_reserve_card failed: %s" % exec_r.error)
			return any
		GameLog.debug("NetClient", "Auto select_reserve_card actor=%d %s" % [pid, _room_brief(room)])
		broadcast_command_applied(room, cmd)
		any = true
		state = room.game_engine.get_state()
		if state == null or str(state.phase) != DefsClass.PHASE_SETUP or str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
			return any
	return any

func _server_has_selected_reserve_card(player: Dictionary) -> bool:
	var v = player.get("reserve_card_selected", -1)
	if v is int:
		return int(v) >= 0
	if v is float:
		var f: float = float(v)
		return f == floor(f) and int(f) >= 0
	return false

func server_drain_forfeited_auto_steps(room) -> void:
	if room == null or room.game_engine == null:
		return
	if room.has_method("get_peer_ids"):
		var peers_val = room.get_peer_ids()
		if peers_val is Array and (peers_val as Array).is_empty():
			return

	var safety := 0
	while safety < 128:
		safety += 1
		var state = room.game_engine.get_state()
		if state == null:
			return
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
			return

		if server_try_auto_select_forfeited_reserve_cards(room):
			continue

		if server_try_auto_submit_forfeited_restructuring(room):
			continue

		var current_pid := int(state.get_current_player_id())
		if current_pid < 0:
			return
		if not server_is_player_forfeited(state, current_pid):
			return

		var cmd = null
		if str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			cmd = CommandClass.create("select_reserve_card", current_pid, {"selected_index": 0})
		elif str(state.phase) == DefsClass.PHASE_RESTRUCTURING and int(state.round_number) > 1:
			cmd = CommandClass.create("submit_restructuring", current_pid, {})
		elif str(state.phase) == DefsClass.PHASE_ORDER_OF_BUSINESS:
			var pos := server_pick_order_of_business_position(state)
			if pos < 0:
				return
			cmd = CommandClass.create("choose_turn_order", current_pid, {"position": pos})
		elif str(state.phase) == DefsClass.PHASE_WORKING:
			cmd = CommandClass.create(ActionIdsClass.SKIP_SUB_PHASE, current_pid, {})
		else:
			cmd = CommandClass.create(ActionIdsClass.SKIP, current_pid, {})

		var exec_r2 = room.game_engine.execute_command(cmd)
		if not exec_r2.ok:
			GameLog.error("NetClient", "auto step failed: %s (action=%s)" % [exec_r2.error, str(cmd.action_id)])
			return
		GameLog.debug("NetClient", "Auto step executed %s %s" % [_command_brief(cmd), _room_brief(room)])
		broadcast_command_applied(room, cmd)

	GameLog.error("NetClient", "auto steps exceeded safety limit")
