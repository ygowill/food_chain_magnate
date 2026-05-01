# Dedicated Server 入口（Headless）
extends Node

const DEFAULT_PORT := 7000
const DEFAULT_BIND_ADDRESS := "0.0.0.0"
const DEFAULT_PLATFORM_BACKEND_URL := "http://127.0.0.1:8000"
const DEFAULT_INTERNAL_API_SECRET := "dev-internal-secret-change-in-production"
const DEFAULT_ROOM_PERSIST_PATH := "user://dedicated_server/online_room_snapshots.json"
const DEFAULT_ROUND_AUTOSAVE_DIR := "user://dedicated_server/online_round_autosaves"
const DEFAULT_SERVER_IDENTITY_PATH := "user://dedicated_server/server_identity.cfg"
const HEARTBEAT_INTERVAL_SEC := 15.0
const PERSIST_INTERVAL_SEC := 2.0
const ROOM_DIRECTORY_SYNC_DEBOUNCE_SEC := 0.2

const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const MapSnapshotRendererClass = preload("res://server/map_snapshot_renderer.gd")
const RoomPersistenceStoreClass = preload("res://server/room_persistence_store.gd")
const ServerIdentityStoreClass = preload("res://server/server_identity_store.gd")

var _backend_url: String = ""
var _internal_api_secret: String = ""
var _game_server_id: String = ""
var _public_ws_url: String = ""
var _heartbeat_in_flight: bool = false
var _heartbeat_timer: Timer = null
var _room_persistence_store = null
var _persist_timer: Timer = null
var _server_identity_store = null
var _room_directory_sync_timer: Timer = null
var _room_directory_sync_in_flight: bool = false
var _room_directory_sync_pending: bool = false

func _ready() -> void:
	var port := DEFAULT_PORT
	var bind_address := DEFAULT_BIND_ADDRESS

	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := str(args[i])
		if a == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
		elif a.begins_with("--port="):
			port = int(a.split("=", false, 1)[1])
		elif a == "--bind" and i + 1 < args.size():
			bind_address = str(args[i + 1]).strip_edges()
		elif a.begins_with("--bind="):
			bind_address = str(a.split("=", false, 1)[1]).strip_edges()

	var r: Result = NetClient.start_server(port, bind_address)
	if not r.ok:
		GameLog.error("DedicatedServer", r.error)
		get_tree().quit(1)
		return

	var runtime_r: Result = _resolve_runtime_config(port, bind_address)
	if not runtime_r.ok:
		GameLog.error("DedicatedServer", runtime_r.error)
		get_tree().quit(1)
		return

	var persist_r: Result = await _setup_persistence()
	if not persist_r.ok:
		GameLog.error("DedicatedServer", persist_r.error)
		get_tree().quit(1)
		return

	_setup_room_directory_sync()
	_setup_heartbeat(port)
	GameLog.info("DedicatedServer", "Running. args=%s" % str(args))

func _exit_tree() -> void:
	_persist_rooms()

func _resolve_runtime_config(port: int, bind_address: String) -> Result:
	_backend_url = str(OS.get_environment("PLATFORM_BACKEND_URL")).strip_edges()
	if _backend_url.is_empty():
		_backend_url = DEFAULT_PLATFORM_BACKEND_URL
	_internal_api_secret = str(OS.get_environment("INTERNAL_API_SECRET")).strip_edges()
	if _internal_api_secret.is_empty():
		_internal_api_secret = DEFAULT_INTERNAL_API_SECRET

	var env_game_server_id := str(OS.get_environment("GAME_SERVER_ID")).strip_edges()
	if not env_game_server_id.is_empty():
		_game_server_id = env_game_server_id
	else:
		_server_identity_store = ServerIdentityStoreClass.new(DEFAULT_SERVER_IDENTITY_PATH)
		var identity_r: Result = _server_identity_store.load_or_create(port)
		if not identity_r.ok:
			return identity_r
		_game_server_id = str(Dictionary(identity_r.value).get("game_server_id", "")).strip_edges()
		if _game_server_id.is_empty():
			return Result.failure("加载 game_server_id 失败")

	_public_ws_url = _resolve_public_ws_url(port, bind_address)
	return Result.success()

