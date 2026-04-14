class_name OnlineRoom
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const OnlineResumePointValidatorClass = preload("res://core/engine/game_engine/online_resume_point_validator.gd")
const DEFAULT_RESTAURANT_LOGO_COUNT := 6

const STATUS_LOBBY := "Lobby"
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
var _resume_checkpoint_id: String = ""
var _resume_checkpoint_sequence: int = 0
var _resume_checkpoint_state_hash: String = ""
var _resume_checkpoint_archive: Dictionary = {}
var _resume_delta_log: Array[Dictionary] = []
var _resume_checkpoint_counter: int = 0
var _prepared_resume_start_engine = null
var _prepared_resume_start_archive: Dictionary = {}
var _prepared_resume_start_final_hash: String = ""

func to_persistence_dict(include_runtime_membership: bool = false) -> Result:
	if str(status) != STATUS_IN_GAME and str(status) != STATUS_LOBBY:
		return Result.failure("只支持持久化 Lobby/InGame 房间")

	_sync_seat_states_from_engine()

	var archive: Dictionary = {}
	if str(status) == STATUS_IN_GAME:
		if game_engine == null:
			return Result.failure("InGame 房间缺少 game_engine")
		var archive_r: Result = game_engine.create_archive()
		if not archive_r.ok:
			return Result.failure("create_archive failed: %s" % archive_r.error)
		archive = Dictionary(archive_r.value).duplicate(true)

	var out := {
		"room_code": room_code,
		"status": status,
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
	if status == STATUS_LOBBY and room_mode == ROOM_MODE_RESUME_ARCHIVE:
		out["resume_lobby_archive"] = _resume_lobby_archive.duplicate(true)
	if include_runtime_membership:
		out["spectators"] = _build_directory_spectators_array()
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

static func _enable_online_dinnertime_confirm_on_engine(engine) -> void:
	OnlineResumePointValidatorClass.prepare_engine_for_online_resume(engine)

func _clear_prepared_resume_start_cache() -> void:
	_prepared_resume_start_engine = null
	_prepared_resume_start_archive = {}
	_prepared_resume_start_final_hash = ""

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

	var validate_r: Result = OnlineResumePointValidatorClass.validate_resume_point(preview_engine)
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

func _current_resume_sequence() -> int:
	if game_engine == null:
		return 0
	var history_val = game_engine.get("command_history") if game_engine is Object else null
	return Array(history_val).size() if history_val is Array else 0

func _current_resume_state_hash() -> String:
	if game_engine == null or not game_engine.has_method("get_state"):
		return ""
	var state = game_engine.get_state()
	if state == null or not state.has_method("compute_hash"):
		return ""
	return str(state.compute_hash())

func _reset_recovery_store_from_current_engine(reason: String = "") -> Result:
	if status != STATUS_IN_GAME:
		_resume_checkpoint_id = ""
		_resume_checkpoint_sequence = 0
		_resume_checkpoint_state_hash = ""
		_resume_checkpoint_archive = {}
		_resume_delta_log.clear()
		return Result.success()
	if game_engine == null:
		return Result.failure("Room engine missing")
	var archive_r: Result = game_engine.create_archive()
	if not archive_r.ok:
		return Result.failure("create_archive failed: %s" % archive_r.error)
	_resume_checkpoint_counter += 1
	var suffix := str(reason).strip_edges()
	if suffix.is_empty():
		suffix = "checkpoint"
	_resume_checkpoint_id = "%s_%d_%d" % [suffix, _current_resume_sequence(), _resume_checkpoint_counter]
	_resume_checkpoint_sequence = _current_resume_sequence()
	_resume_checkpoint_state_hash = _current_resume_state_hash()
	_resume_checkpoint_archive = Dictionary(archive_r.value).duplicate(true)
	_resume_delta_log.clear()
	return Result.success({
		"checkpoint_id": _resume_checkpoint_id,
		"sequence": _resume_checkpoint_sequence,
		"state_hash": _resume_checkpoint_state_hash,
	})

func get_resume_cursor() -> Dictionary:
	return {
		"checkpoint_id": _resume_checkpoint_id,
		"last_applied_sequence": _current_resume_sequence(),
		"last_state_hash": _current_resume_state_hash(),
	}

func build_delta_resume_payload(cursor: Dictionary, max_commands: int = 0, soft_limit_bytes: int = 0) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")
	if cursor.is_empty():
		return Result.failure("resume cursor missing")
	if _resume_checkpoint_archive.is_empty():
		var checkpoint_r: Result = _reset_recovery_store_from_current_engine("resume_init")
		if not checkpoint_r.ok:
			return checkpoint_r

	var from_sequence := int(cursor.get("last_applied_sequence", -1))
	var from_hash := str(cursor.get("last_state_hash", "")).strip_edges()
	var current_sequence := _current_resume_sequence()
	var current_hash := _current_resume_state_hash()
	if from_sequence < 0 or from_sequence > current_sequence:
		return Result.failure("resume cursor sequence invalid")

	var expected_hash := ""
	if from_sequence == current_sequence:
		expected_hash = current_hash
	elif from_sequence == _resume_checkpoint_sequence:
		expected_hash = _resume_checkpoint_state_hash
	else:
		for item in _resume_delta_log:
			var entry: Dictionary = Dictionary(item)
			if int(entry.get("sequence", -1)) != from_sequence:
				continue
			expected_hash = str(entry.get("post_state_hash", "")).strip_edges()
			break
	if expected_hash.is_empty():
		return Result.failure("delta gap")
	if from_hash.is_empty() or expected_hash != from_hash:
		return Result.failure("resume cursor hash mismatch")

	var entries: Array[Dictionary] = []
	for item2 in _resume_delta_log:
		var entry2: Dictionary = Dictionary(item2)
		if int(entry2.get("sequence", -1)) <= from_sequence:
			continue
		entries.append(entry2.duplicate(true))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("sequence", -1)) < int(b.get("sequence", -1))
	)

	if from_sequence < current_sequence:
		var expected_sequence := from_sequence + 1
		for entry3 in entries:
			if int(entry3.get("sequence", -1)) != expected_sequence:
				return Result.failure("delta gap")
			expected_sequence += 1
		if expected_sequence - 1 != current_sequence:
			return Result.failure("delta incomplete")

	if max_commands > 0 and entries.size() > max_commands:
		return Result.failure("delta too long")

	var payload := {
		"room_code": str(room_code).strip_edges().to_upper(),
		"checkpoint_id": _resume_checkpoint_id,
		"from_sequence": from_sequence,
		"to_sequence": current_sequence,
		"final_sequence": current_sequence,
		"final_hash": current_hash,
		"entries": entries,
	}
	var payload_bytes := int(var_to_bytes(payload).size())
	if soft_limit_bytes > 0 and payload_bytes > soft_limit_bytes:
		return Result.failure("delta too large")

	return Result.success({
		"payload": payload,
		"payload_bytes": payload_bytes,
		"entry_count": entries.size(),
		"from_sequence": from_sequence,
		"to_sequence": current_sequence,
		"final_hash": current_hash,
	})

