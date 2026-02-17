# NetClient：Client-only 逻辑（连接回调 + ClientHello）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

var _net = null

func setup(net_client) -> void:
	_net = net_client

func on_connected_to_server() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = true
	send_client_hello()
	_net.connected.emit()

func on_connection_failed() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = false
	_net.disconnected.emit("connection_failed")
	_net.shutdown()

func on_server_disconnected() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	_net._client_transport_connected = false
	_net.disconnected.emit("server_disconnected")
	_net.shutdown()

func send_client_hello() -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var request_id: String = _net._next_request_id()
	var payload := {
		"request_id": request_id,
		"protocol_version": NetContext.PROTOCOL_VERSION,
		"game_version": Globals.get_version(),
		"schema_version": Globals.SCHEMA_VERSION,
		"player_profile": NetContext.player_profile.duplicate(true),
	}
	_net.rpc_id(1, "rpc_client_hello", payload)

func handle_rpc_room_state(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	NetContext.room_state = payload.duplicate(true)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state)
	_net.room_state_updated.emit(NetContext.room_state)

func handle_rpc_room_list(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var rooms_val = payload.get("rooms", null)
	if not (rooms_val is Array):
		return
	NetContext.room_list = Array(rooms_val).duplicate(true)
	_net.room_list_updated.emit(NetContext.room_list.duplicate(true))

func handle_rpc_game_started(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var mapping_val = payload.get("player_id_by_peer_id", null)
	if not (mapping_val is Dictionary):
		return
	var cfg_val = payload.get("config", null)
	if not (cfg_val is Dictionary):
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
		GameLog.error("NetClient", "Online client engine initialize failed: %s" % init_r.error)
		return

	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state if NetContext != null else {})

	_net.game_started.emit(payload.duplicate(true))

func handle_rpc_command_applied(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var cmd_dict_val = payload.get("cmd", null)
	if not (cmd_dict_val is Dictionary):
		return
	var state_hash := str(payload.get("state_hash", ""))
	_net.command_applied.emit(Dictionary(cmd_dict_val), state_hash)

func handle_rpc_resync_archive(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var archive_val = payload.get("archive", null)
	if not (archive_val is Dictionary):
		return
	_net._pending_resync_archive = Dictionary(archive_val).duplicate(true)
	_net.resync_archive_received.emit(Dictionary(_net._pending_resync_archive).duplicate(true))

func handle_rpc_request_rejected(payload: Dictionary) -> void:
	var request_id := str(payload.get("request_id", ""))
	var code := str(payload.get("code", ""))
	var message := str(payload.get("message", ""))
	_net.request_rejected.emit(request_id, code, message)