func _setup_persistence() -> Result:
	var snapshot_path := str(OS.get_environment("FCM_ROOM_PERSIST_PATH")).strip_edges()
	if snapshot_path.is_empty():
		snapshot_path = DEFAULT_ROOM_PERSIST_PATH
	_room_persistence_store = RoomPersistenceStoreClass.new(snapshot_path)
	var round_autosave_dir := str(OS.get_environment("FCM_ROUND_AUTOSAVE_DIR")).strip_edges()
	if round_autosave_dir.is_empty():
		round_autosave_dir = DEFAULT_ROUND_AUTOSAVE_DIR
	if _room_persistence_store.has_method("set_round_autosave_dir"):
		_room_persistence_store.set_round_autosave_dir(round_autosave_dir)

	if NetClient == null or not NetClient.has_method("has_server_room_manager") or not NetClient.has_server_room_manager():
		return Result.failure("DedicatedServer persistence setup failed: RoomManager missing")

	var load_r: Result = _room_persistence_store.load_snapshot()
	if not load_r.ok:
		return Result.failure("加载房间快照失败: %s" % load_r.error)
	var snapshot: Dictionary = Dictionary(load_r.value)
	var sync_r: Result = await _sync_room_directory_snapshot(snapshot)
	if not sync_r.ok:
		GameLog.warn("DedicatedServer", "Sync room directory failed: %s" % sync_r.error)
	var restore_snapshot: Dictionary = snapshot
	if sync_r.value is Dictionary:
		restore_snapshot = Dictionary(sync_r.value)
	var restore_r: Result = NetClient.restore_server_room_manager_from_persistence(restore_snapshot)
	if not restore_r.ok:
		return Result.failure("恢复房间快照失败: %s" % restore_r.error)

	_persist_timer = Timer.new()
	_persist_timer.one_shot = false
	_persist_timer.wait_time = PERSIST_INTERVAL_SEC
	add_child(_persist_timer)
	_persist_timer.timeout.connect(_on_persist_timeout)
	_persist_timer.start()
	_setup_round_autosave()

	var restored_rooms := int(restore_r.value.get("restored_rooms", 0)) if restore_r.value is Dictionary else 0
	GameLog.info(
		"DedicatedServer",
		"Persistence enabled path=%s restored_rooms=%d interval=%.1fs"
			% [ProjectSettings.globalize_path(snapshot_path), restored_rooms, PERSIST_INTERVAL_SEC]
	)
	_persist_rooms()
	return Result.success()

func _setup_round_autosave() -> void:
	if NetClient == null or not is_instance_valid(NetClient):
		return
	if not NetClient.has_signal("server_round_autosave_requested"):
		return
	var cb := Callable(self, "_on_server_round_autosave_requested")
	if not NetClient.server_round_autosave_requested.is_connected(cb):
		NetClient.server_round_autosave_requested.connect(cb)

func _on_server_round_autosave_requested(room_code: String, completed_round_number: int, state_hash: String, snapshot_kind: String = "round_end") -> void:
	call_deferred("_persist_round_autosave", room_code, completed_round_number, state_hash, snapshot_kind)

