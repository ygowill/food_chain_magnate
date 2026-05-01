class_name OnlineRoom
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const ArchiveRecoveryClass = preload("res://core/engine/game_engine/archive_recovery.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")
const ResumeDeltaStoreClass = preload("res://server/room_resume_delta_store.gd")
const RollbackProposalStoreClass = preload("res://server/room_rollback_proposal_store.gd")
const StartSessionStateClass = preload("res://server/room_start_session_state.gd")
const DEFAULT_RESTAURANT_LOGO_COUNT := 6
const RESUME_PARTICIPANT_BINDINGS_CONFIG_KEY := "resume_participant_bindings"

const STATUS_LOBBY := "Lobby"
const STATUS_STARTING := "Starting"
const STATUS_IN_GAME := "InGame"
const STATUS_ENDED := "Ended"
const ROOM_MODE_NORMAL := "normal"
const ROOM_MODE_RESUME_ARCHIVE := "resume_archive"

const SEAT_CONNECTED := "CONNECTED"
const SEAT_RECONNECTING := "RECONNECTING"
const SEAT_FORFEITED := "FORFEITED"
const RESUME_DELTA_ROTATE_COMMAND_THRESHOLD := 32

var room_code: String = ""
var host_peer_id: int = 0
var status: String = STATUS_LOBBY
var config: Dictionary = {}
var join_policy: String = "public"
var password_hash: String = ""

var updated_at_ms: int = 0
var started_at_iso: String = ""
var ended_at_iso: String = ""
var started_at_unix_sec: int = 0
var ended_at_unix_sec: int = 0
var match_finalize_in_flight: bool = false
var match_finalize_reported: bool = false
var finalized_match_id: String = ""

var game_engine = null
var player_id_by_peer_id: Dictionary = {} # peer_id -> player_id

# 兼容外部现有调用：以下字段由 _seat_slot_by_index 派生，不再作为权威状态。
var _seat_profile_by_seat_index: Dictionary = {} # seat_index -> profile
var _peer_id_by_seat_index: Dictionary = {} # seat_index -> peer_id
var _player_profile_by_peer_id: Dictionary = {} # peer_id -> profile
var _spectator_profile_by_peer_id: Dictionary = {} # peer_id -> profile
var _seat_by_player_peer_id: Dictionary = {} # peer_id -> seat_index
var _desired_player_count: int = 0
var _user_id_by_seat_index: Dictionary = {} # seat_index -> user_id
var _host_seat_index: int = -1
var owner_user_id: String = ""
var room_mode: String = ROOM_MODE_NORMAL

var _seat_slot_by_index: Dictionary = {} # seat_index -> slot
var _waiting_member_by_user_id: Dictionary = {} # user_id -> member
var _waiting_member_by_peer_id: Dictionary = {} # peer_id -> member（运行时视图）
var _resume_lobby_archive: Dictionary = {}
var _prepared_resume_start_engine = null
var _prepared_resume_start_archive: Dictionary = {}
var _prepared_resume_start_final_hash: String = ""
var _resume_delta_store = ResumeDeltaStoreClass.new()
var _start_session_state = StartSessionStateClass.new()
var _rollback_proposal_store = RollbackProposalStoreClass.new()

func to_persistence_dict(include_runtime_membership: bool = false) -> Result:
	var persisted_status := str(status)
	if persisted_status == STATUS_STARTING:
		persisted_status = STATUS_LOBBY
	if persisted_status != STATUS_IN_GAME and persisted_status != STATUS_LOBBY:
		return Result.failure("只支持持久化 Lobby/InGame 房间")
	var span := OnlinePerfTraceClass.begin_span("server.persistence.room.to_dict", {
		"room_code": room_code,
		"status": persisted_status,
		"include_runtime_membership": bool(include_runtime_membership),
	})

	_sync_seat_states_from_engine()

	var archive: Dictionary = {}
	if persisted_status == STATUS_IN_GAME:
		if game_engine == null:
			OnlinePerfTraceClass.end_span(span, {
				"ok": false,
				"error": "InGame 房间缺少 game_engine",
			})
			return Result.failure("InGame 房间缺少 game_engine")
		var archive_span := OnlinePerfTraceClass.begin_span("server.persistence.room.create_archive", {
			"room_code": room_code,
			"history_size": int(game_engine.command_history.size()),
			"current_index": int(game_engine.current_command_index),
		})
		var archive_r: Result = game_engine.create_archive()
		if not archive_r.ok:
			OnlinePerfTraceClass.end_span(archive_span, {
				"ok": false,
				"error": str(archive_r.error),
			})
			OnlinePerfTraceClass.end_span(span, {
				"ok": false,
				"error": str(archive_r.error),
			})
			return Result.failure("create_archive failed: %s" % archive_r.error)
		archive = Dictionary(archive_r.value).duplicate(true)
		var commands_val = archive.get("commands", null)
		OnlinePerfTraceClass.end_span(archive_span, {
			"ok": true,
			"command_count": Array(commands_val).size() if commands_val is Array else 0,
			"current_index": int(archive.get("current_index", -1)),
		})

	var out := {
		"room_code": room_code,
		"status": persisted_status,
		"owner_user_id": owner_user_id,
		"room_mode": room_mode,
		"config": config.duplicate(true),
		"join_policy": join_policy,
		"password_hash": password_hash,
		"updated_at_ms": updated_at_ms,
		"started_at_iso": started_at_iso,
		"ended_at_iso": ended_at_iso,
		"started_at_unix_sec": started_at_unix_sec,
		"ended_at_unix_sec": ended_at_unix_sec,
		"match_finalize_reported": match_finalize_reported,
		"finalized_match_id": finalized_match_id,
		"host_seat_index": _host_seat_index,
		"seat_slots": _seat_slot_by_index.duplicate(true),
		"waiting_members": _serialize_waiting_members(),
		"seat_profiles": _seat_profile_by_seat_index.duplicate(true),
		"user_ids_by_seat": _user_id_by_seat_index.duplicate(true),
		"archive": archive,
	}
	if include_runtime_membership:
		out["runtime_status"] = str(status)
	if persisted_status == STATUS_LOBBY and room_mode == ROOM_MODE_RESUME_ARCHIVE:
		out["resume_lobby_archive"] = _resume_lobby_archive.duplicate(true)
	if include_runtime_membership:
		out["spectators"] = _build_directory_spectators_array()
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"has_archive": not archive.is_empty(),
		"spectator_count": Array(out.get("spectators", [])).size() if out.get("spectators", null) is Array else 0,
	})
	return Result.success(out)

static func from_persistence_dict(data: Dictionary) -> Result:
	var room_code_read := str(data.get("room_code", "")).strip_edges().to_upper()
	if room_code_read.is_empty():
		return Result.failure("持久化房间缺少 room_code")
	var status_read := str(data.get("status", "")).strip_edges()
	if status_read != STATUS_IN_GAME and status_read != STATUS_LOBBY:
		return Result.failure("当前仅支持恢复 Lobby/InGame 房间: %s" % status_read)
	var config_val = data.get("config", null)
	if not (config_val is Dictionary):
		return Result.failure("持久化房间 config 类型错误（期望 Dictionary）")
	var archive_val = data.get("archive", null)
	if status_read == STATUS_IN_GAME and not (archive_val is Dictionary):
		return Result.failure("持久化房间 archive 类型错误（期望 Dictionary）")

	var room := OnlineRoom.new(
		room_code_read,
		0,
		str(data.get("join_policy", "public")).strip_edges(),
		str(data.get("password_hash", "")).strip_edges(),
		Dictionary(config_val).duplicate(true)
	)
	room.status = status_read
	room.owner_user_id = str(data.get("owner_user_id", "")).strip_edges()
	room.room_mode = _normalize_room_mode(str(data.get("room_mode", room.config.get("room_mode", ROOM_MODE_NORMAL))))
	room.updated_at_ms = int(data.get("updated_at_ms", 0))
	room.started_at_iso = str(data.get("started_at_iso", "")).strip_edges()
	room.ended_at_iso = str(data.get("ended_at_iso", "")).strip_edges()
	room.started_at_unix_sec = int(data.get("started_at_unix_sec", 0))
	room.ended_at_unix_sec = int(data.get("ended_at_unix_sec", 0))
	room.match_finalize_in_flight = false
	room.match_finalize_reported = bool(data.get("match_finalize_reported", false))
	room.finalized_match_id = str(data.get("finalized_match_id", "")).strip_edges()
	room._host_seat_index = int(data.get("host_seat_index", -1))
	room.host_peer_id = 0

	var slots_val = data.get("seat_slots", null)
	if slots_val is Dictionary:
		room._seat_slot_by_index = _normalize_seat_slots(Dictionary(slots_val))
	else:
		var seat_profiles := _normalize_int_key_dict(data.get("seat_profiles", null))
		var user_ids := _normalize_int_key_dict(data.get("user_ids_by_seat", null))
		var seat_indices: Array[int] = []
		for key in seat_profiles.keys():
			seat_indices.append(int(key))
		seat_indices.sort()
		for seat_index in seat_indices:
			var profile: Dictionary = Dictionary(seat_profiles.get(seat_index, {})).duplicate(true)
			var user_id := str(user_ids.get(seat_index, "")).strip_edges()
			var state := SEAT_FORFEITED if bool(Dictionary(profile).get("forfeited", false)) else SEAT_RECONNECTING
			room._seat_slot_by_index[seat_index] = room._make_seat_slot(
				seat_index,
				"host" if seat_index == room._host_seat_index else "player",
				user_id,
				profile,
				state,
				0,
				0
			)

		room._player_profile_by_peer_id = {}
		room._spectator_profile_by_peer_id = {}
		room._waiting_member_by_user_id = room._deserialize_waiting_members(data.get("waiting_members", null))
		room._resume_lobby_archive = Dictionary(data.get("resume_lobby_archive", {})).duplicate(true)
		room._desired_player_count = int(room.config.get("desired_player_count", room._seat_slot_by_index.size()))
		if room.room_mode == ROOM_MODE_RESUME_ARCHIVE and room.status == STATUS_LOBBY:
			if room._desired_player_count <= 0:
				room._desired_player_count = room._infer_resume_player_count_from_archive(room._resume_lobby_archive)
				if room._desired_player_count > 0:
					room.config["desired_player_count"] = room._desired_player_count

	if status_read == STATUS_IN_GAME:
		var engine := GameEngineClass.new()
		var load_r: Result = engine.load_from_archive(Dictionary(archive_val).duplicate(true))
		if not load_r.ok:
			return Result.failure("恢复房间 archive 失败: %s" % load_r.error)
		room.game_engine = engine
		var checkpoint_r: Result = room._reset_recovery_store_from_current_engine("restore")
		if not checkpoint_r.ok:
			return Result.failure("恢复房间 recovery store 失败: %s" % checkpoint_r.error)

	room._rebuild_runtime_views()
	return Result.success(room)