func record_resume_delta(cmd: Command, post_state_hash: String = "") -> void:
	if status != STATUS_IN_GAME or game_engine == null or cmd == null:
		return
	if _resume_checkpoint_archive.is_empty():
		var checkpoint_r: Result = _reset_recovery_store_from_current_engine("delta_init")
		if not checkpoint_r.ok:
			return
	var normalized_hash := str(post_state_hash).strip_edges()
	if normalized_hash.is_empty():
		normalized_hash = _current_resume_state_hash()
	_resume_delta_log.append({
		"sequence": _current_resume_sequence(),
		"cmd": cmd.to_dict(),
		"post_state_hash": normalized_hash,
	})
	if _current_resume_sequence() - _resume_checkpoint_sequence >= RESUME_DELTA_ROTATE_COMMAND_THRESHOLD:
		_reset_recovery_store_from_current_engine("delta_rotate")

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
	_resume_lobby_archive = Dictionary(archive).duplicate(true)
	var inferred_player_count := _infer_resume_player_count_from_archive(_resume_lobby_archive)
	if inferred_player_count <= 0:
		return Result.failure("resume archive player_count invalid")
	_desired_player_count = inferred_player_count
	config["desired_player_count"] = inferred_player_count
	_touch()
	return Result.success()

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
	if existing_waiting.is_empty() and _user_id_by_seat_index.values().has(user_id):
		return Result.failure("user already assigned to seat")
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
	if status == STATUS_LOBBY:
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
	return {
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

func to_room_state_dict_for_peer(peer_id: int) -> Dictionary:
	var state := to_room_state_dict()
	state["self_seat_index"] = get_seat_index_for_peer(peer_id)
	state["self_role"] = get_role_for_peer(peer_id)
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

	return {
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

func start_game() -> Result:
	var ready := can_start_game()
	if not ready.ok:
		return ready

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

		var restore_game_config_overrides := false
		var restore_game_option_overrides := false
		var prev_game_config_overrides: Dictionary = {}
		var prev_game_option_overrides: Dictionary = {}
		if Globals != null and "game_config_overrides" in Globals:
			restore_game_config_overrides = true
			prev_game_config_overrides = Dictionary(Globals.game_config_overrides).duplicate(true)
			var config_overrides_val = config.get("game_config_overrides", null)
			var config_overrides: Dictionary = Dictionary(config_overrides_val) if config_overrides_val is Dictionary else {}
			Globals.game_config_overrides = config_overrides
		if Globals != null and "game_option_overrides" in Globals:
			restore_game_option_overrides = true
			prev_game_option_overrides = Dictionary(Globals.game_option_overrides).duplicate(true)
			var option_overrides_val = config.get("game_option_overrides", null)
			var option_overrides: Dictionary = Dictionary(option_overrides_val) if option_overrides_val is Dictionary else {}
			Globals.game_option_overrides = option_overrides

			var init_r: Result = engine.initialize(player_count, seed, enabled_modules, base_dir, reserve_card_choices, logo_choices)
			if restore_game_config_overrides:
				Globals.game_config_overrides = prev_game_config_overrides
			if restore_game_option_overrides:
				Globals.game_option_overrides = prev_game_option_overrides
			if not init_r.ok:
				return Result.failure("GameEngine.initialize failed: %s" % init_r.error)

	_enable_online_dinnertime_confirm_on_engine(engine)

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
	_resume_lobby_archive = {}
	_clear_prepared_resume_start_cache()
	_rebuild_runtime_views()
	_touch()
	var checkpoint_r: Result = _reset_recovery_store_from_current_engine("start_game")
	if not checkpoint_r.ok:
		return Result.failure("初始化 recovery store 失败: %s" % checkpoint_r.error)

	return Result.success({
		"player_id_by_peer_id": player_id_by_peer_id.duplicate(true),
		"config": config.duplicate(true),
	})

func rewind_to_current_player_turn_start(include_archive: bool = true) -> Result:
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if game_engine == null:
		return Result.failure("Room engine missing")
	if not game_engine.has_method("find_current_player_turn_start_command_index"):
		return Result.failure("Room engine missing turn-start query")

	var idx_r: Result = game_engine.find_current_player_turn_start_command_index()
	if not idx_r.ok:
		return Result.failure("find_current_player_turn_start_command_index failed: %s" % idx_r.error)

	var target_index := int(idx_r.value)
	var before_index := int(game_engine.current_command_index)

	if target_index < before_index:
		var rewind_r: Result = game_engine.rewind_to_command(target_index)
		if not rewind_r.ok:
			return Result.failure("rewind_to_command failed: %s" % rewind_r.error)
		if game_engine.has_method("truncate_future_history"):
			game_engine.truncate_future_history()

	var state_hash := ""
	var state = game_engine.get_state()
	if state != null:
		state_hash = str(state.compute_hash())

	var out := {
		"target_index": target_index,
		"before_index": before_index,
		"current_index": int(game_engine.current_command_index),
		"history_size": int(game_engine.command_history.size()),
		"state_hash": state_hash,
		"noop": target_index >= before_index,
	}

	if include_archive:
		var archive_r: Result = game_engine.create_archive()
		if not archive_r.ok:
			return Result.failure("create_archive failed: %s" % archive_r.error)
		out["archive"] = Dictionary(archive_r.value).duplicate(true)

	var checkpoint_r: Result = _reset_recovery_store_from_current_engine("rewind")
	if not checkpoint_r.ok:
		return Result.failure("reset recovery store failed: %s" % checkpoint_r.error)
	_touch()
	return Result.success(out)

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