func _persist_round_autosave(room_code: String, completed_round_number: int, state_hash: String, snapshot_kind: String = "round_end") -> void:
	if _room_persistence_store == null:
		return
	if NetClient == null or not NetClient.has_method("get_server_room_by_code"):
		return
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return
	var kind := _normalize_round_snapshot_kind(snapshot_kind)
	var room = NetClient.get_server_room_by_code(code)
	if room == null:
		GameLog.warn("DedicatedServer", "Round autosave skipped: room not found %s" % code)
		return
	if not room.has_method("build_full_authority_archive_export"):
		GameLog.warn("DedicatedServer", "Round autosave skipped: room export missing %s" % code)
		return
	var export_r: Result = room.build_full_authority_archive_export(kind == "game_over")
	if not export_r.ok:
		GameLog.warn("DedicatedServer", "Round autosave export failed room=%s err=%s" % [code, export_r.error])
		return
	var export_info: Dictionary = Dictionary(export_r.value) if export_r.value is Dictionary else {}
	var archive_val = export_info.get("archive", null)
	if not (archive_val is Dictionary):
		GameLog.warn("DedicatedServer", "Round autosave export returned invalid archive room=%s" % code)
		return
	var save_r: Result = _room_persistence_store.save_round_autosave_archive(
		code,
		Dictionary(archive_val).duplicate(true),
		int(completed_round_number),
		str(state_hash).strip_edges(),
		kind
	)
	if not save_r.ok:
		GameLog.warn("DedicatedServer", "Round autosave write failed room=%s err=%s" % [code, save_r.error])
		return
	var save_info: Dictionary = Dictionary(save_r.value).duplicate(true) if save_r.value is Dictionary else {}
	var map_snapshot_png := PackedByteArray()
	var state = room.game_engine.get_state()
	if state != null:
		var render_r: Result = MapSnapshotRendererClass.render_state_png(state)
		if render_r.ok and render_r.value is Dictionary:
			map_snapshot_png = PackedByteArray(Dictionary(render_r.value).get("png_bytes", PackedByteArray()))
			if not map_snapshot_png.is_empty() and _room_persistence_store.has_method("save_round_map_snapshot_png"):
				var png_save_r: Result = _room_persistence_store.save_round_map_snapshot_png(
					code,
					map_snapshot_png,
					int(completed_round_number),
					kind
				)
				if not png_save_r.ok:
					GameLog.warn("DedicatedServer", "Round map snapshot write failed room=%s err=%s" % [code, png_save_r.error])
		else:
			GameLog.warn("DedicatedServer", "Round map snapshot render failed room=%s err=%s" % [code, render_r.error])
	var upload_r: Result = await _upload_round_artifacts(
		code,
		int(completed_round_number),
		kind,
		str(state_hash).strip_edges(),
		str(save_info.get("json_text", "")),
		map_snapshot_png
	)
	if not upload_r.ok:
		GameLog.warn("DedicatedServer", "Round artifacts upload failed room=%s err=%s" % [code, upload_r.error])
	GameLog.info(
		"DedicatedServer",
		"Round autosave saved room=%s completed_round=%d kind=%s path=%s bytes=%d snapshot_bytes=%d"
			% [
				code,
				int(completed_round_number),
				kind,
				str(save_info.get("path", "")),
				int(save_info.get("json_bytes", 0)),
				map_snapshot_png.size(),
			]
	)
	_persist_rooms()

func _upload_round_artifacts(
	room_code: String,
	completed_round_number: int,
	snapshot_kind: String,
	state_hash: String,
	archive_json: String,
	map_snapshot_png: PackedByteArray
) -> Result:
	if _backend_url.is_empty() or _internal_api_secret.is_empty():
		return Result.failure("round artifacts upload missing backend/internal secret")

	var body_dict: Dictionary = {
		"room_code": str(room_code).strip_edges().to_upper(),
		"round_number": int(completed_round_number),
		"snapshot_kind": _normalize_round_snapshot_kind(snapshot_kind),
		"state_hash": str(state_hash).strip_edges(),
	}
	var archive_text := str(archive_json)
	if not archive_text.strip_edges().is_empty():
		var archive_bytes := archive_text.to_utf8_buffer()
		body_dict["archive_json"] = archive_text
		body_dict["archive_checksum"] = _sha256_hex(archive_bytes)
		body_dict["archive_size_bytes"] = archive_bytes.size()
	if not map_snapshot_png.is_empty():
		body_dict["map_snapshot_png_base64"] = Marshalls.raw_to_base64(map_snapshot_png)
		body_dict["map_snapshot_checksum"] = _sha256_hex(map_snapshot_png)
		body_dict["map_snapshot_size_bytes"] = map_snapshot_png.size()
	if not body_dict.has("archive_json") and not body_dict.has("map_snapshot_png_base64"):
		return Result.failure("round artifacts upload payload empty")

	var base := str(_backend_url)
	if base.ends_with("/"):
		base = base.trim_suffix("/")
	var url := base + "/internal/matches/round_artifacts"
	var headers := [
		"Content-Type: application/json",
		"X-Internal-Secret: " + _internal_api_secret,
	]
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body_dict))
	if err != OK:
		http.queue_free()
		return Result.failure("round artifacts upload request_failed err=%s url=%s" % [str(err), url])
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = int(result[1]) if result.size() > 1 else 0
	if response_code < 200 or response_code >= 300:
		var response_body := PackedByteArray(result[3]).get_string_from_utf8() if result.size() > 3 else ""
		return Result.failure("round artifacts upload failed status=%d body=%s" % [response_code, _safe_log_text(response_body, 240)])
	return Result.success()

