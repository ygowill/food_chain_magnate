# NetClient：Client-only 逻辑（连接回调 + ClientHello）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：RoomState/RoomList/CommandApplied 等高频收包走 DEBUG。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")
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
		if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
			NetContext.sync_online_resume_progress_from_engine(Globals.current_game_engine)
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
	NetContext.room_state = payload.duplicate(true)
	var self_seat_val = NetContext.room_state.get("self_seat_index", null)
	if self_seat_val is int or self_seat_val is float:
		NetContext.local_player_id = int(self_seat_val)
	var self_role := str(NetContext.room_state.get("self_role", "")).strip_edges()
	NetContext.local_role = self_role
	if str(NetContext.room_state.get("status", "")).strip_edges() != "InGame":
		_set_online_client_engine_room_code("")
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
	var existing_engine: GameEngine = _try_reuse_existing_online_client_engine(room_code, local_pid)
	if existing_engine != null:
		_net.game_started.emit(payload.duplicate(true))
		_try_apply_pending_resync_delta()
		return

	var init_r: Result = _initialize_online_client_engine_from_config(config, room_code, local_pid)
	if not init_r.ok:
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
	_set_pending_resync_archive(Dictionary(archive_val))
	var pending_archive := _get_pending_resync_archive()
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
	var rewind_meta := Dictionary(payload).duplicate(true)
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
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var manifest: Dictionary = Dictionary(payload).duplicate(true)
	if not _matches_payload_room_code(manifest, "ResyncSnapshot manifest"):
		return
	var transfer_id := str(manifest.get("transfer_id", "")).strip_edges()
	var chunk_count := int(manifest.get("chunk_count", 0))
	if transfer_id.is_empty() or chunk_count <= 0:
		GameLog.warn("NetClient", "RX ResyncSnapshot manifest ignored: invalid manifest")
		return
	_set_pending_resync_snapshot_manifest(manifest)
	_set_pending_resync_snapshot_chunks({})
	GameLog.warn(
		"NetClient",
		"RX ResyncSnapshot manifest request_id=%s transfer_id=%s chunks=%d total_bytes=%d"
			% [
				_safe_text(str(manifest.get("request_id", ""))),
				_safe_text(transfer_id),
				chunk_count,
				int(manifest.get("total_bytes", -1)),
			]
	)