static func _normalize_int_key_dict(value) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	var src: Dictionary = Dictionary(value)
	for key in src.keys():
		var key_text := str(key).strip_edges()
		if key_text.is_empty():
			continue
		out[int(key_text)] = src.get(key, null)
	return out

static func _normalize_seat_slots(value: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in value.keys():
		var key_text := str(key).strip_edges()
		if key_text.is_empty():
			continue
		var seat_index := int(key_text)
		var raw = value.get(key, null)
		if not (raw is Dictionary):
			continue
		var slot_src: Dictionary = Dictionary(raw)
		var slot := {
			"seat_index": seat_index,
			"role": str(slot_src.get("role", "player")).strip_edges(),
			"user_id": str(slot_src.get("user_id", "")).strip_edges(),
			"profile": Dictionary(slot_src.get("profile", {})).duplicate(true),
			"seat_state": str(slot_src.get("seat_state", SEAT_RECONNECTING)).strip_edges(),
			"peer_id": 0,
			"generation": int(slot_src.get("generation", 0)),
			"reconnect_deadline_ms": int(slot_src.get("reconnect_deadline_ms", 0)),
		}
		if slot["seat_state"] != SEAT_CONNECTED and slot["seat_state"] != SEAT_RECONNECTING and slot["seat_state"] != SEAT_FORFEITED:
			slot["seat_state"] = SEAT_RECONNECTING
		out[seat_index] = slot
	return out

func _init(p_room_code: String, p_host_peer_id: int, p_join_policy: String, p_password_hash: String, p_config: Dictionary) -> void:
	room_code = p_room_code
	host_peer_id = p_host_peer_id
	join_policy = p_join_policy
	password_hash = p_password_hash
	config = p_config.duplicate(true)
	room_mode = _normalize_room_mode(str(config.get("room_mode", ROOM_MODE_NORMAL)))
	_desired_player_count = int(config.get("desired_player_count", 0))
	_touch()

static func _normalize_room_mode(raw_mode: String) -> String:
	var mode := str(raw_mode).strip_edges()
	if mode == ROOM_MODE_RESUME_ARCHIVE:
		return ROOM_MODE_RESUME_ARCHIVE
	return ROOM_MODE_NORMAL

static func _enable_online_settlement_confirm_on_engine(engine) -> Result:
	return OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)

func _clear_prepared_resume_start_cache() -> void:
	_prepared_resume_start_engine = null
	_prepared_resume_start_archive = {}
	_prepared_resume_start_final_hash = ""

func _clear_pending_start_session() -> void:
	_start_session_state.clear()

func has_pending_start_session() -> bool:
	return _start_session_state.has_pending()

func get_pending_start_session_id() -> String:
	return _start_session_state.get_session_id()

func get_pending_start_request_id() -> String:
	return _start_session_state.get_request_id()

func set_pending_start_phase(phase: String) -> void:
	if not has_pending_start_session():
		return
	_start_session_state.set_phase(phase)
	_touch()

func get_pending_start_target_peer_ids() -> Array[int]:
	return _start_session_state.get_target_peer_ids()

func begin_start_game_session(request_id: String) -> Result:
	if has_pending_start_session():
		return Result.failure("Room start already in progress")
	var ready := can_start_game()
	if not ready.ok:
		return ready

	var started_at_ms := int(Time.get_unix_time_from_system() * 1000.0)
	status = STATUS_STARTING
	_start_session_state.begin(room_code, request_id, get_peer_ids(), started_at_ms)
	_touch()
	return Result.success(get_pending_start_summary())

func get_pending_start_summary() -> Dictionary:
	return _start_session_state.get_summary()

func mark_pending_start_peer_ready(peer_id: int) -> bool:
	if not _start_session_state.mark_peer_ready(peer_id):
		return false
	_touch()
	return true

func is_pending_start_ready_to_commit() -> bool:
	return _start_session_state.is_ready_to_commit()

func abort_prepared_start_game(reason: String = "") -> void:
	_start_session_state.set_error(reason)
	status = STATUS_LOBBY
	game_engine = null
	_clear_pending_start_session()
	_clear_prepared_resume_start_cache()
	_rebuild_runtime_views()
	_touch()

func _prepare_effective_resume_start_engine() -> Result:
	if not is_resume_archive_room():
		return Result.failure("Room is not a resume lobby")
	if _resume_lobby_archive.is_empty():
		return Result.failure("resume archive missing")
	if _prepared_resume_start_engine != null and is_instance_valid(_prepared_resume_start_engine):
		var prepared_state = _prepared_resume_start_engine.get_state() if _prepared_resume_start_engine.has_method("get_state") else null
		var prepared_hash := ""
		if prepared_state != null and prepared_state.has_method("compute_hash"):
			prepared_hash = str(prepared_state.compute_hash())
		return Result.success({
			"engine": _prepared_resume_start_engine,
			"history_size": int(_prepared_resume_start_engine.command_history.size()),
			"current_index": int(_prepared_resume_start_engine.current_command_index),
			"final_hash": prepared_hash,
		})

	var preview_engine = GameEngineClass.new()
	var load_r: Result = preview_engine.load_from_archive(_resume_lobby_archive.duplicate(true))
	if not load_r.ok:
		return Result.failure("GameEngine.load_from_archive failed: %s" % load_r.error)
	if int(preview_engine.current_command_index) < int(preview_engine.command_history.size()) - 1:
		preview_engine.truncate_future_history()

	var validate_r: Result = OnlineResumePointValidatorClass.validate_resume_point_strict(preview_engine)
	if not validate_r.ok:
		return validate_r

	_prepared_resume_start_engine = preview_engine
	_prepared_resume_start_archive = {}
	_prepared_resume_start_final_hash = str(preview_engine.get_state().compute_hash()) if preview_engine.get_state() != null else ""
	return Result.success({
		"engine": preview_engine,
		"history_size": int(preview_engine.command_history.size()),
		"current_index": int(preview_engine.current_command_index),
		"final_hash": _prepared_resume_start_final_hash,
	}).with_warnings(validate_r.warnings)

func _touch() -> void:
	updated_at_ms = int(Time.get_unix_time_from_system() * 1000.0)

func _reset_recovery_store_from_current_engine(reason: String = "") -> Result:
	return _resume_delta_store.reset_from_engine(status, STATUS_IN_GAME, game_engine, reason)

func get_resume_cursor() -> Dictionary:
	return _resume_delta_store.get_cursor(game_engine)

func build_delta_resume_payload(cursor: Dictionary, max_commands: int = 0, soft_limit_bytes: int = 0) -> Result:
	return _resume_delta_store.build_payload(room_code, status, STATUS_IN_GAME, game_engine, cursor, max_commands, soft_limit_bytes)

func record_resume_delta(cmd: Command, post_state_hash: String = "") -> Result:
	return _resume_delta_store.record(status, STATUS_IN_GAME, game_engine, cmd, post_state_hash, RESUME_DELTA_ROTATE_COMMAND_THRESHOLD)

func _make_seat_slot(
	seat_index: int,
	role: String,
	user_id: String,
	profile: Dictionary,
	seat_state: String,
	peer_id: int,
	generation: int
) -> Dictionary:
	var normalized_profile: Dictionary = Dictionary(profile).duplicate(true)
	if str(normalized_profile.get("name", "")).strip_edges().is_empty():
		normalized_profile["name"] = "玩家 %d" % [seat_index + 1]
	if not normalized_profile.has("color_index"):
		normalized_profile["color_index"] = 0
	if not normalized_profile.has("restaurant_logo_id"):
		normalized_profile["restaurant_logo_id"] = -1
	return {
		"seat_index": int(seat_index),
		"role": "host" if str(role).strip_edges() == "host" else "player",
		"user_id": str(user_id).strip_edges(),
		"profile": normalized_profile,
		"seat_state": str(seat_state).strip_edges(),
		"peer_id": int(peer_id),
		"generation": int(generation),
		"reconnect_deadline_ms": 0,
	}

func _make_waiting_member(
	user_id: String,
	role: String,
	profile: Dictionary,
	peer_id: int,
	member_status: String = "active",
	generation: int = 1
) -> Dictionary:
	var normalized_profile: Dictionary = Dictionary(profile).duplicate(true)
	if str(normalized_profile.get("name", "")).strip_edges().is_empty():
		normalized_profile["name"] = "玩家"
	if not str(user_id).strip_edges().is_empty():
		normalized_profile["user_id"] = str(user_id).strip_edges()
	var normalized_status := str(member_status).strip_edges()
	if normalized_status != "reconnecting":
		normalized_status = "active"
	return {
		"user_id": str(user_id).strip_edges(),
		"role": "host" if str(role).strip_edges() == "host" else "player",
		"profile": normalized_profile,
		"peer_id": int(peer_id),
		"member_status": normalized_status,
		"generation": maxi(1, int(generation)),
	}

func _initial_generation(token_generation: int = -1) -> int:
	if int(token_generation) > 0:
		return int(token_generation) + 1
	return 1