func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

func _normalize_round_snapshot_kind(snapshot_kind: String) -> String:
	var kind := str(snapshot_kind).strip_edges()
	if kind == "game_over":
		return "game_over"
	return "round_end"

func _safe_log_text(text: String, max_len: int) -> String:
	var t := str(text).strip_edges()
	if t.length() <= max_len:
		return t
	return t.substr(0, max_len) + "..."

func _sync_room_directory_snapshot(snapshot: Dictionary) -> Result:
	if _backend_url.is_empty() or _internal_api_secret.is_empty() or _game_server_id.is_empty():
		return Result.failure("room directory sync missing backend/internal/game_server_id")

	var base := str(_backend_url)
	if base.ends_with("/"):
		base = base.trim_suffix("/")
	var url := base + "/internal/game_servers/%s/rooms/sync" % _game_server_id.uri_encode()
	var headers := [
		"Content-Type: application/json",
		"X-Internal-Secret: " + _internal_api_secret,
	]
	var rooms_payload: Array[Dictionary] = []
	var rooms_val = snapshot.get("rooms", null)
	if rooms_val is Array:
		for item in Array(rooms_val):
			if not (item is Dictionary):
				continue
			var room: Dictionary = Dictionary(item)
			var members: Array[Dictionary] = []
			var host_seat_index := int(room.get("host_seat_index", -1))
			var seat_slots_val = room.get("seat_slots", null)
			if seat_slots_val is Dictionary:
				var seat_slots: Dictionary = Dictionary(seat_slots_val)
				var seat_keys: Array[int] = []
				for seat_key in seat_slots.keys():
					seat_keys.append(int(seat_key))
				seat_keys.sort()
				for seat_index in seat_keys:
					var slot_val = seat_slots.get(seat_index, seat_slots.get(str(seat_index), null))
					if not (slot_val is Dictionary):
						continue
					var slot: Dictionary = Dictionary(slot_val)
					var user_id := str(slot.get("user_id", "")).strip_edges()
					if user_id.is_empty():
						continue
					var member_status := "active"
					var seat_state := str(slot.get("seat_state", "")).strip_edges()
					if seat_state == "RECONNECTING":
						member_status = "reconnecting"
					elif seat_state == "FORFEITED":
						member_status = "forfeited"
					members.append({
						"user_id": user_id,
						"role": str(slot.get("role", "player")).strip_edges(),
						"seat_index": seat_index,
						"member_status": member_status,
						"generation": int(slot.get("generation", 1)),
					})
			else:
				var user_ids_by_seat_val = room.get("user_ids_by_seat", null)
				var user_ids_by_seat: Dictionary = Dictionary(user_ids_by_seat_val) if user_ids_by_seat_val is Dictionary else {}
				var seat_keys: Array[int] = []
				for seat_key in user_ids_by_seat.keys():
					seat_keys.append(int(seat_key))
				seat_keys.sort()
				for seat_index in seat_keys:
					var user_id := str(user_ids_by_seat.get(seat_index, "")).strip_edges()
					if user_id.is_empty():
						continue
					members.append({
						"user_id": user_id,
						"role": "host" if seat_index == host_seat_index else "player",
						"seat_index": seat_index,
						"member_status": "active",
						"generation": 1,
					})
			var waiting_members_val = room.get("waiting_members", null)
			if waiting_members_val is Array:
				for waiting_member_val in Array(waiting_members_val):
					if not (waiting_member_val is Dictionary):
						continue
					var waiting_member: Dictionary = Dictionary(waiting_member_val)
					var waiting_user_id := str(waiting_member.get("user_id", "")).strip_edges()
					if waiting_user_id.is_empty():
						continue
					members.append({
						"user_id": waiting_user_id,
						"role": str(waiting_member.get("role", "player")).strip_edges(),
						"seat_index": null,
						"member_status": str(waiting_member.get("member_status", "active")).strip_edges(),
						"generation": int(waiting_member.get("generation", 1)),
					})
			var spectators_val = room.get("spectators", null)
			if spectators_val is Array:
				for spectator_val in Array(spectators_val):
					if not (spectator_val is Dictionary):
						continue
					var spectator: Dictionary = Dictionary(spectator_val)
					var spectator_user_id := str(spectator.get("user_id", "")).strip_edges()
					if spectator_user_id.is_empty():
						continue
					members.append({
						"user_id": spectator_user_id,
						"role": "spectator",
						"seat_index": null,
						"member_status": str(spectator.get("member_status", "active")).strip_edges(),
						"generation": 1,
					})
			var owner_user_id := str(room.get("owner_user_id", "")).strip_edges()
			if owner_user_id.is_empty():
				for member in members:
					if str(member.get("role", "")).strip_edges() == "host":
						owner_user_id = str(member.get("user_id", "")).strip_edges()
						break
			if owner_user_id.is_empty():
				for member in members:
					if int(member.get("seat_index", -1)) == host_seat_index:
						owner_user_id = str(member.get("user_id", "")).strip_edges()
						break
			if owner_user_id.is_empty() and not members.is_empty():
				owner_user_id = str(members[0].get("user_id", "")).strip_edges()
			rooms_payload.append({
				"room_code": str(room.get("room_code", "")).strip_edges().to_upper(),
				"owner_user_id": owner_user_id,
				"status": str(room.get("runtime_status", room.get("status", "Lobby"))).strip_edges(),
				"join_policy": str(room.get("join_policy", "public")).strip_edges(),
				"password_hash": str(room.get("password_hash", "")).strip_edges(),
				"config_json": JSON.stringify(Dictionary(room.get("config", {})).duplicate(true)),
				"ws_url": _public_ws_url,
				"members": members,
			})
	var body := JSON.stringify({
		"ws_url": _public_ws_url,
		"rooms": rooms_payload,
	})

	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return Result.failure("room directory sync request_failed err=%s url=%s" % [str(err), url])
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = int(result[1]) if result.size() > 1 else 0
	if response_code < 200 or response_code >= 300:
		return Result.failure("room directory sync failed status=%d url=%s" % [response_code, url])
	var body_text := PackedByteArray(result[3]).get_string_from_utf8() if result.size() > 3 else ""
	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		return Result.success(snapshot)
	var response_dict: Dictionary = Dictionary(parsed)
	var skipped_val: Variant = response_dict.get("skipped_ended_room_codes", null)
	if skipped_val is Array:
		_prune_remote_ended_rooms(Array(skipped_val), "room_directory_sync")
	var accepted_val: Variant = response_dict.get("accepted_room_codes", null)
	if not (accepted_val is Array):
		return Result.success(snapshot)
	return Result.success(_filter_snapshot_by_room_codes(snapshot, Array(accepted_val)))

