# NetClient：Server-only 逻辑（room 管理 + 广播 + forfeit 自动推进）
# 注意：不要在这里新增任何 @rpc 方法，以避免联机双方脚本 RPC 校验不一致。
# 日志分级：广播与逐命令同步等热路径走 DEBUG，异常/回灌/拒绝请求保留 WARN/ERROR。
extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const ConnectTokenClass = preload("res://core/utils/connect_token.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")
const GameOverWinnerRulesClass = preload("res://core/rules/game_over_winner_rules.gd")
const ResultClass = preload("res://core/types/result.gd")
const DEFAULT_PLATFORM_BACKEND_URL := "http://127.0.0.1:8000"
const DEFAULT_INTERNAL_API_SECRET := "dev-internal-secret-change-in-production"
const DEFAULT_RESTAURANT_LOGO_COUNT := 6
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"
const DEFAULT_DISCONNECT_GRACE_PERIOD_SEC := 120.0
const DEFAULT_RESYNC_REQUEST_COOLDOWN_MSEC := 1000
const RESYNC_SNAPSHOT_CHUNK_BUFFER_HEADROOM_RATIO := 0.25
const DEFAULT_RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES := 256 * 1024
const DEFAULT_RESYNC_SNAPSHOT_MAX_CHUNKS := 256
const RESYNC_DELTA_BUFFER_HEADROOM_RATIO := 0.5
const DEFAULT_RESYNC_DELTA_MAX_COMMANDS := 32

var _net = null
var connect_token_secret_override: String = ""
var disconnect_grace_period_sec_override: float = -1.0
var _disconnect_forfeit_ticket_by_key: Dictionary = {} # "ROOM:kind:value" -> ticket (int)
var _last_resync_request_msec_by_peer: Dictionary = {} # peer_id -> last accepted resync request msec
var _last_resync_transfer_mode_by_peer: Dictionary = {} # peer_id -> "delta" | "snapshot"

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

