# NetClient：Server-only 逻辑（room 管理 + 广播 + forfeit 自动推进）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：广播与逐命令同步等热路径走 DEBUG，异常/回灌/拒绝请求保留 WARN/ERROR。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const DEFAULT_RESTAURANT_LOGO_COUNT := 6
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"
const DEFAULT_DISCONNECT_GRACE_PERIOD_SEC := 120.0

var _net = null
var connect_token_secret_override: String = ""
var disconnect_grace_period_sec_override: float = -1.0
var _disconnect_forfeit_ticket_by_key: Dictionary = {} # "ROOM:actor_id" -> ticket (int)

func setup(net_client) -> void:
	_net = net_client

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

func _disconnect_forfeit_key(room_code: String, actor_id: int) -> String:
	return "%s:%d" % [str(room_code).strip_edges().to_upper(), int(actor_id)]

func _is_actor_connected(room, actor_id: int) -> bool:
	if room == null or not (room.player_id_by_peer_id is Dictionary):
		return false
	for v in Dictionary(room.player_id_by_peer_id).values():
		var pid := -999999
		if v is int:
			pid = int(v)
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				pid = int(f)
		if pid == actor_id:
			return true
	return false

func _schedule_disconnect_forfeit(room, actor_id: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null or room.game_engine == null:
		return
	if actor_id < 0:
		return
	var grace_sec := _get_disconnect_grace_period_sec()
	var room_code := str(room.room_code).strip_edges().to_upper()
	var key := _disconnect_forfeit_key(room_code, actor_id)
	var ticket := int(_disconnect_forfeit_ticket_by_key.get(key, 0)) + 1
	_disconnect_forfeit_ticket_by_key[key] = ticket

	if grace_sec <= 0.0:
		_on_disconnect_grace_timeout(room_code, actor_id, ticket)
		return

	var tree = _net.get_tree()
	if tree == null or not (tree is SceneTree):
		return
	var timer = (tree as SceneTree).create_timer(grace_sec)
	timer.timeout.connect(Callable(self, "_on_disconnect_grace_timeout").bind(room_code, actor_id, ticket))
	GameLog.warn(
		"NetClient",
		"Disconnect grace scheduled room=%s actor=%d grace_sec=%.1f"
			% [_safe_text(room_code), actor_id, grace_sec]
	)

func _clear_disconnect_forfeit(room_code: String, actor_id: int) -> void:
	var key := _disconnect_forfeit_key(room_code, actor_id)
	if _disconnect_forfeit_ticket_by_key.has(key):
		_disconnect_forfeit_ticket_by_key.erase(key)

func _on_disconnect_grace_timeout(room_code: String, actor_id: int, ticket: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var key := _disconnect_forfeit_key(room_code, actor_id)
	if int(_disconnect_forfeit_ticket_by_key.get(key, 0)) != int(ticket):
		return
	_disconnect_forfeit_ticket_by_key.erase(key)

	if _net._room_manager == null:
		return
	var rm = _net._room_manager
	if not (rm.rooms is Dictionary):
		return
	var room = rm.rooms.get(str(room_code).strip_edges().to_upper(), null)
	if room == null or room.game_engine == null or str(room.status) != "InGame":
		return
	if _is_actor_connected(room, actor_id):
		return

	var state = room.game_engine.get_state()
	if server_is_player_forfeited(state, actor_id):
		return

	var cmd = CommandClass.create("forfeit_player", actor_id, {})
	var fr = room.game_engine.execute_command(cmd)
	if fr.ok:
		GameLog.warn("NetClient", "Applied forfeit after disconnect grace room=%s actor=%d" % [_safe_text(room_code), actor_id])
		broadcast_command_applied(room, cmd)
		server_drain_forfeited_auto_steps(room)
		broadcast_room_state(room)
		broadcast_room_list("")
	else:
		GameLog.error("NetClient", "forfeit_player failed after disconnect grace room=%s actor=%d err=%s" % [_safe_text(room_code), actor_id, fr.error])

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

func _request_tag(peer_id: int, request_id: String) -> String:
	return "peer=%d request_id=%s" % [peer_id, _safe_text(request_id)]

func _room_brief(room) -> String:
	if room == null:
		return "room=- status=- host=0 players=0 spectators=0 peers=0"
	var room_code := _safe_text(str(room.room_code).to_upper())
	var status := _safe_text(str(room.status))
	var host_peer_id := int(room.host_peer_id)
	var players := 0
	var spectators := 0
	if room.has_method("to_room_state_dict"):
		var state: Dictionary = room.to_room_state_dict()
		var players_val = state.get("players", null)
		if players_val is Array:
			players = Array(players_val).size()
		var spectators_val = state.get("spectators", null)
		if spectators_val is Array:
			spectators = Array(spectators_val).size()
	var peers := 0
	if room.has_method("get_peer_ids"):
		peers = Array(room.get_peer_ids()).size()
	return "room=%s status=%s host=%d players=%d spectators=%d peers=%d" % [
		room_code,
		status,
		host_peer_id,
		players,
		spectators,
		peers
	]

func _command_brief(cmd) -> String:
	if cmd == null:
		return "action=- actor=-1 index=-1"
	return "action=%s actor=%d index=%d" % [
		_safe_text(str(cmd.action_id)),
		int(cmd.actor),
		int(cmd.index)
	]

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

	_net._profile_by_peer_id.erase(peer_id)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	var in_game := room != null and str(room.status) == "InGame"
	var actor_id := -1
	if room != null and (room.player_id_by_peer_id is Dictionary):
		if room.player_id_by_peer_id.has(peer_id):
			actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
			room.player_id_by_peer_id.erase(peer_id)
		elif room.player_id_by_peer_id.has(str(peer_id)):
			actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
			room.player_id_by_peer_id.erase(str(peer_id))

	var removed := false
	var rr = _net._room_manager.disconnect_peer(peer_id) if in_game else _net._room_manager.leave_room(peer_id)
	if rr.ok:
		removed = bool(rr.value.get("removed", false))
	else:
		GameLog.error(
			"NetClient",
			"disconnect handling failed peer=%d in_game=%s err=%s %s"
				% [peer_id, str(in_game), rr.error, _room_brief(room)]
		)

	# 房间已被清理（无任何在线成员）：直接关闭对局，不再执行 forfeit/auto step。
	# 否则，服务器会在无人在线时继续自动推进（直到 safety limit）。
	if in_game and removed and room != null and room.game_engine != null:
		if room.game_engine.has_method("dispose"):
			room.game_engine.dispose()
		room.game_engine = null

	if in_game and not removed and actor_id >= 0 and room.game_engine != null:
		_schedule_disconnect_forfeit(room, actor_id)

	if rr.ok and room != null and not removed:
		broadcast_room_state(room)
		broadcast_room_list("")
		GameLog.info("NetClient", "Disconnect handled keep-room peer=%d removed=%s %s" % [peer_id, str(removed), _room_brief(room)])
	elif rr.ok and removed:
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

func broadcast_room_state(room) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null:
		return
	var state: Dictionary = room.to_room_state_dict()
	var targets := Array(room.get_peer_ids())
	for peer_id in targets:
		_net.rpc_id(peer_id, "rpc_room_state", state)
	GameLog.debug("NetClient", "TX RoomState %s recipients=%d" % [_room_brief(room), targets.size()])

func empty_room_state() -> Dictionary:
	return {
		"room_code": "",
		"host_peer_id": 0,
		"players": [],
		"spectators": [],
		"password_required": false,
		"allow_spectators": true,
		"config": {},
		"status": "Lobby",
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
	if not secret.is_empty():
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
		var jr: Result = _platform_auto_join(peer_id, request_id, normalized_profile, token_payload)
		if not jr.ok:
			_net._profile_by_peer_id.erase(peer_id)
			send_request_rejected(peer_id, request_id, "platform_join_failed", jr.error)
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

func _platform_auto_join(peer_id: int, request_id: String, profile: Dictionary, token_payload: Dictionary) -> Result:
	if _net == null or not is_instance_valid(_net):
		return Result.failure("NetClient missing")
	if _net._room_manager == null or not is_instance_valid(_net._room_manager):
		return Result.failure("RoomManager missing")

	var room_code := str(token_payload.get("room_code", "")).strip_edges().to_upper()
	var role := str(token_payload.get("role", "")).strip_edges()
	if room_code.is_empty():
		return Result.failure("connect_token missing room_code")
	if role != "host" and role != "player" and role != "spectator":
		return Result.failure("connect_token invalid role: %s" % role)

	var rm = _net._room_manager
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
		if seat_index < 0:
			return Result.failure("connect_token missing seat_index")

		var config: Dictionary = {}
		var cfg_json := str(token_payload.get("config_json", "")).strip_edges()
		if not cfg_json.is_empty():
			var parsed: Variant = JSON.parse_string(cfg_json)
			if not (parsed is Dictionary):
				return Result.failure("connect_token config_json 类型错误（期望 JSON Dictionary）")
			config = Dictionary(parsed)

		var existing = rm.rooms.get(room_code, null) if (rm.rooms is Dictionary) else null
		if existing == null:
			if not rm.has_method("create_room_with_code"):
				return Result.failure("RoomManager.create_room_with_code missing")
			r = rm.create_room_with_code(peer_id, profile, room_code, config)
		elif str(existing.status) == "InGame":
			if not rm.has_method("reconnect_player"):
				return Result.failure("RoomManager.reconnect_player missing")
			var user_id := str(token_payload.get("user_id", "")).strip_edges()
			r = rm.reconnect_player(peer_id, profile, room_code, seat_index, user_id, "host")
		else:
			if not rm.has_method("join_room_with_seat"):
				return Result.failure("RoomManager.join_room_with_seat missing")
			r = rm.join_room_with_seat(peer_id, profile, room_code, seat_index, "host")
	elif role == "player":
		var seat_index_val2 = token_payload.get("seat_index", null)
		var seat_index2 := -1
		if seat_index_val2 is int:
			seat_index2 = int(seat_index_val2)
		elif seat_index_val2 is float:
			var f2: float = float(seat_index_val2)
			if f2 == floor(f2):
				seat_index2 = int(f2)
		if seat_index2 < 0:
			return Result.failure("connect_token missing seat_index")

		var existing2 = rm.rooms.get(room_code, null) if (rm.rooms is Dictionary) else null
		if existing2 != null and str(existing2.status) == "InGame":
			if not rm.has_method("reconnect_player"):
				return Result.failure("RoomManager.reconnect_player missing")
			var user_id2 := str(token_payload.get("user_id", "")).strip_edges()
			r = rm.reconnect_player(peer_id, profile, room_code, seat_index2, user_id2)
		else:
			if not rm.has_method("join_room_with_seat"):
				return Result.failure("RoomManager.join_room_with_seat missing")
			r = rm.join_room_with_seat(peer_id, profile, room_code, seat_index2)
	else:
		if not rm.has_method("spectate_room"):
			return Result.failure("RoomManager.spectate_room missing")
		r = rm.spectate_room(peer_id, profile, room_code)

	if not r.ok:
		return r

	var payload: Dictionary = Dictionary(r.value) if (r.value is Dictionary) else {}
	var room = payload.get("room", null)
	if room == null:
		return Result.failure("platform auto join missing room")
	var actual_role := str(payload.get("role", "")).strip_edges()
	if not actual_role.is_empty() and actual_role != role:
		return Result.failure("platform auto join role mismatch: token=%s actual=%s" % [role, actual_role])

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
			_clear_disconnect_forfeit(room_code, seat_index3)

	# InGame：自动下发 GameStarted + ResyncArchive（与 JoinRoom in-game 行为对齐）
	if str(room.status) == "InGame" and room.game_engine != null:
		_net.rpc_id(peer_id, "rpc_game_started", {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
		})
		var archive_r = room.game_engine.create_archive()
		if archive_r.ok:
			_net.rpc_id(peer_id, "rpc_resync_archive", {
				"archive": Dictionary(archive_r.value).duplicate(true),
			})
		else:
			GameLog.error(
				"NetClient",
				"Platform auto join in-game archive create failed %s err=%s"
					% [_request_tag(peer_id, request_id), archive_r.error]
			)

	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"Platform auto join ok %s role=%s room=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(role), _safe_text(room_code), _room_brief(room)]
	)
	return Result.success({"room_code": room_code, "role": role})

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
		var bd_read := ModuleDirSpecClass.parse_base_dirs(bd)
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

	var jr = _net._room_manager.join_room(peer_id, profile, room_code, room_password)
	if not jr.ok:
		send_request_rejected(peer_id, request_id, "join_room_failed", jr.error)
		return

	var room = Dictionary(jr.value).get("room", null)
	if room == null:
		send_request_rejected(peer_id, request_id, "join_room_failed", "Missing room in result")
		return

	var role := str(Dictionary(jr.value).get("role", "player"))
	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.info(
		"NetClient",
		"JoinRoom success %s role=%s %s"
			% [_request_tag(peer_id, request_id), _safe_text(role), _room_brief(room)]
	)
	if str(room.status) == "InGame" and room.game_engine != null:
		var payload := {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
		}
		_net.rpc_id(peer_id, "rpc_game_started", payload)
		var archive_r = room.game_engine.create_archive()
		if archive_r.ok:
			_net.rpc_id(peer_id, "rpc_resync_archive", {
				"archive": Dictionary(archive_r.value).duplicate(true),
			})
			GameLog.warn(
				"NetClient",
				"JoinRoom in-game resync sent %s history_size=%d state_hash=%s"
					% [
						_request_tag(peer_id, request_id),
						int(room.game_engine.command_history.size()),
						_short_hash(str(room.game_engine.get_state().compute_hash() if room.game_engine.get_state() != null else ""))
					]
			)
		else:
			GameLog.error(
				"NetClient",
				"JoinRoom in-game archive create failed %s err=%s"
					% [_request_tag(peer_id, request_id), archive_r.error]
			)

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
		var bd_read := ModuleDirSpecClass.parse_base_dirs(bd)
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

	broadcast_room_state(room)
	broadcast_room_list("")
	GameLog.debug(
		"NetClient",
		"UpdateRoomConfig success %s %s patch_keys=%s"
			% [_request_tag(peer_id, request_id), _room_brief(room), str(Array(patch.keys()))]
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

	var lr = _net._room_manager.leave_room(peer_id)
	if not lr.ok:
		send_request_rejected(peer_id, request_id, "leave_room_failed", lr.error)
		return

	var removed := bool(lr.value.get("removed", false))
	if room != null and not removed:
		broadcast_room_state(room)
	broadcast_room_list("")

	_net.rpc_id(peer_id, "rpc_room_state", empty_room_state())
	GameLog.info(
		"NetClient",
		"LeaveRoom success %s removed=%s previous_room=%s"
			% [_request_tag(peer_id, request_id), str(removed), _room_brief(room)]
	)

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

	var sr = room.start_game()
	if not sr.ok:
		send_request_rejected(peer_id, request_id, "start_game_failed", sr.error)
		return

	broadcast_room_state(room)
	broadcast_room_list("")

	var payload_val: Dictionary = Dictionary(sr.value)
	var payload := {
		"player_id_by_peer_id": Dictionary(payload_val.get("player_id_by_peer_id", {})),
		"config": Dictionary(payload_val.get("config", {})),
	}

	for pid in room.get_peer_ids():
		_net.rpc_id(int(pid), "rpc_game_started", payload)
	GameLog.warn(
		"NetClient",
		"StartGame success %s %s mapped_players=%d"
			% [_request_tag(peer_id, request_id), _room_brief(room), Dictionary(payload.get("player_id_by_peer_id", {})).size()]
	)

func handle_rpc_action_request(request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	var request_id := str(request.get("request_id", ""))
	var action_id := str(request.get("action_id", "")).strip_edges()
	var params_preview = request.get("params", null)
	var params_keys: Array = Array(Dictionary(params_preview).keys()) if params_preview is Dictionary else []
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

	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
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
	var r = room.game_engine.execute_command(cmd)
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
	broadcast_command_applied(room, cmd)
	server_drain_forfeited_auto_steps(room)

func handle_rpc_resync_request(_request: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return

	var peer_id: int = int(_net.multiplayer.get_remote_sender_id())
	GameLog.warn("NetClient", "RX ResyncRequest peer=%d" % peer_id)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	if room == null:
		send_request_rejected(peer_id, "", "not_in_room", "Not in room")
		return
	if str(room.status) != "InGame":
		send_request_rejected(peer_id, "", "not_in_game", "Room not in game")
		return
	if room.game_engine == null:
		send_request_rejected(peer_id, "", "engine_missing", "Room engine missing")
		return

	var archive_r = room.game_engine.create_archive()
	if not archive_r.ok:
		send_request_rejected(peer_id, "", "resync_failed", archive_r.error)
		return

	_net.rpc_id(peer_id, "rpc_resync_archive", {
		"archive": Dictionary(archive_r.value).duplicate(true),
	})
	var state_hash := ""
	var state = room.game_engine.get_state()
	if state != null and state.has_method("compute_hash"):
		state_hash = str(state.compute_hash())
	GameLog.warn(
		"NetClient",
		"TX ResyncArchive peer=%d %s history_size=%d state_hash=%s"
			% [peer_id, _room_brief(room), int(room.game_engine.command_history.size()), _short_hash(state_hash)]
	)

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
	var actor_id := -1
	if room.player_id_by_peer_id.has(peer_id):
		actor_id = int(room.player_id_by_peer_id.get(peer_id, -1))
	elif room.player_id_by_peer_id.has(str(peer_id)):
		actor_id = int(room.player_id_by_peer_id.get(str(peer_id), -1))
	if actor_id < 0:
		send_request_rejected(peer_id, request_id, "spectator_readonly", "Spectator cannot request rewind")
		return

	# 仅允许“当前玩家”发起回退（避免旁观/非当前回合玩家影响对局）。
	var state = room.game_engine.get_state()
	if state == null:
		send_request_rejected(peer_id, request_id, "state_missing", "Room state missing")
		return
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING and int(state.get_current_player_id()) != actor_id:
		send_request_rejected(peer_id, request_id, "not_current_player", "Only current player can request rewind")
		return

	if not room.has_method("rewind_to_current_player_turn_start"):
		send_request_rejected(peer_id, request_id, "not_supported", "Room does not support rewind")
		return

	var rr = room.rewind_to_current_player_turn_start(false)
	if not rr.ok:
		send_request_rejected(peer_id, request_id, "rewind_failed", rr.error)
		return
	if not (rr.value is Dictionary):
		send_request_rejected(peer_id, request_id, "rewind_failed", "rewind result type invalid")
		return

	var payload: Dictionary = Dictionary(rr.value)
	var out := {
		"request_id": request_id,
		"target_index": int(payload.get("target_index", -1)),
		"before_index": int(payload.get("before_index", payload.get("current_index", -1))),
		"history_size": int(payload.get("history_size", -1)),
		"state_hash": str(payload.get("state_hash", "")),
		"noop": bool(payload.get("noop", false)),
	}
	GameLog.warn(
		"NetClient",
		"Rewind prepared %s actor=%d target=%d before=%d history=%d noop=%s state_hash=%s %s"
			% [
				_request_tag(peer_id, request_id),
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
			_net.rpc_id(target_peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})
	else:
		_net.rpc_id(peer_id, "rpc_resync_archive", {"archive": {"_rewind_to_turn_start": out}})

	broadcast_room_state(room)

func broadcast_command_applied(room, cmd) -> void:
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
	var targets := Array(room.get_peer_ids())
	for pid in targets:
		_net.rpc_id(int(pid), "rpc_command_applied", payload)
	GameLog.debug(
		"NetClient",
		"TX CommandApplied %s state_hash=%s recipients=%d %s"
			% [_command_brief(cmd), _short_hash(state_hash), targets.size(), _room_brief(room)]
	)

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