func _prune_remote_ended_rooms(room_codes: Array, source: String) -> void:
	if room_codes.is_empty():
		return
	if NetClient == null or not is_instance_valid(NetClient):
		return
	if not NetClient.has_method("force_remove_server_room"):
		return

	var removed_codes: Array[String] = []
	var notified_peer_ids: Array[int] = []
	for code_val in room_codes:
		var code := str(code_val).strip_edges().to_upper()
		if code.is_empty():
			continue
		var remove_r: Result = NetClient.force_remove_server_room(code)
		if not remove_r.ok:
			GameLog.warn("DedicatedServer", "Prune remote-ended room failed code=%s source=%s error=%s" % [code, source, remove_r.error])
			continue
		var remove_info: Dictionary = Dictionary(remove_r.value) if remove_r.value is Dictionary else {}
		if not bool(remove_info.get("removed", false)):
			continue
		removed_codes.append(code)
		var peer_ids_val: Variant = remove_info.get("peer_ids", [])
		if peer_ids_val is Array:
			for peer_val in Array(peer_ids_val):
				var peer_id := int(peer_val)
				if peer_id <= 0:
					continue
				if not notified_peer_ids.has(peer_id):
					notified_peer_ids.append(peer_id)
				NetClient.rpc_id(peer_id, "rpc_room_state", NetClient.build_empty_room_state())

	if removed_codes.is_empty():
		return
	NetClient.broadcast_server_room_list("")
	_persist_rooms()
	GameLog.info(
		"DedicatedServer",
		"Pruned remote-ended rooms source=%s rooms=%s notified_peers=%d"
			% [source, ",".join(removed_codes), notified_peer_ids.size()]
	)