func _consume_generation(current_generation: int, token_generation: int = -1) -> Result:
	var normalized_current := maxi(1, int(current_generation))
	var normalized_token := int(token_generation)
	if normalized_token > 0:
		if normalized_token < normalized_current:
			return Result.failure("generation_conflict")
		return Result.success(normalized_token + 1)
	return Result.success(normalized_current + 1)

func _serialize_waiting_members() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var user_ids: Array[String] = []
	for user_id_key in _waiting_member_by_user_id.keys():
		var uid := str(user_id_key).strip_edges()
		if uid.is_empty():
			continue
		user_ids.append(uid)
	user_ids.sort()
	for user_id in user_ids:
		var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id, {}))
		if member.is_empty():
			continue
		out.append({
			"user_id": user_id,
			"role": str(member.get("role", "player")).strip_edges(),
			"profile": Dictionary(member.get("profile", {})).duplicate(true),
			"peer_id": int(member.get("peer_id", 0)),
			"member_status": str(member.get("member_status", "active")).strip_edges(),
			"generation": int(member.get("generation", 1)),
		})
	return out

func _deserialize_waiting_members(value) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Array):
		return out
	for item in Array(value):
		if not (item is Dictionary):
			continue
		var member_src: Dictionary = Dictionary(item)
		var user_id := str(member_src.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		out[user_id] = _make_waiting_member(
			user_id,
			str(member_src.get("role", "player")).strip_edges(),
			Dictionary(member_src.get("profile", {})).duplicate(true),
			int(member_src.get("peer_id", 0)),
			str(member_src.get("member_status", "active")).strip_edges(),
			int(member_src.get("generation", 1))
		)
	return out

func _infer_resume_player_count_from_archive(archive: Dictionary) -> int:
	if archive.is_empty():
		return 0
	var initial_state_val = archive.get("initial_state", null)
	if not (initial_state_val is Dictionary):
		return 0
	var players_val = Dictionary(initial_state_val).get("players", null)
	if not (players_val is Array):
		return 0
	return Array(players_val).size()

func _get_resume_participant_bindings_from_config() -> Array[Dictionary]:
	var bindings_val = config.get(RESUME_PARTICIPANT_BINDINGS_CONFIG_KEY, null)
	if not (bindings_val is Array):
		return []
	return _normalize_resume_participant_bindings(Array(bindings_val))

func _get_resume_participant_slots_from_archive() -> Array[Dictionary]:
	if _resume_lobby_archive.is_empty():
		return []
	return ArchiveClass.get_online_resume_participant_slots(_resume_lobby_archive)

func _normalize_resume_participant_bindings(value: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in value:
		if not (item is Dictionary):
			continue
		var slot_src: Dictionary = Dictionary(item)
		var user_id := str(slot_src.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		var seat_index := _parse_optional_int(slot_src.get("seat_index", null), -1)
		if seat_index < 0:
			seat_index = _parse_optional_int(slot_src.get("player_id", null), -1)
		if seat_index < 0:
			continue
		out.append({
			"seat_index": seat_index,
			"player_id": _parse_optional_int(slot_src.get("player_id", null), seat_index),
			"user_id": user_id,
			"role": "host" if str(slot_src.get("role", "")).strip_edges() == "host" else "player",
		})
	return out

func _parse_optional_int(value, default_value: int = -1) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return default_value

func _find_resume_binding_for_user_id(user_id: String) -> Dictionary:
	var uid := str(user_id).strip_edges()
	if uid.is_empty():
		return {}
	for binding in _get_resume_participant_bindings_from_config():
		if str(binding.get("user_id", "")).strip_edges() == uid:
			return Dictionary(binding).duplicate(true)
	for slot in _get_resume_participant_slots_from_archive():
		if str(slot.get("user_id", "")).strip_edges() == uid:
			return Dictionary(slot).duplicate(true)
	return {}

func _find_resume_expected_seat_index_for_user_id(user_id: String) -> int:
	var binding: Dictionary = _find_resume_binding_for_user_id(user_id)
	if binding.is_empty():
		return -1
	var seat_index := _parse_optional_int(binding.get("seat_index", null), -1)
	if seat_index < 0:
		seat_index = _parse_optional_int(binding.get("player_id", null), -1)
	if seat_index < 0:
		return -1
	if _desired_player_count > 0 and seat_index >= _desired_player_count:
		return -1
	return seat_index

func find_seat_index_for_user_id(user_id: String) -> int:
	var uid := str(user_id).strip_edges()
	if uid.is_empty():
		return -1
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		if str(slot.get("user_id", "")).strip_edges() == uid:
			return seat_index
	return -1

func _build_online_resume_meta_for_archive() -> Dictionary:
	if status != STATUS_IN_GAME or game_engine == null or not game_engine.has_method("get_state"):
		return {}
	var state = game_engine.get_state()
	if state == null or not (state.players is Array):
		return {}
	var participant_slots := _build_online_resume_participant_slots(state)
	if participant_slots.is_empty():
		return {}
	return {
		"version": ArchiveClass.ONLINE_RESUME_META_VERSION,
		"owner_user_id": owner_user_id,
		"saved_at": Time.get_datetime_string_from_system(),
		"participant_slots": participant_slots,
	}

func _build_online_resume_participant_slots(state) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.players is Array):
		return out
	var players: Array = Array(state.players)
	var map_restaurants: Dictionary = {}
	if state.map is Dictionary:
		map_restaurants = Dictionary(Dictionary(state.map).get("restaurants", {}))
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var user_id := str(slot.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		var profile: Dictionary = Dictionary(slot.get("profile", {})).duplicate(true)
		var player: Dictionary = {}
		if seat_index >= 0 and seat_index < players.size() and players[seat_index] is Dictionary:
			player = Dictionary(players[seat_index]).duplicate(true)
		out.append({
			"seat_index": seat_index,
			"player_id": seat_index,
			"user_id": user_id,
			"display_name": str(profile.get("name", "")).strip_edges(),
			"role": str(slot.get("role", "player")).strip_edges(),
			"restaurant_logo_id": int(player.get("restaurant_logo_id", profile.get("restaurant_logo_id", -1))),
			"cash": int(player.get("cash", 0)),
			"restaurants_count": Array(player.get("restaurants", [])).size(),
			"restaurant_summary": _build_online_resume_restaurant_summary(player, map_restaurants),
		})
	return out

func _build_online_resume_restaurant_summary(player: Dictionary, map_restaurants: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var restaurant_ids: Array[String] = []
	for rest_id_val in Array(player.get("restaurants", [])):
		var restaurant_id := str(rest_id_val).strip_edges()
		if restaurant_id.is_empty():
			continue
		restaurant_ids.append(restaurant_id)
	restaurant_ids.sort()
	for restaurant_id2 in restaurant_ids:
		var rest: Dictionary = Dictionary(map_restaurants.get(restaurant_id2, {})).duplicate(true)
		out.append({
			"restaurant_id": restaurant_id2,
			"anchor_pos": _serialize_grid_pos(rest.get("anchor_pos", null)),
			"entrance_pos": _serialize_grid_pos(rest.get("entrance_pos", null)),
			"rotation": int(rest.get("rotation", 0)),
		})
	return out

func _serialize_grid_pos(value):
	if value is Vector2i:
		var pos: Vector2i = value
		return [pos.x, pos.y]
	if value is Vector2:
		var pos2: Vector2 = value
		return [int(pos2.x), int(pos2.y)]
	if value is Array:
		var arr: Array = Array(value)
		if arr.size() >= 2:
			return [int(arr[0]), int(arr[1])]
	if value is Dictionary:
		var dict_val: Dictionary = Dictionary(value)
		if dict_val.has("x") and dict_val.has("y"):
			return [int(dict_val.get("x", 0)), int(dict_val.get("y", 0))]
	return []

func _attach_online_resume_meta_to_archive(archive: Dictionary) -> Dictionary:
	return ArchiveClass.with_online_resume_meta(archive, _build_online_resume_meta_for_archive())

func is_resume_archive_room() -> bool:
	return room_mode == ROOM_MODE_RESUME_ARCHIVE

func _occupied_seat_indices() -> Array[int]:
	var out: Array[int] = []
	for key in _seat_slot_by_index.keys():
		out.append(int(key))
	out.sort()
	return out

func _get_slot(seat_index: int) -> Dictionary:
	if not _seat_slot_by_index.has(seat_index):
		return {}
	return Dictionary(_seat_slot_by_index.get(seat_index, {}))

func _set_slot(seat_index: int, slot: Dictionary) -> void:
	_seat_slot_by_index[seat_index] = Dictionary(slot).duplicate(true)

func _erase_slot(seat_index: int) -> void:
	if _seat_slot_by_index.has(seat_index):
		_seat_slot_by_index.erase(seat_index)

func _is_slot_connected(slot: Dictionary) -> bool:
	return int(slot.get("peer_id", 0)) > 0 and str(slot.get("seat_state", "")).strip_edges() == SEAT_CONNECTED

func _rebuild_runtime_views() -> void:
	_seat_profile_by_seat_index = {}
	_peer_id_by_seat_index = {}
	_player_profile_by_peer_id = {}
	_waiting_member_by_peer_id = {}
	_spectator_profile_by_peer_id = _spectator_profile_by_peer_id.duplicate(true)
	_seat_by_player_peer_id = {}
	_user_id_by_seat_index = {}
	player_id_by_peer_id = {}

	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var profile: Dictionary = Dictionary(slot.get("profile", {})).duplicate(true)
		var peer_id := int(slot.get("peer_id", 0))
		var user_id := str(slot.get("user_id", "")).strip_edges()

		_seat_profile_by_seat_index[seat_index] = profile
		if not user_id.is_empty():
			_user_id_by_seat_index[seat_index] = user_id
		if peer_id > 0:
			_peer_id_by_seat_index[seat_index] = peer_id
			_player_profile_by_peer_id[peer_id] = profile.duplicate(true)
			_seat_by_player_peer_id[peer_id] = seat_index

		var slot_state := str(slot.get("seat_state", "")).strip_edges()
		if peer_id > 0 and slot_state == SEAT_CONNECTED and slot_state != SEAT_FORFEITED and not _is_seat_forfeited_from_engine(seat_index):
			player_id_by_peer_id[peer_id] = seat_index

	for member in _waiting_member_by_user_id.values():
		if not (member is Dictionary):
			continue
		var waiting_member: Dictionary = Dictionary(member)
		var waiting_peer_id := int(waiting_member.get("peer_id", 0))
		if waiting_peer_id <= 0:
			continue
		_waiting_member_by_peer_id[waiting_peer_id] = waiting_member.duplicate(true)

	if _host_seat_index >= 0:
		host_peer_id = int(_peer_id_by_seat_index.get(_host_seat_index, 0))
	else:
		host_peer_id = 0
		for member2 in _waiting_member_by_user_id.values():
			if not (member2 is Dictionary):
				continue
			var waiting_host: Dictionary = Dictionary(member2)
			if str(waiting_host.get("role", "")).strip_edges() != "host":
				continue
			host_peer_id = int(waiting_host.get("peer_id", 0))
			break

func _find_waiting_user_id_by_peer(peer_id: int) -> String:
	for user_id_key in _waiting_member_by_user_id.keys():
		var user_id := str(user_id_key).strip_edges()
		if user_id.is_empty():
			continue
		var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id, {}))
		if int(member.get("peer_id", 0)) == int(peer_id):
			return user_id
	return ""

func get_waiting_user_id_for_peer(peer_id: int) -> String:
	return _find_waiting_user_id_by_peer(peer_id)

func get_waiting_member_peer_id(user_id: String) -> int:
	var uid := str(user_id).strip_edges()
	if uid.is_empty() or not _waiting_member_by_user_id.has(uid):
		return 0
	return int(Dictionary(_waiting_member_by_user_id.get(uid, {})).get("peer_id", 0))

func get_waiting_member_count() -> int:
	return _waiting_member_by_user_id.size()

func get_active_participant_count() -> int:
	return get_player_count() + get_waiting_member_count()

func is_password_required() -> bool:
	if join_policy != "password":
		return false
	return password_hash != _sha256_hex("")

func get_allow_spectators() -> bool:
	return bool(config.get("allow_spectators", true))

func update_config(patch: Dictionary) -> Result:
	if patch.is_empty():
		return Result.success()

	if patch.has("desired_player_count"):
		var v = patch.get("desired_player_count", null)
		if not (v is int or v is float):
			return Result.failure("desired_player_count 类型错误（期望 int）")
		var n := int(v)
		if n < get_player_count():
			return Result.failure("desired_player_count 不能小于当前人数: %d" % get_player_count())
		_desired_player_count = n
		config["desired_player_count"] = n

	for k in patch.keys():
		var key := str(k)
		if key == "desired_player_count":
			continue
		config[key] = patch.get(k, null)

	_touch()
	return Result.success()

func has_peer(peer_id: int) -> bool:
	return _player_profile_by_peer_id.has(peer_id) or _waiting_member_by_peer_id.has(peer_id) or _spectator_profile_by_peer_id.has(peer_id)

func get_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var peer_id := int(slot.get("peer_id", 0))
		if peer_id > 0:
			peer_ids.append(peer_id)
	var waiting_peer_ids: Array[int] = []
	for member in _waiting_member_by_user_id.values():
		if not (member is Dictionary):
			continue
		var waiting_peer_id := int(Dictionary(member).get("peer_id", 0))
		if waiting_peer_id > 0:
			waiting_peer_ids.append(waiting_peer_id)
	waiting_peer_ids.sort()
	peer_ids.append_array(waiting_peer_ids)
	var spectator_ids: Array[int] = []
	for k in _spectator_profile_by_peer_id.keys():
		spectator_ids.append(int(k))
	spectator_ids.sort()
	peer_ids.append_array(spectator_ids)
	return peer_ids

func get_player_count() -> int:
	return _seat_slot_by_index.size()

func get_connected_player_count() -> int:
	var count := 0
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		if _is_slot_connected(slot):
			count += 1
	return count

func is_full() -> bool:
	if _desired_player_count <= 0:
		return false
	if is_resume_archive_room():
		return get_active_participant_count() >= _desired_player_count
	return get_player_count() >= _desired_player_count

func is_empty() -> bool:
	return _seat_slot_by_index.is_empty() and _waiting_member_by_user_id.is_empty() and _spectator_profile_by_peer_id.is_empty()

func add_peer(peer_id: int, profile: Dictionary, token_generation: int = -1) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if is_full():
		return Result.failure("Room is full")

	var seat_index := _pick_seat_index()
	var role := "host" if _host_seat_index < 0 else "player"
	var user_id := str(profile.get("user_id", "")).strip_edges()
	var slot := _make_seat_slot(
		seat_index,
		role,
		user_id,
		profile,
		SEAT_CONNECTED,
		peer_id,
		_initial_generation(token_generation)
	)
	_set_slot(seat_index, slot)
	if role == "host":
		_host_seat_index = seat_index
	_rebuild_runtime_views()
	_touch()
	return Result.success()

func add_peer_at_seat(peer_id: int, profile: Dictionary, seat_index: int, token_generation: int = -1) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if is_full():
		return Result.failure("Room is full")

	var idx := int(seat_index)
	if idx < 0:
		return Result.failure("Invalid seat_index")
	if _desired_player_count > 0 and idx >= _desired_player_count:
		return Result.failure("seat_index out of range")
	if _seat_slot_by_index.has(idx):
		return Result.failure("Seat already occupied")

	var role := "host" if idx == _host_seat_index or _host_seat_index < 0 else "player"
	var user_id := str(profile.get("user_id", "")).strip_edges()
	var slot := _make_seat_slot(
		idx,
		role,
		user_id,
		profile,
		SEAT_CONNECTED,
		peer_id,
		_initial_generation(token_generation)
	)
	_set_slot(idx, slot)
	if role == "host":
		_host_seat_index = idx
	_rebuild_runtime_views()
	_touch()
	return Result.success()

func configure_resume_lobby(archive: Dictionary) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if archive.is_empty():
		return Result.failure("resume archive missing")
	_clear_prepared_resume_start_cache()
	room_mode = ROOM_MODE_RESUME_ARCHIVE
	config["room_mode"] = ROOM_MODE_RESUME_ARCHIVE
	var load_r: Result = ArchiveRecoveryClass.load_for_online_resume(Dictionary(archive).duplicate(true), false)
	if not load_r.ok:
		return Result.failure("resume archive load failed: %s" % load_r.error)
	var loaded_info: Dictionary = Dictionary(load_r.value) if load_r.value is Dictionary else {}
	_resume_lobby_archive = Dictionary(loaded_info.get("archive", archive)).duplicate(true)
	var inferred_player_count := _infer_resume_player_count_from_archive(_resume_lobby_archive)
	if inferred_player_count <= 0:
		return Result.failure("resume archive player_count invalid")
	_desired_player_count = inferred_player_count
	config["desired_player_count"] = inferred_player_count
	_touch()
	return Result.success().with_warnings(load_r.warnings)

func get_resume_lobby_archive() -> Dictionary:
	return _resume_lobby_archive.duplicate(true)

func build_effective_resume_start_archive() -> Result:
	var prepared_r: Result = _prepare_effective_resume_start_engine()
	if not prepared_r.ok:
		return prepared_r
	var prepared_info: Dictionary = Dictionary(prepared_r.value) if prepared_r.value is Dictionary else {}
	var preview_engine = prepared_info.get("engine", null)
	if preview_engine == null or not is_instance_valid(preview_engine):
		return Result.failure("resume start engine missing")

	if _prepared_resume_start_archive.is_empty():
		var archive_r: Result = preview_engine.create_archive()
		if not archive_r.ok:
			return Result.failure("create_archive failed: %s" % archive_r.error)
		_prepared_resume_start_archive = Dictionary(archive_r.value).duplicate(true)
		if _prepared_resume_start_final_hash.is_empty():
			_prepared_resume_start_final_hash = str(_prepared_resume_start_archive.get("final_hash", "")).strip_edges()

	var archive: Dictionary = _prepared_resume_start_archive.duplicate(true)
	return Result.success({
		"archive": archive,
		"history_size": int(prepared_info.get("history_size", preview_engine.command_history.size())),
		"current_index": int(prepared_info.get("current_index", preview_engine.current_command_index)),
		"final_hash": _prepared_resume_start_final_hash,
	}).with_warnings(prepared_r.warnings)

func build_full_authority_archive_export(allow_ended_terminal_export: bool = false) -> Result:
	if status != STATUS_IN_GAME and not (allow_ended_terminal_export and status == STATUS_ENDED):
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")
	var archive_r: Result = game_engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)
	var archive: Dictionary = _attach_online_resume_meta_to_archive(Dictionary(archive_r.value).duplicate(true))
	var state = game_engine.get_state() if game_engine.has_method("get_state") else null
	var final_hash := str(state.compute_hash()) if state != null and state.has_method("compute_hash") else str(archive.get("final_hash", "")).strip_edges()
	return Result.success({
		"room_code": str(room_code).strip_edges().to_upper(),
		"archive": archive,
		"history_size": int(game_engine.command_history.size()),
		"current_index": int(game_engine.current_command_index),
		"final_hash": final_hash,
	})

func add_waiting_member(peer_id: int, profile: Dictionary, role: String = "player", token_generation: int = -1) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if not is_resume_archive_room():
		return Result.failure("Room is not a resume lobby")

	var user_id := str(profile.get("user_id", "")).strip_edges()
	if user_id.is_empty():
		return Result.failure("user_id required for waiting member")

	var normalized_role := "host" if str(role).strip_edges() == "host" else "player"
	var existing_waiting: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id, {}))
	var assigned_seat_index := find_seat_index_for_user_id(user_id)
	if assigned_seat_index >= 0:
		var reclaim_r: Result = reclaim_peer_at_seat(peer_id, profile, assigned_seat_index, user_id, token_generation)
		if not reclaim_r.ok:
			return reclaim_r
		var reclaim_payload: Dictionary = Dictionary(reclaim_r.value) if reclaim_r.value is Dictionary else {}
		reclaim_payload["auto_assigned"] = true
		reclaim_payload["assigned_seat_index"] = assigned_seat_index
		return Result.success(reclaim_payload)
	if existing_waiting.is_empty() and is_full():
		return Result.failure("Room is full")

	var replaced_peer_id := int(existing_waiting.get("peer_id", 0))
	var generation := _initial_generation(token_generation)
	if not existing_waiting.is_empty():
		var generation_r: Result = _consume_generation(int(existing_waiting.get("generation", 1)), token_generation)
		if not generation_r.ok:
			return generation_r
		generation = int(generation_r.value)
	_waiting_member_by_user_id[user_id] = _make_waiting_member(
		user_id,
		normalized_role if existing_waiting.is_empty() else str(existing_waiting.get("role", normalized_role)).strip_edges(),
		profile,
		peer_id,
		"active",
		generation
	)
	var expected_seat_index := _find_resume_expected_seat_index_for_user_id(user_id)
	if expected_seat_index >= 0 and not _seat_slot_by_index.has(expected_seat_index):
		var assign_r: Result = assign_waiting_member_to_seat(user_id, expected_seat_index)
		if assign_r.ok:
			return Result.success({
				"replaced_peer_id": replaced_peer_id,
				"auto_assigned": true,
				"assigned_seat_index": expected_seat_index,
			})
	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"replaced_peer_id": replaced_peer_id,
	})

