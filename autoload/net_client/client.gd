# NetClient：Client-only 逻辑（连接回调 + ClientHello）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：RoomState/RoomList/CommandApplied 等高频收包走 DEBUG。
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

var _net = null

func setup(net_client) -> void:
	_net = net_client

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
	_net.shutdown()

func on_server_disconnected() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = false
	GameLog.warn("NetClient", "Server disconnected url=%s" % _safe_text(str(NetContext.server_url)))
	_net.disconnected.emit("server_disconnected")
	_net.shutdown()

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
	NetContext.room_state = payload.duplicate(true)
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
	if mapping.has(my_peer_id):
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

	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()

	var player_count := int(config.get("desired_player_count", 0))
	var seed := int(config.get("seed", 0))
	var base_dir := str(config.get("modules_v2_base_dir", "")).strip_edges()
	var base_dirs_read := ModuleDirSpecClass.parse_base_dirs(base_dir)
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

	var engine = GameEngineClass.new()
	var init_r = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
	if not init_r.ok:
		GameLog.error(
			"NetClient",
			"Online client engine initialize failed players=%d seed=%d modules=%d base_dir=%s err=%s"
				% [player_count, seed, enabled_modules.size(), base_dir, init_r.error]
		)
		return
	var state = engine.get_state()
	if state != null:
		if not (state.round_state is Dictionary):
			state.round_state = {}
		state.round_state[ONLINE_DINNERTIME_CONFIRM_KEY] = true

	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state if NetContext != null else {})
	GameLog.info(
		"NetClient",
		"Online client engine ready players=%d seed=%d modules=%d base_dir=%s"
			% [player_count, seed, enabled_modules.size(), base_dir]
	)

	_net.game_started.emit(payload.duplicate(true))

func handle_rpc_command_applied(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var cmd_dict_val = payload.get("cmd", null)
	if not (cmd_dict_val is Dictionary):
		GameLog.warn("NetClient", "RX CommandApplied ignored: cmd type invalid")
		return
	var cmd_dict: Dictionary = Dictionary(cmd_dict_val)
	var state_hash := str(payload.get("state_hash", ""))
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
	_net._pending_resync_archive = Dictionary(archive_val).duplicate(true)
	if _net._pending_resync_archive.has("_rewind_to_turn_start"):
		var meta_val = _net._pending_resync_archive.get("_rewind_to_turn_start", null)
		var meta: Dictionary = Dictionary(meta_val) if meta_val is Dictionary else {}
		GameLog.warn(
			"NetClient",
			"RX RewindMeta request_id=%s target=%d before=%d history=%d noop=%s state_hash=%s"
				% [
					_safe_text(str(meta.get("request_id", ""))),
					int(meta.get("target_index", -1)),
					int(meta.get("before_index", -1)),
					int(meta.get("history_size", -1)),
					str(bool(meta.get("noop", false))),
					_short_hash(str(meta.get("state_hash", "")))
				]
		)
	else:
		GameLog.warn(
			"NetClient",
			"RX ResyncArchive snapshot keys=%s" % str(Array(_net._pending_resync_archive.keys()))
		)
	_net.resync_archive_received.emit(Dictionary(_net._pending_resync_archive).duplicate(true))

func handle_rpc_request_rejected(payload: Dictionary) -> void:
	var request_id := str(payload.get("request_id", ""))
	var code := str(payload.get("code", ""))
	var message := str(payload.get("message", ""))
	GameLog.warn(
		"NetClient",
		"RX RequestRejected request_id=%s code=%s message=%s"
			% [_safe_text(request_id), _safe_text(code), _safe_text(message)]
	)
	_net.request_rejected.emit(request_id, code, message)

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