func _setup_room_directory_sync() -> void:
	if _room_directory_sync_timer == null or not is_instance_valid(_room_directory_sync_timer):
		_room_directory_sync_timer = Timer.new()
		_room_directory_sync_timer.one_shot = true
		_room_directory_sync_timer.wait_time = ROOM_DIRECTORY_SYNC_DEBOUNCE_SEC
		add_child(_room_directory_sync_timer)
		_room_directory_sync_timer.timeout.connect(_on_room_directory_sync_timeout)

	if NetClient == null or not is_instance_valid(NetClient):
		return
	var cb := Callable(self, "_on_room_directory_dirty")
	if not NetClient.server_room_directory_dirty.is_connected(cb):
		NetClient.server_room_directory_dirty.connect(cb)

func _on_room_directory_dirty() -> void:
	_request_room_directory_sync()

func _request_room_directory_sync() -> void:
	if _room_directory_sync_in_flight:
		_room_directory_sync_pending = true
		return
	if _room_directory_sync_timer == null or not is_instance_valid(_room_directory_sync_timer):
		return
	if _room_directory_sync_timer.is_stopped():
		_room_directory_sync_timer.start()

func _on_room_directory_sync_timeout() -> void:
	await _flush_room_directory_sync()

func _flush_room_directory_sync() -> void:
	if _room_directory_sync_in_flight:
		_room_directory_sync_pending = true
		return
	if NetClient == null or not NetClient.has_method("create_server_room_persistence_snapshot"):
		return

	var snapshot_r: Result = NetClient.create_server_room_persistence_snapshot(true)
	if not snapshot_r.ok:
		GameLog.warn("DedicatedServer", "Create room directory snapshot failed: %s" % snapshot_r.error)
		return

	_room_directory_sync_in_flight = true
	var sync_r: Result = await _sync_room_directory_snapshot(Dictionary(snapshot_r.value))
	_room_directory_sync_in_flight = false
	if not sync_r.ok:
		GameLog.warn("DedicatedServer", "Immediate room directory sync failed: %s" % sync_r.error)

	if _room_directory_sync_pending:
		_room_directory_sync_pending = false
		if _room_directory_sync_timer != null and is_instance_valid(_room_directory_sync_timer):
			_room_directory_sync_timer.start()

func _filter_snapshot_by_room_codes(snapshot: Dictionary, accepted_room_codes: Array) -> Dictionary:
	var allowed_lookup: Dictionary = {}
	for code_val in accepted_room_codes:
		var code := str(code_val).strip_edges().to_upper()
		if code.is_empty():
			continue
		allowed_lookup[code] = true

	var out: Dictionary = snapshot.duplicate(true)
	var filtered_rooms: Array[Dictionary] = []
	var rooms_val = out.get("rooms", null)
	if rooms_val is Array:
		for item in Array(rooms_val):
			if not (item is Dictionary):
				continue
			var room: Dictionary = Dictionary(item)
			var room_code := str(room.get("room_code", "")).strip_edges().to_upper()
			if room_code.is_empty():
				continue
			if not allowed_lookup.has(room_code):
				continue
			filtered_rooms.append(room.duplicate(true))
	out["rooms"] = filtered_rooms
	return out