func assign_waiting_member_to_seat(user_id: String, seat_index: int) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if not is_resume_archive_room():
		return Result.failure("Room is not a resume lobby")

	var uid := str(user_id).strip_edges()
	if uid.is_empty():
		return Result.failure("user_id missing")
	if not _waiting_member_by_user_id.has(uid):
		return Result.failure("Waiting member not found")

	var idx := int(seat_index)
	if idx < 0:
		return Result.failure("Invalid seat_index")
	if _desired_player_count > 0 and idx >= _desired_player_count:
		return Result.failure("seat_index out of range")
	if _seat_slot_by_index.has(idx):
		return Result.failure("Seat already occupied")

	var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(uid, {}))
	var role := str(member.get("role", "player")).strip_edges()
	var slot := _make_seat_slot(
		idx,
		role,
		uid,
		Dictionary(member.get("profile", {})).duplicate(true),
		SEAT_CONNECTED if int(member.get("peer_id", 0)) > 0 else SEAT_RECONNECTING,
		int(member.get("peer_id", 0)),
		int(member.get("generation", 1))
	)
	_set_slot(idx, slot)
	if role == "host":
		_host_seat_index = idx
	_waiting_member_by_user_id.erase(uid)
	_rebuild_runtime_views()
	_touch()
	return Result.success()