func _get_resync_request_cooldown_msec() -> int:
	var raw := str(OS.get_environment("RESYNC_REQUEST_COOLDOWN_MSEC")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(0, int(raw))
	return DEFAULT_RESYNC_REQUEST_COOLDOWN_MSEC

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

func _get_resync_snapshot_chunk_size_bytes() -> int:
	var buffer_size := 0
	if _net != null and is_instance_valid(_net) and _net is Object:
		var peer = (_net as Object).get("_peer")
		if peer != null and peer is Object:
			buffer_size = int((peer as Object).get("outbound_buffer_size"))
	if buffer_size <= 0:
		buffer_size = 4 * 1024 * 1024
	var hard_cap := maxi(64, int(floor(float(buffer_size) * RESYNC_SNAPSHOT_CHUNK_BUFFER_HEADROOM_RATIO)))
	var raw := str(OS.get_environment("RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return clampi(int(raw), 64, hard_cap)
	return mini(DEFAULT_RESYNC_SNAPSHOT_CHUNK_SIZE_BYTES, hard_cap)

func _get_resync_snapshot_max_chunks() -> int:
	var raw := str(OS.get_environment("RESYNC_SNAPSHOT_MAX_CHUNKS")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(1, int(raw))
	return DEFAULT_RESYNC_SNAPSHOT_MAX_CHUNKS

func _get_resync_delta_soft_limit_bytes() -> int:
	var buffer_size := 0
	if _net != null and is_instance_valid(_net) and _net is Object:
		var peer = (_net as Object).get("_peer")
		if peer != null and peer is Object:
			buffer_size = int((peer as Object).get("outbound_buffer_size"))
	if buffer_size <= 0:
		buffer_size = 4 * 1024 * 1024
	return maxi(1024, int(floor(float(buffer_size) * RESYNC_DELTA_BUFFER_HEADROOM_RATIO)))

func _get_resync_delta_max_commands() -> int:
	var raw := str(OS.get_environment("RESYNC_DELTA_MAX_COMMANDS")).strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		return maxi(0, int(raw))
	return DEFAULT_RESYNC_DELTA_MAX_COMMANDS

func _build_full_resync_snapshot_transfer(room) -> Result:
	if room == null:
		return Result.failure("Room missing")
	if room.game_engine == null:
		return Result.failure("Room engine missing")

	var archive_r = room.game_engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)

	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var transfer_id := "%s_%d_%d" % [
		_safe_text(str(room.room_code).to_upper()),
		int(room.game_engine.command_history.size()),
		int(Time.get_ticks_msec()),
	]
	var chunk_r: Result = ResyncSnapshotTransferClass.build_snapshot_transfer(
		archive,
		transfer_id,
		_get_resync_snapshot_chunk_size_bytes(),
		_get_resync_snapshot_max_chunks()
	)
	if not chunk_r.ok:
		return Result.failure("Resync archive too large (%s)" % str(chunk_r.error))

	var state_hash := ""
	var state = room.game_engine.get_state()
	if state != null and state.has_method("compute_hash"):
		state_hash = str(state.compute_hash())

	var chunk_payload: Dictionary = Dictionary(chunk_r.value)
	var manifest: Dictionary = Dictionary(chunk_payload.get("manifest", {})).duplicate(true)
	manifest["room_code"] = str(room.room_code).strip_edges().to_upper()
	return Result.success({
		"manifest": manifest,
		"chunks": Array(chunk_payload.get("chunks", [])).duplicate(true),
		"payload_bytes": int(chunk_payload.get("total_bytes", 0)),
		"chunk_count": int(chunk_payload.get("chunk_count", 0)),
		"archive_hash": str(chunk_payload.get("archive_hash", "")),
		"history_size": int(room.game_engine.command_history.size()),
		"state_hash": state_hash,
	})

func _build_archive_resync_snapshot_transfer(
	room_code: String,
	archive: Dictionary,
	history_size: int = -1,
	state_hash: String = ""
) -> Result:
	if archive.is_empty():
		return Result.failure("Archive missing")
	var transfer_id := "%s_resume_%d" % [
		_safe_text(str(room_code).to_upper()),
		int(Time.get_ticks_msec()),
	]
	var chunk_r: Result = ResyncSnapshotTransferClass.build_snapshot_transfer(
		Dictionary(archive).duplicate(true),
		transfer_id,
		_get_resync_snapshot_chunk_size_bytes(),
		_get_resync_snapshot_max_chunks()
	)
	if not chunk_r.ok:
		return Result.failure("Resync archive too large (%s)" % str(chunk_r.error))

	var chunk_payload: Dictionary = Dictionary(chunk_r.value)
	var manifest: Dictionary = Dictionary(chunk_payload.get("manifest", {})).duplicate(true)
	manifest["room_code"] = str(room_code).strip_edges().to_upper()
	return Result.success({
		"manifest": manifest,
		"chunks": Array(chunk_payload.get("chunks", [])).duplicate(true),
		"payload_bytes": int(chunk_payload.get("total_bytes", 0)),
		"chunk_count": int(chunk_payload.get("chunk_count", 0)),
		"archive_hash": str(chunk_payload.get("archive_hash", "")),
		"history_size": int(history_size),
		"state_hash": str(state_hash).strip_edges(),
	})

func _build_delta_resync_transfer(room, resume_cursor: Dictionary) -> Result:
	if room == null:
		return Result.failure("Room missing")
	if not room.has_method("build_delta_resume_payload"):
		return Result.failure("Room delta resume missing")
	return room.build_delta_resume_payload(
		Dictionary(resume_cursor).duplicate(true),
		_get_resync_delta_max_commands(),
		_get_resync_delta_soft_limit_bytes()
	)

func _send_prebuilt_resync_snapshot(peer_id: int, request_id: String, room, transfer: Dictionary, source: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var manifest: Dictionary = Dictionary(transfer.get("manifest", {})).duplicate(true)
	manifest["request_id"] = request_id
	_net.rpc_id(peer_id, "rpc_resync_snapshot_manifest", manifest)
	for chunk_val in Array(transfer.get("chunks", [])):
		if not (chunk_val is Dictionary):
			continue
		_net.rpc_id(peer_id, "rpc_resync_snapshot_chunk", Dictionary(chunk_val).duplicate(true))
	GameLog.warn(
		"NetClient",
		"TX ResyncSnapshot source=%s %s %s history_size=%d state_hash=%s total_bytes=%d chunks=%d"
			% [
				_safe_text(source),
				_request_tag(peer_id, request_id),
				_room_brief(room),
				int(transfer.get("history_size", -1)),
				_short_hash(str(transfer.get("state_hash", ""))),
				int(transfer.get("payload_bytes", -1)),
				int(transfer.get("chunk_count", -1)),
		]
	)

func _send_prebuilt_resync_delta(peer_id: int, request_id: String, room, transfer: Dictionary, source: String) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	var payload: Dictionary = Dictionary(transfer.get("payload", {})).duplicate(true)
	payload["request_id"] = request_id
	_net.rpc_id(peer_id, "rpc_resync_delta", payload)
	GameLog.warn(
		"NetClient",
		"TX ResyncDelta source=%s %s %s from=%d to=%d entries=%d final_hash=%s payload_bytes=%d"
			% [
				_safe_text(source),
				_request_tag(peer_id, request_id),
				_room_brief(room),
				int(transfer.get("from_sequence", -1)),
				int(transfer.get("to_sequence", -1)),
				int(transfer.get("entry_count", -1)),
				_short_hash(str(transfer.get("final_hash", ""))),
				int(transfer.get("payload_bytes", -1)),
			]
	)

func _build_best_effort_resume_transfer(room, resume_cursor: Dictionary = {}) -> Result:
	var cursor: Dictionary = Dictionary(resume_cursor).duplicate(true)
	var force_snapshot := bool(cursor.get("force_snapshot", false))
	var fallback_reason := ""
	if not force_snapshot and not cursor.is_empty():
		var delta_r: Result = _build_delta_resync_transfer(room, cursor)
		if delta_r.ok:
			return Result.success({
				"mode": "delta",
				"transfer": Dictionary(delta_r.value).duplicate(true),
			})
		fallback_reason = str(delta_r.error)
	var snapshot_r: Result = _build_full_resync_snapshot_transfer(room)
	if not snapshot_r.ok:
		return snapshot_r
	return Result.success({
		"mode": "snapshot",
		"transfer": Dictionary(snapshot_r.value).duplicate(true),
		"fallback_reason": fallback_reason,
	})

func _dispatch_prepared_resume_transfer(
	peer_id: int,
	request_id: String,
	room,
	prepared_transfer: Dictionary,
	source: String
) -> Result:
	var mode := str(prepared_transfer.get("mode", "")).strip_edges()
	var transfer: Dictionary = Dictionary(prepared_transfer.get("transfer", {})).duplicate(true)
	if mode == "delta":
		_send_prebuilt_resync_delta(peer_id, request_id, room, transfer, source)
		return Result.success({"mode": "delta"})
	if mode == "snapshot":
		var fallback_reason := str(prepared_transfer.get("fallback_reason", "")).strip_edges()
		if not fallback_reason.is_empty():
			GameLog.info(
				"NetClient",
				"Resume delta unavailable source=%s %s reason=%s"
					% [_safe_text(source), _request_tag(peer_id, request_id), fallback_reason]
			)
		_send_prebuilt_resync_snapshot(peer_id, request_id, room, transfer, source)
		return Result.success({"mode": "snapshot"})
	return Result.failure("resume transfer mode invalid: %s" % mode)

func _send_best_effort_resume_transfer(
	peer_id: int,
	request_id: String,
	room,
	source: String,
	resume_cursor: Dictionary = {}
) -> Result:
	var prepared_r: Result = _build_best_effort_resume_transfer(room, resume_cursor)
	if not prepared_r.ok:
		return prepared_r
	return _dispatch_prepared_resume_transfer(
		peer_id,
		request_id,
		room,
		Dictionary(prepared_r.value),
		source
	)

func _is_resync_request_rate_limited(peer_id: int, force_snapshot: bool = false) -> bool:
	var cooldown_msec := _get_resync_request_cooldown_msec()
	if cooldown_msec <= 0:
		_last_resync_request_msec_by_peer[peer_id] = int(Time.get_ticks_msec())
		return false
	var now_msec := int(Time.get_ticks_msec())
	var last_msec := int(_last_resync_request_msec_by_peer.get(peer_id, 0))
	if last_msec > 0 and now_msec - last_msec < cooldown_msec:
		var last_mode := str(_last_resync_transfer_mode_by_peer.get(peer_id, "")).strip_edges()
		if not force_snapshot or last_mode != "delta":
			return true
	_last_resync_request_msec_by_peer[peer_id] = now_msec
	return false

func _remember_resync_transfer_mode(peer_id: int, mode: String) -> void:
	var normalized_mode := str(mode).strip_edges()
	if normalized_mode.is_empty():
		_last_resync_transfer_mode_by_peer.erase(peer_id)
		return
	_last_resync_transfer_mode_by_peer[peer_id] = normalized_mode

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
	_last_resync_request_msec_by_peer.erase(replaced_peer_id)
	_last_resync_transfer_mode_by_peer.erase(replaced_peer_id)
	_net._profile_by_peer_id.erase(replaced_peer_id)
	_net.rpc_id(replaced_peer_id, "rpc_room_state", empty_room_state())

func _build_match_summary_payload(state) -> Dictionary:
	var modules: Array[String] = []
	if state != null and (state.modules is Array):
		for module_val in Array(state.modules):
			var module_id := str(module_val).strip_edges()
			if module_id.is_empty():
				continue
			modules.append(module_id)

	var bank: Dictionary = {}
	if state != null and (state.bank is Dictionary):
		var b: Dictionary = Dictionary(state.bank)
		bank = {
			"total": int(b.get("total", 0)),
			"broke_count": int(b.get("broke_count", 0)),
			"reserve_added_total": int(b.get("reserve_added_total", 0)),
		}

	var marketing_instances: Array = []
	if state != null and (state.marketing_instances is Array):
		marketing_instances = Array(state.marketing_instances).duplicate(true)

	return {
		"modules": modules,
		"round_number": int(state.round_number) if state != null else 0,
		"bank": bank,
		"marketing_instances": marketing_instances,
	}

func _get_finalize_ordered_seat_indices(room) -> Array[int]:
	var ordered_seat_indices: Array[int] = []
	if room != null and (room._seat_profile_by_seat_index is Dictionary):
		for seat_key in room._seat_profile_by_seat_index.keys():
			ordered_seat_indices.append(int(seat_key))
	elif room != null and (room._user_id_by_seat_index is Dictionary):
		for seat_key in room._user_id_by_seat_index.keys():
			ordered_seat_indices.append(int(seat_key))
	ordered_seat_indices.sort()
	return ordered_seat_indices

func _resolve_finalize_player_ordinal(room, state, seat_index: int) -> int:
	if state == null or not (state.players is Array):
		return -1
	var ordered_seat_indices := _get_finalize_ordered_seat_indices(room)
	if ordered_seat_indices.size() == state.players.size():
		return ordered_seat_indices.find(seat_index)
	if seat_index >= 0 and seat_index < state.players.size():
		return seat_index
	return -1

func _resolve_finalize_player_dict(room, state, seat_index: int) -> Dictionary:
	if state == null or not (state.players is Array):
		return {}
	var ordinal := _resolve_finalize_player_ordinal(room, state, seat_index)
	if ordinal < 0 or ordinal >= state.players.size():
		return {}
	var fallback_val = state.players[ordinal]
	if fallback_val is Dictionary:
		return Dictionary(fallback_val)
	return {}

func _canonicalize_participant_stats_product_key(product_id: String) -> String:
	var normalized := str(product_id).strip_edges().to_lower()
	if normalized == "coke" or normalized == "cola":
		return "soda"
	return normalized

func _append_participant_stats_count(target: Dictionary, key: String, amount: int = 1) -> void:
	var stat_key := str(key).strip_edges()
	if stat_key.is_empty():
		return
	var delta := int(amount)
	if delta == 0:
		return
	target[stat_key] = int(target.get(stat_key, 0)) + delta

func _build_participant_stats_payload(room, state, seat_index: int) -> Dictionary:
	if room == null or state == null:
		return {}
	if room.game_engine == null:
		return {}

	var player_ordinal := _resolve_finalize_player_ordinal(room, state, seat_index)
	if player_ordinal < 0:
		return {}

	var history_r := EventHistoryRebuildClass.build(room.game_engine, int(room.game_engine.current_command_index))
	if not history_r.ok:
		GameLog.warn(
			"NetClient",
			"Finalize stats rebuild failed room=%s seat=%d err=%s"
				% [_safe_text(str(room.room_code)), seat_index, str(history_r.error)]
		)
		return {}
	if not (history_r.value is Array):
		return {}

	var marketing_by_type: Dictionary = {}
	var produced: Dictionary = {}
	var sold: Dictionary = {}
	var metrics: Dictionary = {}
	var marketing_actions := 0
	var hired_employees := 0
	var trained_employees := 0

	for event_val in Array(history_r.value):
		if not (event_val is Dictionary):
			continue
		var event: Dictionary = event_val
		var event_type := str(event.get("type", "")).strip_edges()
		if event_type.is_empty():
			continue
		var data_val = event.get("data", null)
		var data: Dictionary = data_val if (data_val is Dictionary) else {}
		var event_player_id := int(data.get("player_id", data.get("actor", -1)))
		if event_player_id != player_ordinal:
			continue

		match event_type:
			"employee_recruited":
				hired_employees += 1
			"employee_trained":
				trained_employees += 1
			"marketing_placed":
				marketing_actions += 1
				_append_participant_stats_count(marketing_by_type, str(data.get("marketing_type", "")).strip_edges())
			"food_produced":
				var produced_key := _canonicalize_participant_stats_product_key(str(data.get("food_type", "")))
				if not produced_key.is_empty():
					_append_participant_stats_count(produced, produced_key, int(data.get("amount", 0)))
			"food_sold":
				var quantity := maxi(1, int(data.get("quantity", 1)))
				var required_val = data.get("required", null)
				if required_val is Dictionary:
					var required: Dictionary = required_val
					for product_key in required.keys():
						var sold_key := _canonicalize_participant_stats_product_key(str(product_key))
						if sold_key.is_empty():
							continue
						_append_participant_stats_count(sold, sold_key, int(required.get(product_key, 0)) * quantity)
			"house_placed":
				_append_participant_stats_count(metrics, "house_built")
			"garden_added":
				_append_participant_stats_count(metrics, "garden_built")
			"restaurant_placed":
				_append_participant_stats_count(metrics, "restaurant_built")
			"restaurant_moved":
				_append_participant_stats_count(metrics, "restaurant_moved")
			"drinks_procured":
				_append_participant_stats_count(metrics, "procurement_actions")
			"command_executed":
				var action_id := str(data.get("action_id", "")).strip_edges()
				if action_id == "place_lobbyists_road" or action_id == "place_lobbyists_park":
					_append_participant_stats_count(metrics, "lobbyists_actions")

	return {
		"marketing_actions": marketing_actions,
		"billboard_placements": int(marketing_by_type.get("billboard", 0)),
		"hired_employees": hired_employees,
		"trained_employees": trained_employees,
		"marketing_by_type": marketing_by_type,
		"metrics": metrics,
		"produced": produced,
		"sold": sold,
	}

func _build_participant_score_payload(room, state, seat_index: int) -> Dictionary:
	var seat_profile: Dictionary = {}
	if room != null and (room._seat_profile_by_seat_index is Dictionary):
		seat_profile = Dictionary(room._seat_profile_by_seat_index.get(seat_index, {}))

	var player: Dictionary = _resolve_finalize_player_dict(room, state, seat_index)

	var employees: Array = []
	var employees_val = player.get("employees", null)
	if employees_val is Array:
		employees = Array(employees_val).duplicate(true)

	var reserve_employees: Array = []
	var reserve_val = player.get("reserve_employees", null)
	if reserve_val is Array:
		reserve_employees = Array(reserve_val).duplicate(true)

	var busy_marketers: Array = []
	var busy_val = player.get("busy_marketers", null)
	if busy_val is Array:
		busy_marketers = Array(busy_val).duplicate(true)

	var restaurants: Array = []
	var restaurants_val = player.get("restaurants", null)
	if restaurants_val is Array:
		restaurants = Array(restaurants_val).duplicate(true)

	var milestones: Array = []
	var milestones_val = player.get("milestones", null)
	if milestones_val is Array:
		milestones = Array(milestones_val).duplicate(true)

	var inventory: Dictionary = {}
	var inventory_val = player.get("inventory", null)
	if inventory_val is Dictionary:
		inventory = Dictionary(inventory_val).duplicate(true)

	var restaurant_logo_id := -1
	var player_logo_val = player.get("restaurant_logo_id", null)
	if player_logo_val is int:
		restaurant_logo_id = int(player_logo_val)
	elif player_logo_val is float:
		var player_logo_float: float = float(player_logo_val)
		if player_logo_float == floor(player_logo_float):
			restaurant_logo_id = int(player_logo_float)
	if restaurant_logo_id < 0:
		restaurant_logo_id = int(seat_profile.get("restaurant_logo_id", -1))

	var stats_payload := _build_participant_stats_payload(room, state, seat_index)

	return {
		"display_name": str(seat_profile.get("name", "Player %d" % [seat_index + 1])),
		"restaurant_logo_id": restaurant_logo_id,
		"cash": int(player.get("cash", 0)),
		"forfeited": bool(player.get("forfeited", false)),
		"employees": employees,
		"reserve_employees": reserve_employees,
		"busy_marketers": busy_marketers,
		"restaurants": restaurants,
		"milestones": milestones,
		"inventory": inventory,
		"stats": stats_payload,
	}

func _build_finalize_participants(room, state, winner_player_id: int) -> Array:
	var participants: Array = []
	if room == null:
		return participants
	if not (room._seat_profile_by_seat_index is Dictionary):
		return participants

	var seat_indices: Array[int] = []
	for seat_key in room._seat_profile_by_seat_index.keys():
		seat_indices.append(int(seat_key))
	seat_indices.sort()

	for seat_index in seat_indices:
		var user_id := ""
		if room._user_id_by_seat_index is Dictionary:
			user_id = str(room._user_id_by_seat_index.get(seat_index, "")).strip_edges()
		if user_id.is_empty():
			GameLog.warn(
				"NetClient",
				"Finalize skip participant without user_id room=%s seat=%d"
					% [_safe_text(str(room.room_code)), seat_index]
			)
			continue

		var score_payload := _build_participant_score_payload(room, state, seat_index)
		var player_ordinal := _resolve_finalize_player_ordinal(room, state, seat_index)
		var forfeited := bool(score_payload.get("forfeited", false))
		var result := "lose"
		if forfeited:
			result = "forfeit"
		elif winner_player_id < 0:
			result = "draw"
		elif player_ordinal == winner_player_id:
			result = "win"

		participants.append({
			"user_id": user_id,
			"role": "player",
			"seat_index": seat_index,
			"result": result,
			"score_json": JSON.stringify(score_payload),
		})

	return participants

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

	var participants := _build_finalize_participants(room, state, winner_player_id)
	var summary_payload := _build_match_summary_payload(state)
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

func _disconnect_grace_key(room_code: String, target_kind: String, target_value: String) -> String:
	return "%s:%s:%s" % [
		str(room_code).strip_edges().to_upper(),
		str(target_kind).strip_edges(),
		str(target_value).strip_edges(),
	]

func _disconnect_forfeit_key(room_code: String, actor_id: int) -> String:
	return _disconnect_grace_key(room_code, "actor", str(int(actor_id)))

func _disconnect_lobby_seat_key(room_code: String, seat_index: int) -> String:
	return _disconnect_grace_key(room_code, "seat", str(int(seat_index)))

func _resolve_disconnect_grace_target(room, peer_id: int) -> Dictionary:
	if room == null:
		return {}
	var room_status := str(room.status).strip_edges()
	if room_status == "Lobby":
		if room.has_method("get_waiting_user_id_for_peer"):
			var waiting_user_id := str(room.get_waiting_user_id_for_peer(peer_id)).strip_edges()
			if not waiting_user_id.is_empty():
				return {
					"kind": "waiting",
					"value": waiting_user_id,
				}
		var seat_index := _resolve_actor_id_for_peer(room, peer_id)
		if seat_index >= 0:
			return {
				"kind": "seat",
				"value": str(seat_index),
			}
		return {}
	if room_status != "InGame":
		return {}
	var actor_id := _resolve_actor_id_for_peer(room, peer_id)
	if actor_id < 0:
		return {}
	return {
		"kind": "actor",
		"value": str(actor_id),
	}

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

func _is_disconnect_target_connected(room, target_kind: String, target_value: String) -> bool:
	var normalized_kind := str(target_kind).strip_edges()
	if normalized_kind == "waiting":
		if room == null or not room.has_method("get_waiting_member_peer_id"):
			return false
		return int(room.get_waiting_member_peer_id(str(target_value).strip_edges())) > 0
	if not str(target_value).is_valid_int():
		return false
	return _is_actor_connected(room, int(target_value))

func _schedule_disconnect_forfeit(room, target: Dictionary) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if room == null:
		return
	var target_kind := str(target.get("kind", "")).strip_edges()
	var target_value := str(target.get("value", "")).strip_edges()
	if target_kind.is_empty() or target_value.is_empty():
		return
	var room_status := str(room.status).strip_edges()
	if room_status != "InGame" and room_status != "Lobby":
		return
	if room_status == "InGame" and room.game_engine == null:
		return
	var grace_sec := _get_disconnect_grace_period_sec()
	var room_code := str(room.room_code).strip_edges().to_upper()
	var key := _disconnect_grace_key(room_code, target_kind, target_value)
	var ticket := int(_disconnect_forfeit_ticket_by_key.get(key, 0)) + 1
	_disconnect_forfeit_ticket_by_key[key] = ticket

	if grace_sec <= 0.0:
		_on_disconnect_grace_timeout(room_code, target_kind, target_value, ticket)
		return

	var tree = _net.get_tree()
	if tree == null or not (tree is SceneTree):
		return
	var timer = (tree as SceneTree).create_timer(grace_sec)
	timer.timeout.connect(Callable(self, "_on_disconnect_grace_timeout").bind(room_code, target_kind, target_value, ticket))
	GameLog.warn(
		"NetClient",
		"Disconnect grace scheduled room=%s kind=%s target=%s grace_sec=%.1f"
			% [_safe_text(room_code), _safe_text(target_kind), _safe_text(target_value), grace_sec]
	)

func _clear_disconnect_forfeit(room_code: String, actor_id: int) -> void:
	var key := _disconnect_forfeit_key(room_code, actor_id)
	if _disconnect_forfeit_ticket_by_key.has(key):
		_disconnect_forfeit_ticket_by_key.erase(key)

func _clear_disconnect_grace_seat(room_code: String, seat_index: int) -> void:
	var key := _disconnect_lobby_seat_key(room_code, seat_index)
	if _disconnect_forfeit_ticket_by_key.has(key):
		_disconnect_forfeit_ticket_by_key.erase(key)

func _clear_disconnect_waiting_member(room_code: String, user_id: String) -> void:
	var key := _disconnect_grace_key(room_code, "waiting", str(user_id).strip_edges())
	if _disconnect_forfeit_ticket_by_key.has(key):
		_disconnect_forfeit_ticket_by_key.erase(key)

func _on_disconnect_grace_timeout(room_code: String, target_kind: String, target_value: String, ticket: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var key := _disconnect_grace_key(room_code, target_kind, target_value)
	if int(_disconnect_forfeit_ticket_by_key.get(key, 0)) != int(ticket):
		return
	_disconnect_forfeit_ticket_by_key.erase(key)

	if _net._room_manager == null:
		return
	var rm = _net._room_manager
	if not (rm.rooms is Dictionary):
		return
	var room = rm.rooms.get(str(room_code).strip_edges().to_upper(), null)
	if room == null:
		return
	if _is_disconnect_target_connected(room, target_kind, target_value):
		return
	if str(room.status) == "Lobby":
		if str(target_kind).strip_edges() == "waiting":
			if not rm.has_method("release_reconnecting_waiting_member"):
				return
			var waiting_release_r: Result = rm.release_reconnecting_waiting_member(room_code, str(target_value))
			if not waiting_release_r.ok:
				GameLog.error(
					"NetClient",
					"release_reconnecting_waiting_member failed after disconnect grace room=%s user=%s err=%s"
						% [_safe_text(room_code), _safe_text(str(target_value)), waiting_release_r.error]
				)
				return
			var waiting_release_payload: Dictionary = Dictionary(waiting_release_r.value) if waiting_release_r.value is Dictionary else {}
			if not bool(waiting_release_payload.get("released", false)):
				return
			var waiting_removed := bool(waiting_release_payload.get("removed", false))
			var waiting_room_after = waiting_release_payload.get("room", null)
			_mark_room_directory_dirty()
			if not waiting_removed and waiting_room_after != null:
				broadcast_room_state(waiting_room_after)
			broadcast_room_list("")
			GameLog.warn(
				"NetClient",
				"Released lobby reconnecting waiting member after disconnect grace room=%s user=%s removed=%s"
					% [_safe_text(room_code), _safe_text(str(target_value)), str(waiting_removed)]
			)
			return
		if str(target_kind).strip_edges() != "seat" or not str(target_value).is_valid_int():
			return
		if not rm.has_method("release_reconnecting_seat"):
			return
		var release_r: Result = rm.release_reconnecting_seat(room_code, int(target_value))
		if not release_r.ok:
			GameLog.error(
				"NetClient",
				"release_reconnecting_seat failed after disconnect grace room=%s seat=%s err=%s"
					% [_safe_text(room_code), _safe_text(str(target_value)), release_r.error]
			)
			return
		var release_payload: Dictionary = Dictionary(release_r.value) if release_r.value is Dictionary else {}
		if not bool(release_payload.get("released", false)):
			return
		var removed := bool(release_payload.get("removed", false))
		var room_after = release_payload.get("room", null)
		_mark_room_directory_dirty()
		if not removed and room_after != null:
			broadcast_room_state(room_after)
		broadcast_room_list("")
		GameLog.warn(
			"NetClient",
			"Released lobby reconnecting seat after disconnect grace room=%s seat=%s removed=%s"
				% [_safe_text(room_code), _safe_text(str(target_value)), str(removed)]
		)
		return
	if room.game_engine == null or str(room.status) != "InGame":
		return
	if str(target_kind).strip_edges() != "actor" or not str(target_value).is_valid_int():
		return
	var actor_id := int(target_value)

	var state = room.game_engine.get_state()
	if server_is_player_forfeited(state, actor_id):
		return

	var cmd = CommandClass.create("forfeit_player", actor_id, {})
	var fr = room.game_engine.execute_command(cmd)
	if fr.ok:
		GameLog.warn("NetClient", "Applied forfeit after disconnect grace room=%s actor=%d" % [_safe_text(room_code), actor_id])
		broadcast_command_applied(room, cmd)
		server_drain_forfeited_auto_steps(room)
		_try_finalize_match_if_game_over(room)
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

	_last_resync_request_msec_by_peer.erase(peer_id)
	_last_resync_transfer_mode_by_peer.erase(peer_id)
	_net._profile_by_peer_id.erase(peer_id)
	var room = _net._room_manager.get_room_by_peer(peer_id)
	var room_status := str(room.status) if room != null else ""
	var in_game := room != null and room_status == "InGame"
	var preserve_room_on_disconnect := room != null and (room_status == "InGame" or room_status == "Lobby")
	var disconnect_target: Dictionary = _resolve_disconnect_grace_target(room, peer_id)
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
		_schedule_disconnect_forfeit(room, disconnect_target)

	if rr.ok and room != null and not removed:
		_mark_room_directory_dirty()
		broadcast_room_state(room)
		broadcast_room_list("")
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
		var prepared_r: Result = _build_best_effort_resume_transfer(existing_room, resume_cursor)
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
				_clear_disconnect_grace_seat(room_code, seat_index3)
			else:
				_clear_disconnect_forfeit(room_code, seat_index3)
		elif is_resume_room and str(room.status).strip_edges() == "Lobby":
			var waiting_user_id := str(token_payload.get("user_id", "")).strip_edges()
			if not waiting_user_id.is_empty():
				_clear_disconnect_waiting_member(room_code, waiting_user_id)

	# InGame：自动下发 GameStarted + chunked snapshot（与 JoinRoom in-game 行为对齐）
	if str(room.status) == "InGame" and room.game_engine != null:
		if prepared_resume_transfer.is_empty():
			var prepared_fallback_r: Result = _build_best_effort_resume_transfer(room, resume_cursor)
			if not prepared_fallback_r.ok:
				return ResultClass.failure(prepared_fallback_r.error)
			prepared_resume_transfer = Dictionary(prepared_fallback_r.value).duplicate(true)
		_net.rpc_id(peer_id, "rpc_game_started", {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
			"local_player_id": room.get_seat_index_for_peer(peer_id) if room.has_method("get_seat_index_for_peer") else -1,
		})
		var resume_r: Result = _dispatch_prepared_resume_transfer(
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
			var transfer_r: Result = _build_full_resync_snapshot_transfer(target_room)
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
		var payload := {
			"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
			"config": room.config.duplicate(true),
			"local_player_id": room.get_seat_index_for_peer(peer_id) if room.has_method("get_seat_index_for_peer") else -1,
		}
		_net.rpc_id(peer_id, "rpc_game_started", payload)
		var transfer_to_send := in_game_resync_snapshot_transfer
		if transfer_to_send.is_empty():
			var transfer_r2: Result = _build_full_resync_snapshot_transfer(room)
			if not transfer_r2.ok:
				send_request_rejected(peer_id, request_id, "join_room_failed", transfer_r2.error)
				return
			transfer_to_send = Dictionary(transfer_r2.value)
		_send_prebuilt_resync_snapshot(peer_id, request_id, room, transfer_to_send, "join_room")

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
				_clear_disconnect_forfeit(str(room.room_code), actor_id)
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

	var resume_start_snapshot_transfer: Dictionary = {}
	if room.has_method("is_resume_archive_room") and room.is_resume_archive_room():
		if not room.has_method("build_effective_resume_start_archive"):
			send_request_rejected(peer_id, request_id, "start_game_failed", "Room.build_effective_resume_start_archive missing")
			return
		var effective_resume_r: Result = room.build_effective_resume_start_archive()
		if not effective_resume_r.ok:
			send_request_rejected(peer_id, request_id, "start_game_failed", effective_resume_r.error)
			return
		var effective_resume_val = effective_resume_r.value
		if not (effective_resume_val is Dictionary):
			send_request_rejected(peer_id, request_id, "start_game_failed", "resume start archive type invalid")
			return
		var effective_resume_info: Dictionary = effective_resume_val
		var resume_archive: Dictionary = Dictionary(effective_resume_info.get("archive", {})).duplicate(true)
		if resume_archive.is_empty():
			send_request_rejected(peer_id, request_id, "start_game_failed", "resume start archive missing")
			return
		var resume_hash := str(effective_resume_info.get("final_hash", resume_archive.get("final_hash", ""))).strip_edges()
		var history_size := int(effective_resume_info.get("history_size", -1))
		var transfer_r: Result = _build_archive_resync_snapshot_transfer(
			str(room.room_code),
			resume_archive,
			history_size,
			resume_hash
		)
		if not transfer_r.ok:
			send_request_rejected(peer_id, request_id, "start_game_failed", transfer_r.error)
			return
		resume_start_snapshot_transfer = Dictionary(transfer_r.value).duplicate(true)

	var sr = room.start_game()
	if not sr.ok:
		send_request_rejected(peer_id, request_id, "start_game_failed", sr.error)
		return

	_mark_room_directory_dirty()
	broadcast_room_state(room)
	broadcast_room_list("")

	var payload_val: Dictionary = Dictionary(sr.value)
	var payload := {
		"player_id_by_peer_id": Dictionary(payload_val.get("player_id_by_peer_id", {})),
		"config": Dictionary(payload_val.get("config", {})),
	}

	for pid in room.get_peer_ids():
		var per_peer_payload := payload.duplicate(true)
		per_peer_payload["local_player_id"] = room.get_seat_index_for_peer(int(pid)) if room.has_method("get_seat_index_for_peer") else -1
		_net.rpc_id(int(pid), "rpc_game_started", per_peer_payload)
		if not resume_start_snapshot_transfer.is_empty():
			_send_prebuilt_resync_snapshot(int(pid), request_id, room, resume_start_snapshot_transfer, "start_game_resume_archive")
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
	if _is_resync_request_rate_limited(peer_id, force_snapshot):
		send_request_rejected(peer_id, request_id, "resync_rate_limited", "Resync requested too frequently")
		return
	var resume_r: Result = _send_best_effort_resume_transfer(
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
	_remember_resync_transfer_mode(peer_id, str(resume_payload.get("mode", "")))

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
		"room_code": str(room.room_code).strip_edges().to_upper(),
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
			_net.rpc_id(target_peer_id, "rpc_rewind_to_turn_start_meta", out)
	else:
		_net.rpc_id(peer_id, "rpc_rewind_to_turn_start_meta", out)

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
	if room.has_method("record_resume_delta"):
		room.record_resume_delta(cmd, state_hash)
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
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
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