func _on_persist_timeout() -> void:
	_persist_rooms()

func _persist_rooms() -> void:
	if _room_persistence_store == null:
		return
	if NetClient == null or not NetClient.has_method("save_server_room_manager_with_store"):
		return
	var span := OnlinePerfTraceClass.begin_span("server.persistence.persist_rooms", {
		"room_count": int(NetClient.get_server_room_count()) if NetClient.has_method("get_server_room_count") else 0,
		"snapshot_path": _room_persistence_store.get_snapshot_path() if _room_persistence_store.has_method("get_snapshot_path") else "",
	})
	var save_r: Result = NetClient.save_server_room_manager_with_store(_room_persistence_store)
	if not save_r.ok:
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"error": str(save_r.error),
		})
		GameLog.warn("DedicatedServer", "Persist rooms failed: %s" % save_r.error)
		return
	var save_info: Dictionary = Dictionary(save_r.value).duplicate(true) if save_r.value is Dictionary else {}
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"room_count": int(save_info.get("room_count", 0)),
		"json_bytes": int(save_info.get("json_bytes", 0)),
		"path": str(save_info.get("path", "")),
	})

func _setup_heartbeat(_port: int) -> void:
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL_SEC
	add_child(_heartbeat_timer)
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	_heartbeat_timer.start()

	GameLog.info(
		"DedicatedServer",
		"Heartbeat enabled backend=%s game_server_id=%s interval=%.1fs"
			% [_backend_url, _game_server_id, HEARTBEAT_INTERVAL_SEC]
	)
	_send_heartbeat()

func _resolve_public_ws_url(port: int, bind_address: String) -> String:
	var env_ws_url := str(OS.get_environment("GAME_SERVER_WS_URL")).strip_edges()
	if not env_ws_url.is_empty():
		return env_ws_url
	var host := str(bind_address).strip_edges()
	if host.is_empty() or host == "0.0.0.0" or host == "::" or host == "*":
		host = "127.0.0.1"
	return "ws://%s:%d" % [host, int(port)]

func _on_heartbeat_timeout() -> void:
	_send_heartbeat()

func _send_heartbeat() -> void:
	if _heartbeat_in_flight:
		return
	if _backend_url.is_empty() or _internal_api_secret.is_empty() or _game_server_id.is_empty():
		return

	var room_codes: Array[String] = []
	if NetClient != null and NetClient.has_method("list_active_server_room_codes"):
		room_codes = NetClient.list_active_server_room_codes()

	var base := str(_backend_url)
	if base.ends_with("/"):
		base = base.trim_suffix("/")
	var url := base + "/internal/game_servers/heartbeat"
	var body := JSON.stringify({
		"game_server_id": _game_server_id,
		"ws_url": _public_ws_url,
		"room_codes": room_codes,
	})
	var headers := [
		"Content-Type: application/json",
		"X-Internal-Secret: " + _internal_api_secret,
	]

	_heartbeat_in_flight = true
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		_heartbeat_in_flight = false
		if not room_codes.is_empty():
			GameLog.warn("DedicatedServer", "Heartbeat request_failed err=%s url=%s" % [str(err), url])
		return
	var result: Array = await http.request_completed
	http.queue_free()
	_heartbeat_in_flight = false

	var response_code: int = result[1]
	if response_code < 200 or response_code >= 300:
		if not room_codes.is_empty():
			GameLog.warn("DedicatedServer", "Heartbeat failed status=%d url=%s" % [response_code, url])
		return

	var body_text := PackedByteArray(result[3]).get_string_from_utf8() if result.size() > 3 else ""
	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		return
	var ended_val: Variant = Dictionary(parsed).get("ended_room_codes", null)
	if ended_val is Array:
		_prune_remote_ended_rooms(Array(ended_val), "heartbeat")