func unassign_seat_to_waiting(seat_index: int) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if not is_resume_archive_room():
		return Result.failure("Room is not a resume lobby")

	var idx := int(seat_index)
	if idx < 0 or not _seat_slot_by_index.has(idx):
		return Result.failure("Seat not found")

	var slot := _get_slot(idx)
	var user_id := str(slot.get("user_id", "")).strip_edges()
	if user_id.is_empty():
		return Result.failure("Seat user_id missing")
	var member := _make_waiting_member(
		user_id,
		str(slot.get("role", "player")).strip_edges(),
		Dictionary(slot.get("profile", {})).duplicate(true),
		int(slot.get("peer_id", 0)),
		"active" if int(slot.get("peer_id", 0)) > 0 else "reconnecting",
		int(slot.get("generation", 1))
	)
	_waiting_member_by_user_id[user_id] = member
	_erase_slot(idx)
	if idx == _host_seat_index:
		_host_seat_index = -1
	_rebuild_runtime_views()
	_touch()
	return Result.success()

func reclaim_peer_at_seat(
	peer_id: int,
	profile: Dictionary,
	seat_index: int,
	user_id: String = "",
	token_generation: int = -1
) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")

	var idx := int(seat_index)
	if idx < 0:
		return Result.failure("Invalid seat_index")
	if not _seat_slot_by_index.has(idx):
		return Result.failure("Seat not found")

	var slot := _get_slot(idx)
	var uid := str(user_id).strip_edges()
	var existing_uid := str(slot.get("user_id", "")).strip_edges()
	if not uid.is_empty() and not existing_uid.is_empty() and existing_uid != uid:
		return Result.failure("user_id mismatch for seat")
	if existing_uid.is_empty():
		existing_uid = uid
		slot["user_id"] = uid
	if existing_uid.is_empty():
		return Result.failure("user_id required for reclaim")

	var generation_r: Result = _consume_generation(int(slot.get("generation", 1)), token_generation)
	if not generation_r.ok:
		return generation_r
	var replaced_peer_id := int(slot.get("peer_id", 0))
	if replaced_peer_id > 0 and replaced_peer_id != peer_id:
		_evict_connected_player_peer(replaced_peer_id)
	slot["profile"] = Dictionary(profile).duplicate(true)
	slot["peer_id"] = peer_id
	slot["seat_state"] = SEAT_CONNECTED
	slot["generation"] = int(generation_r.value)
	_set_slot(idx, slot)
	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"replaced_peer_id": replaced_peer_id,
	})

func reconnect_player(
	peer_id: int,
	profile: Dictionary,
	seat_index: int,
	user_id: String = "",
	restore_host: bool = false,
	token_generation: int = -1
) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")

	var idx := int(seat_index)
	if idx < 0:
		return Result.failure("Invalid seat_index")
	if not _seat_slot_by_index.has(idx):
		return Result.failure("Seat not found")

	_sync_seat_states_from_engine()
	var slot := _get_slot(idx)
	if str(slot.get("seat_state", "")).strip_edges() == SEAT_FORFEITED:
		return Result.failure("Seat forfeited")

	var uid := str(user_id).strip_edges()
	var existing_uid := str(slot.get("user_id", "")).strip_edges()
	if not uid.is_empty() and not existing_uid.is_empty() and existing_uid != uid:
		return Result.failure("user_id mismatch for seat")
	if existing_uid.is_empty():
		existing_uid = uid
		slot["user_id"] = uid
	if existing_uid.is_empty():
		return Result.failure("user_id required for reconnect")

	var generation_r: Result = _consume_generation(int(slot.get("generation", 1)), token_generation)
	if not generation_r.ok:
		return generation_r
	var replaced_peer_id := int(slot.get("peer_id", 0))
	if replaced_peer_id > 0 and replaced_peer_id != peer_id:
		_evict_connected_player_peer(replaced_peer_id)
	slot["profile"] = Dictionary(profile).duplicate(true)
	slot["peer_id"] = peer_id
	slot["seat_state"] = SEAT_CONNECTED
	slot["generation"] = int(generation_r.value)
	if restore_host:
		slot["role"] = "host"
		_host_seat_index = idx
	_set_slot(idx, slot)
	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"replaced_peer_id": replaced_peer_id,
	})

func _evict_connected_player_peer(peer_id: int) -> void:
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		if int(slot.get("peer_id", 0)) != peer_id:
			continue
		slot["peer_id"] = 0
		if str(slot.get("seat_state", "")).strip_edges() == SEAT_CONNECTED:
			slot["seat_state"] = SEAT_RECONNECTING
		_set_slot(seat_index, slot)
		break
	_rebuild_runtime_views()

func add_spectator(peer_id: int, profile: Dictionary) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if not get_allow_spectators():
		return Result.failure("Spectators not allowed")

	var spectator_profile: Dictionary = Dictionary(profile).duplicate(true)
	var user_id := str(spectator_profile.get("user_id", "")).strip_edges()
	var replaced_peer_id := 0
	if not user_id.is_empty():
		var spectator_peer_ids: Array[int] = []
		for peer_key in _spectator_profile_by_peer_id.keys():
			spectator_peer_ids.append(int(peer_key))
		spectator_peer_ids.sort()
		for existing_peer_id in spectator_peer_ids:
			if existing_peer_id == peer_id:
				continue
			var existing_profile: Dictionary = Dictionary(_spectator_profile_by_peer_id.get(existing_peer_id, {}))
			if str(existing_profile.get("user_id", "")).strip_edges() != user_id:
				continue
			replaced_peer_id = existing_peer_id
			_spectator_profile_by_peer_id.erase(existing_peer_id)
			break
	_spectator_profile_by_peer_id[peer_id] = spectator_profile
	_touch()
	return Result.success({
		"replaced_peer_id": replaced_peer_id,
	})