func handle_rpc_resync_snapshot_chunk(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var manifest := _get_pending_resync_snapshot_manifest()
	if manifest.is_empty():
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: manifest missing")
		return
	var transfer_id := str(payload.get("transfer_id", "")).strip_edges()
	if transfer_id != str(manifest.get("transfer_id", "")).strip_edges():
		GameLog.warn(
			"NetClient",
			"RX ResyncSnapshot chunk ignored: transfer mismatch current=%s incoming=%s"
				% [_safe_text(str(manifest.get("transfer_id", ""))), _safe_text(transfer_id)]
		)
		return
	var chunk_index := int(payload.get("chunk_index", -1))
	var chunk_count := int(manifest.get("chunk_count", 0))
	if chunk_index < 0 or chunk_index >= chunk_count:
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: index invalid=%d" % chunk_index)
		return
	var bytes_val = payload.get("bytes", null)
	if not (bytes_val is PackedByteArray):
		GameLog.warn("NetClient", "RX ResyncSnapshot chunk ignored: bytes invalid index=%d" % chunk_index)
		return
	var chunks := _get_pending_resync_snapshot_chunks()
	var chunk_bytes: PackedByteArray = bytes_val
	chunks[chunk_index] = chunk_bytes
	_set_pending_resync_snapshot_chunks(chunks)
	if chunks.size() < chunk_count:
		return

	var assemble_r: Result = ResyncSnapshotTransferClass.assemble_snapshot(manifest, chunks)
	_clear_pending_resync_snapshot_state()
	if not assemble_r.ok:
		GameLog.error("NetClient", "ResyncSnapshot assemble failed: %s" % assemble_r.error)
		return
	var archive: Dictionary = Dictionary(assemble_r.value).duplicate(true)
	_set_pending_resync_archive(archive)
	_try_bootstrap_online_client_engine_from_archive(archive)
	GameLog.warn(
		"NetClient",
		"RX ResyncSnapshot assembled transfer_id=%s chunks=%d total_bytes=%d"
			% [
				_safe_text(transfer_id),
				chunk_count,
				int(manifest.get("total_bytes", -1)),
			]
	)
	_net.resync_archive_received.emit(archive.duplicate(true))

func handle_rpc_resync_delta(payload: Dictionary) -> void:
	if NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return
	var delta_payload: Dictionary = Dictionary(payload).duplicate(true)
	if not _matches_payload_room_code(delta_payload, "ResyncDelta"):
		return
	if _get_active_resume_engine() == null:
		_set_pending_resync_delta(delta_payload)
		GameLog.warn(
			"NetClient",
			"RX ResyncDelta buffered from=%d to=%d entries=%d"
				% [
					int(delta_payload.get("from_sequence", -1)),
					int(delta_payload.get("to_sequence", -1)),
					Array(delta_payload.get("entries", [])).size()
				]
		)
		return
	_apply_resync_delta(delta_payload)

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
	if _net == null or not is_instance_valid(_net):
		return
	var pending_delta := _get_pending_resync_delta()
	if pending_delta.is_empty():
		return
	var engine = _get_active_resume_engine()
	if engine == null:
		return
	var payload: Dictionary = pending_delta.duplicate(true)
	_set_pending_resync_delta({})
	_apply_resync_delta(payload)

func _get_pending_resync_delta() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var pending_val = (_net as Object).get("_pending_resync_delta")
	if pending_val is Dictionary:
		return Dictionary(pending_val)
	return {}

func _set_pending_resync_delta(payload: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_delta", Dictionary(payload).duplicate(true))

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

	var engine = GameEngineClass.new()
	var config_overrides_val = config.get("game_config_overrides", null)
	if config_overrides_val is Dictionary:
		engine.set_game_config_overrides(Dictionary(config_overrides_val).duplicate(true))
	var option_overrides_val = config.get("game_option_overrides", null)
	if option_overrides_val is Dictionary:
		engine.set_game_option_overrides(Dictionary(option_overrides_val).duplicate(true))
	var init_r = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
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
	var load_r: Result = engine.load_from_archive(archive)
	if not load_r.ok:
		GameLog.error("NetClient", "Online client archive bootstrap failed: %s" % load_r.error)
		return
	_mark_online_client_engine_ready(engine, room_code, local_pid)
	GameLog.info(
		"NetClient",
		"Online client engine bootstrapped from archive room=%s commands=%d"
			% [_safe_text(room_code), int(engine.command_history.size())]
	)

func _mark_online_client_engine_ready(engine: GameEngine, room_code: String, local_pid: int) -> void:
	if engine == null or engine.get_state() == null:
		return
	var state = engine.get_state()
	if not (state.rules is Dictionary):
		state.rules = {}
	state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
	if local_pid >= -1:
		NetContext.local_player_id = int(local_pid)
	Globals.set_current_game_engine(engine)
	Globals.sync_runtime_config_from_engine(engine)
	if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
		NetContext.sync_online_resume_progress_from_engine(engine)
	if Globals != null and Globals.has_method("apply_online_room_state"):
		Globals.apply_online_room_state(NetContext.room_state if NetContext != null else {})
	_set_online_client_engine_room_code(room_code)

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

func _get_pending_resync_archive() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var archive_val = (_net as Object).get("_pending_resync_archive")
	if archive_val is Dictionary:
		return Dictionary(archive_val)
	return {}

func _set_pending_resync_archive(archive: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_archive", Dictionary(archive).duplicate(true))

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

func _get_pending_resync_snapshot_manifest() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var manifest_val = (_net as Object).get("_pending_resync_snapshot_manifest")
	if manifest_val is Dictionary:
		return Dictionary(manifest_val)
	return {}

func _set_pending_resync_snapshot_manifest(manifest: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_snapshot_manifest", Dictionary(manifest).duplicate(true))

func _get_pending_resync_snapshot_chunks() -> Dictionary:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return {}
	var chunks_val = (_net as Object).get("_pending_resync_snapshot_chunks")
	if chunks_val is Dictionary:
		return Dictionary(chunks_val)
	return {}

func _set_pending_resync_snapshot_chunks(chunks: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net) or not (_net is Object):
		return
	(_net as Object).set("_pending_resync_snapshot_chunks", Dictionary(chunks).duplicate(true))

func _clear_pending_resync_snapshot_state() -> void:
	_set_pending_resync_snapshot_manifest({})
	_set_pending_resync_snapshot_chunks({})

func _apply_resync_delta(payload: Dictionary) -> void:
	var engine = _get_active_resume_engine()
	if engine == null:
		_emit_resync_delta_failure("delta 恢复失败：当前没有可恢复的 engine")
		return
	var entries_val = payload.get("entries", null)
	if not (entries_val is Array):
		_emit_resync_delta_failure("delta 恢复失败：entries 类型错误")
		return

	var from_sequence := int(payload.get("from_sequence", -1))
	var final_sequence := int(payload.get("final_sequence", payload.get("to_sequence", -1)))
	var final_hash := str(payload.get("final_hash", "")).strip_edges()
	var checkpoint_id := str(payload.get("checkpoint_id", "")).strip_edges()
	var entries: Array = Array(entries_val)
	var current_sequence: int = int(engine.command_history.size())
	var state = engine.get_state()
	var current_hash := str(state.compute_hash()) if state != null and state.has_method("compute_hash") else ""

	if current_sequence != from_sequence:
		if current_sequence == final_sequence and not final_hash.is_empty() and current_hash == final_hash:
			if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
				NetContext.sync_online_resume_progress_from_engine(engine, checkpoint_id)
			_net.resync_delta_applied.emit({
				"from_sequence": from_sequence,
				"final_sequence": final_sequence,
				"final_hash": final_hash,
				"entry_count": entries.size(),
				"checkpoint_id": checkpoint_id,
			})
			return
		_emit_resync_delta_failure(
			"delta 恢复失败：本地序列与服务端基线不一致（local=%d server=%d）"
				% [current_sequence, from_sequence]
		)
		return

	for item in entries:
		if not (item is Dictionary):
			_emit_resync_delta_failure("delta 恢复失败：entry 类型错误")
			return
		var entry: Dictionary = Dictionary(item)
		var expected_sequence: int = current_sequence + 1
		var entry_sequence := int(entry.get("sequence", -1))
		if entry_sequence != expected_sequence:
			_emit_resync_delta_failure(
				"delta 恢复失败：序列不连续（expected=%d actual=%d）"
					% [expected_sequence, entry_sequence]
			)
			return
		var cmd_val = entry.get("cmd", null)
		if not (cmd_val is Dictionary):
			_emit_resync_delta_failure("delta 恢复失败：cmd 类型错误")
			return
		var parsed: Result = CommandClass.from_dict(Dictionary(cmd_val))
		if not parsed.ok:
			_emit_resync_delta_failure("delta 恢复失败：命令解析失败：%s" % parsed.error)
			return
		var cmd: Command = parsed.value
		if int(cmd.index) != current_sequence:
			_emit_resync_delta_failure(
				"delta 恢复失败：cmd.index 不匹配（expected=%d actual=%d）"
					% [current_sequence, int(cmd.index)]
			)
			return
		var exec_r: Result = engine.execute_command(cmd, true)
		if not exec_r.ok:
			_emit_resync_delta_failure("delta 恢复失败：命令回放失败：%s" % exec_r.error)
			return
		current_sequence = engine.command_history.size()
		state = engine.get_state()
		current_hash = str(state.compute_hash()) if state != null and state.has_method("compute_hash") else ""
		var entry_hash := str(entry.get("post_state_hash", "")).strip_edges()
		if not entry_hash.is_empty() and current_hash != entry_hash:
			_emit_resync_delta_failure(
				"delta 恢复失败：state_hash 不匹配（local=%s server=%s）"
					% [_short_hash(current_hash), _short_hash(entry_hash)]
			)
			return

	if final_sequence >= 0 and current_sequence != final_sequence:
		_emit_resync_delta_failure(
			"delta 恢复失败：最终序列不匹配（local=%d server=%d）"
				% [current_sequence, final_sequence]
		)
		return
	if not final_hash.is_empty() and current_hash != final_hash:
		_emit_resync_delta_failure(
			"delta 恢复失败：最终 hash 不匹配（local=%s server=%s）"
				% [_short_hash(current_hash), _short_hash(final_hash)]
		)
		return

	if NetContext != null and NetContext.has_method("sync_online_resume_progress_from_engine"):
		NetContext.sync_online_resume_progress_from_engine(engine, checkpoint_id)
	GameLog.warn(
		"NetClient",
		"RX ResyncDelta applied from=%d to=%d entries=%d final_hash=%s"
			% [from_sequence, current_sequence, entries.size(), _short_hash(current_hash)]
	)
	_net.resync_delta_applied.emit({
		"from_sequence": from_sequence,
		"final_sequence": current_sequence,
		"final_hash": current_hash,
		"entry_count": entries.size(),
		"checkpoint_id": checkpoint_id,
	})

func _emit_resync_delta_failure(message: String) -> void:
	if _net != null and is_instance_valid(_net):
		if _net.has_method("request_resume_force_snapshot_once"):
			_net.request_resume_force_snapshot_once()
		_net.resync_delta_failed.emit(str(message))
	GameLog.warn("NetClient", str(message))

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