func remove_peer(peer_id: int) -> Result:
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
		_touch()
		return Result.success({
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	var waiting_user_id := _find_waiting_user_id_by_peer(peer_id)
	if not waiting_user_id.is_empty():
		var waiting_member: Dictionary = Dictionary(_waiting_member_by_user_id.get(waiting_user_id, {}))
		var host_changed_waiting := str(waiting_member.get("role", "")).strip_edges() == "host"
		_waiting_member_by_user_id.erase(waiting_user_id)
		if host_changed_waiting:
			_promote_new_host_after_lobby_leave()
		_rebuild_runtime_views()
		_touch()
		return Result.success({
			"host_changed": host_changed_waiting,
			"host_peer_id": host_peer_id,
		})

	if not _seat_by_player_peer_id.has(peer_id):
		return Result.failure("Peer not in room")

	var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
	if seat_index < 0 or not _seat_slot_by_index.has(seat_index):
		return Result.failure("Seat not found")

	var slot := _get_slot(seat_index)
	var host_changed := false
	if status == STATUS_LOBBY or status == STATUS_STARTING:
		_erase_slot(seat_index)
		if seat_index == _host_seat_index:
			_promote_new_host_after_lobby_leave()
			host_changed = true
	else:
		_sync_seat_states_from_engine()
		slot["peer_id"] = 0
		if _is_seat_forfeited_from_engine(seat_index):
			slot["seat_state"] = SEAT_FORFEITED
		else:
			slot["seat_state"] = SEAT_RECONNECTING
		_set_slot(seat_index, slot)

	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func disconnect_peer(peer_id: int) -> Result:
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
		_touch()
		return Result.success({
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	var waiting_user_id := _find_waiting_user_id_by_peer(peer_id)
	if not waiting_user_id.is_empty():
		var waiting_member: Dictionary = Dictionary(_waiting_member_by_user_id.get(waiting_user_id, {}))
		waiting_member["peer_id"] = 0
		waiting_member["member_status"] = "reconnecting"
		_waiting_member_by_user_id[waiting_user_id] = waiting_member
		_rebuild_runtime_views()
		_touch()
		return Result.success({
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	if not _seat_by_player_peer_id.has(peer_id):
		return Result.failure("Peer not in room")

	var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
	if seat_index < 0 or not _seat_slot_by_index.has(seat_index):
		return Result.failure("Seat not found")

	_sync_seat_states_from_engine()
	var slot := _get_slot(seat_index)
	slot["peer_id"] = 0
	if _is_seat_forfeited_from_engine(seat_index):
		slot["seat_state"] = SEAT_FORFEITED
	else:
		slot["seat_state"] = SEAT_RECONNECTING
	_set_slot(seat_index, slot)

	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"host_changed": seat_index == _host_seat_index,
		"host_peer_id": host_peer_id,
	})

func release_reconnecting_seat(seat_index: int) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")

	var idx := int(seat_index)
	if idx < 0 or not _seat_slot_by_index.has(idx):
		return Result.failure("Seat not found")

	var slot := _get_slot(idx)
	var slot_state := str(slot.get("seat_state", "")).strip_edges()
	if int(slot.get("peer_id", 0)) > 0 or slot_state != SEAT_RECONNECTING:
		return Result.success({
			"released": false,
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	var host_changed := idx == _host_seat_index
	_erase_slot(idx)
	if host_changed:
		_promote_new_host_after_lobby_leave()

	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"released": true,
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func release_reconnecting_waiting_member(user_id: String) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")

	var uid := str(user_id).strip_edges()
	if uid.is_empty() or not _waiting_member_by_user_id.has(uid):
		return Result.success({
			"released": false,
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(uid, {}))
	if int(member.get("peer_id", 0)) > 0 or str(member.get("member_status", "active")).strip_edges() != "reconnecting":
		return Result.success({
			"released": false,
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	var host_changed := str(member.get("role", "")).strip_edges() == "host"
	_waiting_member_by_user_id.erase(uid)
	if host_changed:
		_promote_new_host_after_lobby_leave()

	_rebuild_runtime_views()
	_touch()
	return Result.success({
		"released": true,
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func update_peer_profile(peer_id: int, profile: Dictionary) -> Result:
	if profile == null:
		return Result.failure("Invalid profile")
	var normalized := {
		"name": str(profile.get("name", "玩家")).strip_edges(),
		"color_index": int(profile.get("color_index", 0)),
		"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
	}
	var user_id := str(profile.get("user_id", "")).strip_edges()
	if not user_id.is_empty():
		normalized["user_id"] = user_id
	if str(normalized.get("name", "")).is_empty():
		normalized["name"] = "玩家"

	if _seat_by_player_peer_id.has(peer_id):
		var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
		if seat_index >= 0 and _seat_slot_by_index.has(seat_index):
			var slot := _get_slot(seat_index)
			slot["profile"] = normalized.duplicate(true)
			_set_slot(seat_index, slot)
			_rebuild_runtime_views()
			_touch()
			return Result.success()

	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id[peer_id] = normalized.duplicate(true)
		_touch()
		return Result.success()

	var waiting_user_id := _find_waiting_user_id_by_peer(peer_id)
	if not waiting_user_id.is_empty():
		var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(waiting_user_id, {}))
		member["profile"] = normalized.duplicate(true)
		_waiting_member_by_user_id[waiting_user_id] = member
		_rebuild_runtime_views()
		_touch()
		return Result.success()

	return Result.failure("Peer not in room")

func set_player_logo_by_seat(seat_index: int, restaurant_logo_id: int) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if seat_index < 0 or not _seat_slot_by_index.has(seat_index):
		return Result.failure("Seat not found")

	var logo_limit := DEFAULT_RESTAURANT_LOGO_COUNT
	var logo_id := int(restaurant_logo_id)
	if logo_id < -1 or logo_id >= maxi(1, logo_limit):
		return Result.failure("restaurant_logo_id out of range")

	var slot := _get_slot(seat_index)
	var seat_profile: Dictionary = Dictionary(slot.get("profile", {}))
	if seat_profile.is_empty():
		return Result.failure("Seat profile missing")
	seat_profile["restaurant_logo_id"] = logo_id
	slot["profile"] = seat_profile.duplicate(true)
	_set_slot(seat_index, slot)

	_rebuild_runtime_views()
	_touch()
	return Result.success()

func to_room_state_dict() -> Dictionary:
	_sync_seat_states_from_engine()
	var state := {
		"room_code": room_code,
		"room_mode": room_mode,
		"host_peer_id": host_peer_id,
		"host_seat_index": _host_seat_index,
		"players": _build_players_array(),
		"waiting_members": _build_waiting_members_array(),
		"spectators": _build_spectators_array(),
		"config": config.duplicate(true),
		"password_required": is_password_required(),
		"allow_spectators": get_allow_spectators(),
		"status": status,
	}
	var bootstrap := get_pending_start_summary()
	if not bootstrap.is_empty():
		state["bootstrap"] = bootstrap
	if _rollback_proposal_store.has_pending():
		state["rollback_proposal"] = _rollback_proposal_store.public_payload()
	return state

func to_room_state_dict_for_peer(peer_id: int) -> Dictionary:
	var state := to_room_state_dict()
	state["self_seat_index"] = get_seat_index_for_peer(peer_id)
	state["self_role"] = get_role_for_peer(peer_id)
	if state.get("rollback_proposal", null) is Dictionary:
		var proposal: Dictionary = Dictionary(state.get("rollback_proposal", {})).duplicate(true)
		var self_pid := int(player_id_by_peer_id.get(peer_id, player_id_by_peer_id.get(str(peer_id), -1)))
		proposal["self_player_id"] = self_pid
		proposal["self_vote"] = bool(Dictionary(proposal.get("votes", {})).get(self_pid, false))
		state["rollback_proposal"] = proposal
	if state.get("bootstrap", null) is Dictionary:
		var bootstrap: Dictionary = Dictionary(state.get("bootstrap", {})).duplicate(true)
		bootstrap["self_ready"] = _start_session_state.is_peer_ready(peer_id)
		state["bootstrap"] = bootstrap
	return state

func to_room_summary_dict() -> Dictionary:
	_sync_seat_states_from_engine()
	var cfg: Dictionary = config.duplicate(true)
	var seed_mode := str(cfg.get("seed_mode", "")).strip_edges()
	var seed := int(cfg.get("seed", 0))
	var mods_count := 0
	var mv = cfg.get("enabled_modules_v2", null)
	if mv is Array:
		mods_count = Array(mv).size()

	var host_name := ""
	var host_profile: Dictionary = {}
	if _host_seat_index >= 0 and _seat_slot_by_index.has(_host_seat_index):
		host_profile = Dictionary(_get_slot(_host_seat_index).get("profile", {}))
	elif not owner_user_id.is_empty() and _waiting_member_by_user_id.has(owner_user_id):
		host_profile = Dictionary(Dictionary(_waiting_member_by_user_id.get(owner_user_id, {})).get("profile", {}))
	if not host_profile.is_empty():
		host_name = str(host_profile.get("name", ""))

	var summary := {
		"room_code": room_code,
		"status": status,
		"room_mode": room_mode,
		"desired_player_count": int(cfg.get("desired_player_count", 0)),
		"player_count": get_active_participant_count() if is_resume_archive_room() and status == STATUS_LOBBY else get_player_count(),
		"connected_player_count": get_connected_player_count(),
		"spectator_count": _spectator_profile_by_peer_id.size(),
		"password_required": is_password_required(),
		"allow_spectators": get_allow_spectators(),
		"updated_at_ms": updated_at_ms,
		"host_name": host_name,
		"config_digest": {
			"seed_mode": seed_mode,
			"seed": seed,
			"enabled_modules_count": mods_count,
		},
	}
	var bootstrap := get_pending_start_summary()
	if not bootstrap.is_empty():
		summary["bootstrap"] = bootstrap
	return summary

func build_player_id_by_peer_id() -> Dictionary:
	var out: Dictionary = {}
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var peer_id := int(slot.get("peer_id", 0))
		if peer_id <= 0:
			continue
		if str(slot.get("seat_state", "")).strip_edges() != SEAT_CONNECTED:
			continue
		if _is_seat_forfeited_from_engine(seat_index):
			continue
		out[peer_id] = seat_index
	return out

func get_player_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var peer_id := int(slot.get("peer_id", 0))
		if peer_id > 0:
			peer_ids.append(peer_id)
	return peer_ids

func can_start_game() -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")

	var desired := int(config.get("desired_player_count", 0))
	if desired <= 0:
		return Result.failure("desired_player_count not set")
	if is_resume_archive_room():
		if _resume_lobby_archive.is_empty():
			return Result.failure("resume archive missing")
		if get_waiting_member_count() > 0:
			return Result.failure("waiting members not assigned")
		if get_player_count() != desired:
			return Result.failure("players not ready: have=%d need=%d" % [get_player_count(), desired])
		if get_connected_player_count() != desired:
			return Result.failure("players not connected: have=%d need=%d" % [get_connected_player_count(), desired])
		for seat_index in range(desired):
			if not _seat_slot_by_index.has(seat_index):
				return Result.failure("seat %d missing" % seat_index)
			var slot2 := _get_slot(seat_index)
			if not _is_slot_connected(slot2):
				return Result.failure("seat %d not connected" % seat_index)
		return Result.success()
	if get_player_count() != desired:
		return Result.failure("players not ready: have=%d need=%d" % [get_player_count(), desired])
	if get_connected_player_count() != desired:
		return Result.failure("players not connected: have=%d need=%d" % [get_connected_player_count(), desired])
	for seat_index in range(desired):
		if not _seat_slot_by_index.has(seat_index):
			return Result.failure("seat %d missing" % seat_index)
		var slot := _get_slot(seat_index)
		if not _is_slot_connected(slot):
			return Result.failure("seat %d not connected" % seat_index)

	var seed_mode := str(config.get("seed_mode", "random")).strip_edges()
	if seed_mode != "random" and seed_mode != "fixed":
		return Result.failure("invalid seed_mode: %s" % seed_mode)
	if seed_mode == "fixed" and not config.has("seed"):
		return Result.failure("seed required when seed_mode=fixed")

	var base_dir := str(config.get("modules_v2_base_dir", "")).strip_edges()
	if base_dir.is_empty():
		return Result.failure("modules_v2_base_dir is empty")

	var mods_val = config.get("enabled_modules_v2", null)
	if mods_val != null and not (mods_val is Array):
		return Result.failure("enabled_modules_v2 type invalid (expected Array)")

	return Result.success()

func _build_start_game_engine_and_payload() -> Result:
	var engine = GameEngineClass.new()
	if is_resume_archive_room():
		var prepared_r: Result = _prepare_effective_resume_start_engine()
		if not prepared_r.ok:
			return Result.failure("构造恢复房起局存档失败: %s" % prepared_r.error)
		var prepared_val = prepared_r.value
		if not (prepared_val is Dictionary):
			return Result.failure("构造恢复房起局存档失败：返回值类型错误")
		var prepared_info: Dictionary = prepared_val
		engine = prepared_info.get("engine", null)
		if engine == null or not is_instance_valid(engine):
			return Result.failure("构造恢复房起局存档失败：engine 为空")
	else:
		var player_count := int(config.get("desired_player_count", 0))
		var seed_mode := str(config.get("seed_mode", "random")).strip_edges()
		var seed := int(config.get("seed", 0))
		if seed_mode == "random":
			if seed <= 0:
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				seed = int(rng.randi())
				config["seed"] = seed

		var enabled_modules: Array[String] = []
		var mods_val = config.get("enabled_modules_v2", null)
		if mods_val is Array:
			for it in Array(mods_val):
				var s := str(it).strip_edges()
				if s.is_empty():
					continue
				enabled_modules.append(s)

		var base_dir := str(config.get("modules_v2_base_dir", "")).strip_edges()

		var logo_choices: Array[int] = []
		for seat_index in range(player_count):
			var slot: Dictionary = _get_slot(seat_index)
			var profile: Dictionary = Dictionary(slot.get("profile", {}))
			logo_choices.append(int(profile.get("restaurant_logo_id", -1)))
		config["restaurant_logo_choices_by_player"] = logo_choices
		var reserve_card_choices: Array[int] = []

		var config_overrides_val = config.get("game_config_overrides", null)
		if config_overrides_val != null:
			if not (config_overrides_val is Dictionary):
				return Result.failure("game_config_overrides 必须是 Dictionary")
			engine.set_game_config_overrides(Dictionary(config_overrides_val).duplicate(true))
		var option_overrides_val = config.get("game_option_overrides", null)
		if option_overrides_val != null:
			if not (option_overrides_val is Dictionary):
				return Result.failure("game_option_overrides 必须是 Dictionary")
			engine.set_game_option_overrides(Dictionary(option_overrides_val).duplicate(true))

		var init_r: Result = engine.initialize(player_count, seed, enabled_modules, base_dir, reserve_card_choices, logo_choices)
		if not init_r.ok:
			return Result.failure("GameEngine.initialize failed: %s" % init_r.error)

	var online_prepare_r := _enable_online_settlement_confirm_on_engine(engine)
	if not online_prepare_r.ok:
		return Result.failure("online settlement confirm prepare failed: %s" % online_prepare_r.error)
	return Result.success({
		"engine": engine,
		"payload": {
			"player_id_by_peer_id": build_player_id_by_peer_id(),
			"config": config.duplicate(true),
		},
	})

func _commit_started_engine(engine) -> Result:
	game_engine = engine
	status = STATUS_IN_GAME
	started_at_iso = Time.get_datetime_string_from_system()
	ended_at_iso = ""
	started_at_unix_sec = int(Time.get_unix_time_from_system())
	ended_at_unix_sec = 0
	match_finalize_in_flight = false
	match_finalize_reported = false
	finalized_match_id = ""
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		if int(slot.get("peer_id", 0)) > 0:
			slot["seat_state"] = SEAT_CONNECTED
		else:
			slot["seat_state"] = SEAT_RECONNECTING
		_set_slot(seat_index, slot)
	_waiting_member_by_user_id.clear()
	_clear_prepared_resume_start_cache()
	_rebuild_runtime_views()
	_touch()
	var checkpoint_r: Result = _reset_recovery_store_from_current_engine("start_game")
	if not checkpoint_r.ok:
		return Result.failure("初始化 recovery store 失败: %s" % checkpoint_r.error)
	_resume_lobby_archive = {}
	return Result.success()

func prepare_start_game() -> Result:
	if not has_pending_start_session():
		var begin_r: Result = begin_start_game_session("")
		if not begin_r.ok:
			return begin_r
	elif status != STATUS_STARTING:
		return Result.failure("Room is not in Starting")

	if _start_session_state.has_prepared_payload():
		return Result.success(_start_session_state.get_payload())

	var build_r: Result = _build_start_game_engine_and_payload()
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("start_game build result type invalid")

	var build_info: Dictionary = build_r.value
	_start_session_state.set_prepared(
		build_info.get("engine", null),
		Dictionary(build_info.get("payload", {})),
		"waiting_for_players"
	)
	_touch()
	return Result.success(_start_session_state.get_payload())

func commit_prepared_start_game() -> Result:
	if not has_pending_start_session():
		return Result.failure("pending start session missing")
	var pending_engine = _start_session_state.get_prepared_engine()
	if pending_engine == null or not is_instance_valid(pending_engine):
		return Result.failure("pending start engine missing")

	var payload: Dictionary = _start_session_state.get_payload()
	var commit_r: Result = _commit_started_engine(pending_engine)
	_clear_pending_start_session()
	if not commit_r.ok:
		return commit_r
	return Result.success(payload)

func start_game() -> Result:
	var begin_r: Result = begin_start_game_session("")
	if not begin_r.ok:
		return begin_r
	var prepare_r: Result = prepare_start_game()
	if not prepare_r.ok:
		abort_prepared_start_game(prepare_r.error)
		return prepare_r
	var commit_r: Result = commit_prepared_start_game()
	if not commit_r.ok:
		abort_prepared_start_game(commit_r.error)
		return commit_r
	return commit_r

func rollback_to_command_index(
	target_index: int,
	include_archive: bool = true,
	player_id: int = -1,
	reason: String = "rollback"
) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")

	var target := int(target_index)
	var before_index := int(game_engine.current_command_index)
	if target < -1:
		return Result.failure("target_index invalid: %d" % target)
	if target > before_index:
		return Result.failure("target_index is in the future: target=%d current=%d" % [target, before_index])
	if target >= int(game_engine.command_history.size()):
		return Result.failure("target_index outside history: target=%d history=%d" % [target, int(game_engine.command_history.size())])

	if target < before_index:
		var rewind_r: Result = game_engine.rewind_to_command(target)
		if not rewind_r.ok:
			return Result.failure("rewind_to_command failed: %s" % rewind_r.error)
		if game_engine.has_method("truncate_future_history"):
			game_engine.truncate_future_history()

	var state_hash := ""
	var state = game_engine.get_state()
	if state != null:
		state_hash = str(state.compute_hash())
	var resolved_player_id := int(player_id)
	if resolved_player_id < 0 and state != null:
		resolved_player_id = int(state.get_current_player_id())

	var out := {
		"target_index": target,
		"before_index": before_index,
		"current_index": int(game_engine.current_command_index),
		"history_size": int(game_engine.command_history.size()),
		"state_hash": state_hash,
		"noop": target >= before_index,
		"player_id": resolved_player_id,
		"reason": str(reason).strip_edges(),
	}

	if include_archive:
		var archive_r: Result = game_engine.create_archive()
		if not archive_r.ok:
			return Result.failure("create_archive failed: %s" % archive_r.error)
		out["archive"] = Dictionary(archive_r.value).duplicate(true)

	var checkpoint_r: Result = _reset_recovery_store_from_current_engine(str(reason).strip_edges() if not str(reason).strip_edges().is_empty() else "rollback")
	if not checkpoint_r.ok:
		return Result.failure("reset recovery store failed: %s" % checkpoint_r.error)
	_rollback_proposal_store.clear()
	_touch()
	return Result.success(out)

func rewind_to_current_player_turn_start(include_archive: bool = true, player_id: int = -1) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")
	if not game_engine.has_method("find_current_player_turn_start_command_index"):
		return Result.failure("Room engine missing turn-start query")

	var idx_r: Result = game_engine.find_current_player_turn_start_command_index(player_id)
	if not idx_r.ok:
		return Result.failure("find_current_player_turn_start_command_index failed: %s" % idx_r.error)

	return rollback_to_command_index(int(idx_r.value), include_archive, player_id, "rewind_turn_start")

func rollback_last_command_for_player(include_archive: bool = true, player_id: int = -1) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")

	var before_index := int(game_engine.current_command_index)
	if before_index < 0:
		return Result.failure("No command to rollback")
	if before_index >= int(game_engine.command_history.size()):
		return Result.failure("current_index outside history: current=%d history=%d" % [before_index, int(game_engine.command_history.size())])

	var cmd_val = game_engine.command_history[before_index]
	if not (cmd_val is Command):
		return Result.failure("last command type invalid")
	var cmd: Command = cmd_val
	var actor_id := int(cmd.actor)
	var requested_player_id := int(player_id)
	if requested_player_id >= 0 and actor_id != requested_player_id:
		return Result.failure("Last command belongs to player %d, not player %d" % [actor_id, requested_player_id])

	var rollback_r: Result = rollback_to_command_index(before_index - 1, include_archive, requested_player_id, "undo_last_command")
	if not rollback_r.ok:
		return rollback_r
	if rollback_r.value is Dictionary:
		var out: Dictionary = Dictionary(rollback_r.value).duplicate(true)
		out["rolled_back_index"] = before_index
		out["rolled_back_actor"] = actor_id
		out["rolled_back_action_id"] = str(cmd.action_id)
		rollback_r.value = out
	return rollback_r

func create_rollback_proposal(
	proposal_id: String,
	proposer_peer_id: int,
	proposer_player_id: int,
	target_index: int,
	reason: String = "proposal_rollback"
) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")
	if _rollback_proposal_store.has_pending():
		return Result.failure("Rollback proposal already pending")

	var target := int(target_index)
	var before_index := int(game_engine.current_command_index)
	if target < -1:
		return Result.failure("target_index invalid: %d" % target)
	if target >= before_index:
		return Result.failure("target_index must be before current index: target=%d current=%d" % [target, before_index])
	if target >= int(game_engine.command_history.size()):
		return Result.failure("target_index outside history: target=%d history=%d" % [target, int(game_engine.command_history.size())])

	var proposer_pid := int(proposer_player_id)
	var required: Array[int] = []
	for peer_id in get_player_peer_ids():
		var pid := int(player_id_by_peer_id.get(peer_id, player_id_by_peer_id.get(str(peer_id), -1)))
		if pid < 0 or pid == proposer_pid:
			continue
		if not required.has(pid):
			required.append(pid)
	required.sort()

	var create_r: Result = _rollback_proposal_store.create(
		proposal_id,
		proposer_peer_id,
		proposer_pid,
		target,
		before_index,
		int(game_engine.command_history.size()),
		required,
		reason
	)
	if not create_r.ok:
		return create_r
	_touch()
	return create_r

func vote_rollback_proposal(proposal_id: String, voter_player_id: int, approve: bool) -> Result:
	var vote_r: Result = _rollback_proposal_store.vote(proposal_id, voter_player_id, approve)
	if vote_r.ok:
		_touch()
	return vote_r

func consume_pending_rollback_proposal() -> Dictionary:
	var out := _rollback_proposal_store.consume()
	if not out.is_empty():
		_touch()
	return out

func clear_pending_rollback_proposal() -> void:
	if _rollback_proposal_store.clear():
		_touch()

func has_pending_rollback_proposal() -> bool:
	return _rollback_proposal_store.has_pending()

func get_seat_index_for_peer(peer_id: int) -> int:
	if _seat_by_player_peer_id.has(peer_id):
		return int(_seat_by_player_peer_id.get(peer_id, -1))
	return -1

func get_role_for_peer(peer_id: int) -> String:
	if _spectator_profile_by_peer_id.has(peer_id):
		return "spectator"
	if _waiting_member_by_peer_id.has(peer_id):
		return str(Dictionary(_waiting_member_by_peer_id.get(peer_id, {})).get("role", "player")).strip_edges()
	var seat_index := get_seat_index_for_peer(peer_id)
	if seat_index < 0:
		return ""
	var slot := _get_slot(seat_index)
	return str(slot.get("role", "player")).strip_edges()

func get_seat_state(seat_index: int) -> String:
	if not _seat_slot_by_index.has(seat_index):
		return ""
	return str(_get_slot(seat_index).get("seat_state", "")).strip_edges()

func _sha256_hex(secret: String) -> String:
	if secret.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(secret.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _pick_seat_index() -> int:
	var max_seats := maxi(1, _desired_player_count)
	for i in range(max_seats):
		if not _seat_slot_by_index.has(i):
			return i
	return max_seats

func _pick_new_host_peer_id() -> int:
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		var peer_id := int(slot.get("peer_id", 0))
		if peer_id > 0:
			return peer_id
	return 0

func _promote_new_host_after_lobby_leave() -> void:
	_host_seat_index = -1
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		slot["role"] = "player"
		_set_slot(seat_index, slot)
	for user_id_key in _waiting_member_by_user_id.keys():
		var user_id := str(user_id_key).strip_edges()
		if user_id.is_empty():
			continue
		var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id, {}))
		member["role"] = "player"
		_waiting_member_by_user_id[user_id] = member
	for seat_index2 in _occupied_seat_indices():
		var slot2 := _get_slot(seat_index2)
		slot2["role"] = "host"
		_set_slot(seat_index2, slot2)
		_host_seat_index = seat_index2
		owner_user_id = str(slot2.get("user_id", "")).strip_edges()
		return
	var waiting_user_ids: Array[String] = []
	for user_id_key2 in _waiting_member_by_user_id.keys():
		var user_id2 := str(user_id_key2).strip_edges()
		if user_id2.is_empty():
			continue
		waiting_user_ids.append(user_id2)
	waiting_user_ids.sort()
	for user_id3 in waiting_user_ids:
		var waiting_member: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id3, {}))
		waiting_member["role"] = "host"
		_waiting_member_by_user_id[user_id3] = waiting_member
		owner_user_id = user_id3
		return
	owner_user_id = ""

func _sync_seat_states_from_engine() -> void:
	if status != STATUS_IN_GAME or game_engine == null:
		return
	var changed := false
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		if _is_seat_forfeited_from_engine(seat_index):
			if str(slot.get("seat_state", "")).strip_edges() != SEAT_FORFEITED:
				slot["seat_state"] = SEAT_FORFEITED
				_set_slot(seat_index, slot)
				changed = true
	if changed:
		_rebuild_runtime_views()

func _is_seat_forfeited_from_engine(seat_index: int) -> bool:
	if game_engine == null:
		return false
	var state = game_engine.get_state()
	if state == null:
		return false
	if not (state.players is Array):
		return false
	if seat_index < 0 or seat_index >= state.players.size():
		return false
	var player_val = state.players[seat_index]
	if not (player_val is Dictionary):
		return false
	return bool(Dictionary(player_val).get("forfeited", false))

func _build_players_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat_index in _occupied_seat_indices():
		var slot: Dictionary = _get_slot(seat_index)
		var profile: Dictionary = Dictionary(slot.get("profile", {}))
		var peer_id := int(slot.get("peer_id", 0))
		var slot_state := str(slot.get("seat_state", "")).strip_edges()
		out.append({
			"peer_id": peer_id,
			"connected": peer_id > 0 and slot_state == SEAT_CONNECTED,
			"seat_index": seat_index,
			"name": str(profile.get("name", "")),
			"color_index": int(profile.get("color_index", 0)),
			"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
			"forfeited": slot_state == SEAT_FORFEITED or _is_seat_forfeited_from_engine(seat_index),
			"state": slot_state,
			"generation": int(slot.get("generation", 0)),
			"role": str(slot.get("role", "player")).strip_edges(),
		})
	return out

func _build_waiting_members_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var user_ids: Array[String] = []
	for user_id_key in _waiting_member_by_user_id.keys():
		var uid := str(user_id_key).strip_edges()
		if uid.is_empty():
			continue
		user_ids.append(uid)
	user_ids.sort()
	for user_id in user_ids:
		var member: Dictionary = Dictionary(_waiting_member_by_user_id.get(user_id, {}))
		if member.is_empty():
			continue
		var profile: Dictionary = Dictionary(member.get("profile", {}))
		var peer_id := int(member.get("peer_id", 0))
		var member_status := str(member.get("member_status", "active")).strip_edges()
		out.append({
			"user_id": user_id,
			"peer_id": peer_id,
			"connected": peer_id > 0 and member_status != "reconnecting",
			"name": str(profile.get("name", "")),
			"color_index": int(profile.get("color_index", 0)),
			"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
			"state": member_status,
			"generation": int(member.get("generation", 1)),
			"role": str(member.get("role", "player")).strip_edges(),
		})
	return out

func _build_spectators_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var peer_ids: Array[int] = []
	for k in _spectator_profile_by_peer_id.keys():
		peer_ids.append(int(k))
	peer_ids.sort()
	for peer_id in peer_ids:
		var profile: Dictionary = Dictionary(_spectator_profile_by_peer_id.get(peer_id, {}))
		out.append({
			"peer_id": peer_id,
			"name": str(profile.get("name", "")),
			"color_index": int(profile.get("color_index", 0)),
			"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
		})
	return out

func _build_directory_spectators_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var peer_ids: Array[int] = []
	for k in _spectator_profile_by_peer_id.keys():
		peer_ids.append(int(k))
	peer_ids.sort()
	for peer_id in peer_ids:
		var profile: Dictionary = Dictionary(_spectator_profile_by_peer_id.get(peer_id, {}))
		var user_id := str(profile.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		out.append({
			"user_id": user_id,
			"role": "spectator",
			"seat_index": null,
			"member_status": "active",
		})
	return out

func build_member_directory_entries() -> Array[Dictionary]:
	_sync_seat_states_from_engine()
	var out: Array[Dictionary] = []
	for seat_index in _occupied_seat_indices():
		var slot := _get_slot(seat_index)
		var user_id := str(slot.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		var slot_state := str(slot.get("seat_state", "")).strip_edges()
		var member_status := "active"
		if slot_state == SEAT_RECONNECTING:
			member_status = "reconnecting"
		elif slot_state == SEAT_FORFEITED:
			member_status = "forfeited"
		out.append({
			"user_id": user_id,
			"role": str(slot.get("role", "player")).strip_edges(),
			"seat_index": seat_index,
			"member_status": member_status,
			"generation": int(slot.get("generation", 1)),
		})
	for member in _waiting_member_by_user_id.values():
		if not (member is Dictionary):
			continue
		var waiting_member: Dictionary = Dictionary(member)
		var user_id2 := str(waiting_member.get("user_id", "")).strip_edges()
		if user_id2.is_empty():
			continue
		out.append({
			"user_id": user_id2,
			"role": str(waiting_member.get("role", "player")).strip_edges(),
			"seat_index": null,
			"member_status": str(waiting_member.get("member_status", "active")).strip_edges(),
			"generation": int(waiting_member.get("generation", 1)),
		})
	out.append_array(_build_directory_spectators_array())
	return out
