class_name OnlineRoom
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")
const DEFAULT_RESTAURANT_LOGO_COUNT := 6
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

const STATUS_LOBBY := "Lobby"
const STATUS_IN_GAME := "InGame"
const STATUS_ENDED := "Ended"

var room_code: String = ""
var host_peer_id: int = 0
var status: String = STATUS_LOBBY
var config: Dictionary = {}
var join_policy: String = "password"
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

# 玩家座位：seat_index -> profile（即便掉线/弃权也保留，用于“旁观者”占位）
var _seat_profile_by_seat_index: Dictionary = {} # seat_index -> { name, color_index, restaurant_logo_id }
var _peer_id_by_seat_index: Dictionary = {} # seat_index -> peer_id（在线；掉线则不存在或为 0）

# 在线成员：peer_id -> profile
var _player_profile_by_peer_id: Dictionary = {} # peer_id -> { name, color_index, restaurant_logo_id }
var _spectator_profile_by_peer_id: Dictionary = {} # peer_id -> { name, color_index, restaurant_logo_id }

var _seat_by_player_peer_id: Dictionary = {} # peer_id -> seat_index
var _desired_player_count: int = 0
var _user_id_by_seat_index: Dictionary = {} # seat_index -> user_id（用于断线重连鉴权；不对客户端广播）

func _init(p_room_code: String, p_host_peer_id: int, p_join_policy: String, p_password_hash: String, p_config: Dictionary) -> void:
	room_code = p_room_code
	host_peer_id = p_host_peer_id
	join_policy = p_join_policy
	password_hash = p_password_hash
	config = p_config.duplicate(true)
	_desired_player_count = int(config.get("desired_player_count", 0))
	_touch()

func _touch() -> void:
	updated_at_ms = int(Time.get_unix_time_from_system() * 1000.0)

func is_password_required() -> bool:
	if join_policy != "password":
		return true
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

	# 其它字段按原样覆盖；校验在 server RPC 层完成。
	for k in patch.keys():
		var key := str(k)
		if key == "desired_player_count":
			continue
		config[key] = patch.get(k, null)

	_touch()
	return Result.success()

func has_peer(peer_id: int) -> bool:
	return _player_profile_by_peer_id.has(peer_id) or _spectator_profile_by_peer_id.has(peer_id)

func get_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for k in _player_profile_by_peer_id.keys():
		peer_ids.append(int(k))
	peer_ids.sort_custom(func(a: int, b: int) -> bool:
		return int(_seat_by_player_peer_id.get(a, 999999)) < int(_seat_by_player_peer_id.get(b, 999999))
	)
	var spectator_ids: Array[int] = []
	for k2 in _spectator_profile_by_peer_id.keys():
		spectator_ids.append(int(k2))
	spectator_ids.sort()
	peer_ids.append_array(spectator_ids)
	return peer_ids

func get_player_count() -> int:
	return _seat_profile_by_seat_index.size()

func get_connected_player_count() -> int:
	return _player_profile_by_peer_id.size()

func is_full() -> bool:
	if _desired_player_count <= 0:
		return false
	return get_player_count() >= _desired_player_count

func is_empty() -> bool:
	return _seat_profile_by_seat_index.is_empty() and _spectator_profile_by_peer_id.is_empty()

func add_peer(peer_id: int, profile: Dictionary) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if is_full():
		return Result.failure("Room is full")

	var seat_index := _pick_seat_index()
	_player_profile_by_peer_id[peer_id] = profile.duplicate(true)
	_seat_by_player_peer_id[peer_id] = seat_index
	_seat_profile_by_seat_index[seat_index] = profile.duplicate(true)
	_peer_id_by_seat_index[seat_index] = peer_id
	var user_id := str(profile.get("user_id", "")).strip_edges()
	if not user_id.is_empty():
		_user_id_by_seat_index[seat_index] = user_id
	_touch()
	return Result.success()

func add_peer_at_seat(peer_id: int, profile: Dictionary, seat_index: int) -> Result:
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
	if _seat_profile_by_seat_index.has(idx):
		return Result.failure("Seat already occupied")

	_player_profile_by_peer_id[peer_id] = profile.duplicate(true)
	_seat_by_player_peer_id[peer_id] = idx
	_seat_profile_by_seat_index[idx] = profile.duplicate(true)
	_peer_id_by_seat_index[idx] = peer_id
	var user_id := str(profile.get("user_id", "")).strip_edges()
	if not user_id.is_empty():
		_user_id_by_seat_index[idx] = user_id

	_touch()
	return Result.success()

func reconnect_player(peer_id: int, profile: Dictionary, seat_index: int, user_id: String = "") -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")

	var idx := int(seat_index)
	if idx < 0:
		return Result.failure("Invalid seat_index")
	if not _seat_profile_by_seat_index.has(idx):
		return Result.failure("Seat not found")

	var current_peer_id := int(_peer_id_by_seat_index.get(idx, 0))
	if current_peer_id > 0:
		return Result.failure("Seat already connected")

	var uid := str(user_id).strip_edges()
	if not uid.is_empty():
		var existing_uid := str(_user_id_by_seat_index.get(idx, "")).strip_edges()
		if not existing_uid.is_empty() and existing_uid != uid:
			return Result.failure("user_id mismatch for seat")
		if existing_uid.is_empty():
			_user_id_by_seat_index[idx] = uid

	_player_profile_by_peer_id[peer_id] = profile.duplicate(true)
	_seat_by_player_peer_id[peer_id] = idx
	_peer_id_by_seat_index[idx] = peer_id

	# 更新座位展示信息（昵称/颜色/logo）
	_seat_profile_by_seat_index[idx] = profile.duplicate(true)

	# InGame：恢复 peer->player_id 映射（actor_id == seat_index）
	player_id_by_peer_id[peer_id] = idx

	_touch()
	return Result.success()

func add_spectator(peer_id: int, profile: Dictionary) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")
	if not get_allow_spectators():
		return Result.failure("Spectators not allowed")

	_spectator_profile_by_peer_id[peer_id] = profile.duplicate(true)
	_touch()
	return Result.success()

func remove_peer(peer_id: int) -> Result:
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
		_touch()
		return Result.success({
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	if not _player_profile_by_peer_id.has(peer_id):
		return Result.failure("Peer not in room")

	var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
	_player_profile_by_peer_id.erase(peer_id)
	_seat_by_player_peer_id.erase(peer_id)
	if seat_index >= 0:
		_peer_id_by_seat_index.erase(seat_index)
		_seat_profile_by_seat_index.erase(seat_index)
		_user_id_by_seat_index.erase(seat_index)

	var host_changed := false
	if host_peer_id == peer_id:
		host_peer_id = _pick_new_host_peer_id()
		host_changed = true

	_touch()
	return Result.success({
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func disconnect_peer(peer_id: int) -> Result:
	# Spectator：直接移除（无座位）
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
		_touch()
		return Result.success({
			"host_changed": false,
			"host_peer_id": host_peer_id,
		})

	# Player：保留 seat_profile（作为旁观者占位），但移除在线 peer 映射
	if not _player_profile_by_peer_id.has(peer_id):
		return Result.failure("Peer not in room")

	var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
	_player_profile_by_peer_id.erase(peer_id)
	_seat_by_player_peer_id.erase(peer_id)
	if seat_index >= 0:
		_peer_id_by_seat_index.erase(seat_index)

	var host_changed := false
	if host_peer_id == peer_id:
		host_peer_id = _pick_new_host_peer_id()
		host_changed = true

	_touch()
	return Result.success({
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
	if str(normalized.get("name", "")).is_empty():
		normalized["name"] = "玩家"

	if _player_profile_by_peer_id.has(peer_id):
		_player_profile_by_peer_id[peer_id] = normalized.duplicate(true)
		var seat_index := int(_seat_by_player_peer_id.get(peer_id, -1))
		if seat_index >= 0 and _seat_profile_by_seat_index.has(seat_index):
			_seat_profile_by_seat_index[seat_index] = normalized.duplicate(true)
		_touch()
		return Result.success()

	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id[peer_id] = normalized.duplicate(true)
		_touch()
		return Result.success()

	return Result.failure("Peer not in room")

func set_player_logo_by_seat(seat_index: int, restaurant_logo_id: int) -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if seat_index < 0 or not _seat_profile_by_seat_index.has(seat_index):
		return Result.failure("Seat not found")

	var logo_limit := DEFAULT_RESTAURANT_LOGO_COUNT
	var logo_id := int(restaurant_logo_id)
	if logo_id < -1 or logo_id >= maxi(1, logo_limit):
		return Result.failure("restaurant_logo_id out of range")

	var seat_profile: Dictionary = Dictionary(_seat_profile_by_seat_index.get(seat_index, {}))
	if seat_profile.is_empty():
		return Result.failure("Seat profile missing")
	seat_profile["restaurant_logo_id"] = logo_id
	_seat_profile_by_seat_index[seat_index] = seat_profile.duplicate(true)

	var peer_id := int(_peer_id_by_seat_index.get(seat_index, 0))
	if peer_id > 0 and _player_profile_by_peer_id.has(peer_id):
		var player_profile: Dictionary = Dictionary(_player_profile_by_peer_id.get(peer_id, {}))
		player_profile["restaurant_logo_id"] = logo_id
		_player_profile_by_peer_id[peer_id] = player_profile.duplicate(true)

	_touch()
	return Result.success()

func to_room_state_dict() -> Dictionary:
	return {
		"room_code": room_code,
		"host_peer_id": host_peer_id,
		"players": _build_players_array(),
		"spectators": _build_spectators_array(),
		"config": config.duplicate(true),
		"password_required": is_password_required(),
		"allow_spectators": get_allow_spectators(),
		"status": status,
	}

func to_room_summary_dict() -> Dictionary:
	var cfg: Dictionary = config.duplicate(true)
	var seed_mode := str(cfg.get("seed_mode", "")).strip_edges()
	var seed := int(cfg.get("seed", 0))
	var mods_count := 0
	var mv = cfg.get("enabled_modules_v2", null)
	if mv is Array:
		mods_count = Array(mv).size()

	var host_name := ""
	var host_profile: Dictionary = Dictionary(_player_profile_by_peer_id.get(host_peer_id, {}))
	if not host_profile.is_empty():
		host_name = str(host_profile.get("name", ""))

	return {
		"room_code": room_code,
		"status": status,
		"desired_player_count": int(cfg.get("desired_player_count", 0)),
		"player_count": get_player_count(),
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
	var peer_ids := get_player_peer_ids()
	for i in range(peer_ids.size()):
		out[int(peer_ids[i])] = i
	return out

func get_player_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for k in _player_profile_by_peer_id.keys():
		peer_ids.append(int(k))
	peer_ids.sort_custom(func(a: int, b: int) -> bool:
		return int(_seat_by_player_peer_id.get(a, 999999)) < int(_seat_by_player_peer_id.get(b, 999999))
	)
	return peer_ids

func can_start_game() -> Result:
	if status != STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")

	var desired := int(config.get("desired_player_count", 0))
	if desired <= 0:
		return Result.failure("desired_player_count not set")
	if get_player_count() != desired:
		return Result.failure("players not ready: have=%d need=%d" % [get_player_count(), desired])

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
		var profile: Dictionary = Dictionary(_seat_profile_by_seat_index.get(seat_index, {}))
		logo_choices.append(int(profile.get("restaurant_logo_id", -1)))
	config["restaurant_logo_choices_by_player"] = logo_choices

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
	if not init_r.ok:
		return Result.failure("GameEngine.initialize failed: %s" % init_r.error)
	var state = engine.get_state()
	if state != null:
		if not (state.rules is Dictionary):
			state.rules = {}
		# 写入持久规则区：round_state 会在每回合开始被重建。
		state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1

	game_engine = engine
	player_id_by_peer_id = build_player_id_by_peer_id()
	status = STATUS_IN_GAME
	started_at_iso = Time.get_datetime_string_from_system()
	ended_at_iso = ""
	started_at_unix_sec = int(Time.get_unix_time_from_system())
	ended_at_unix_sec = 0
	match_finalize_in_flight = false
	match_finalize_reported = false
	finalized_match_id = ""
	_touch()

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

		# 在线对局：保持线性时间线，丢弃未来命令（与本地执行新命令的 truncate 规则一致）。
		if game_engine.has_method("truncate_future_history"):
			game_engine.truncate_future_history()

	var state_hash := ""
	var state: GameState = game_engine.get_state()
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

	_touch()
	return Result.success(out)

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
		if not _seat_profile_by_seat_index.has(i):
			return i
	return max_seats

func _pick_new_host_peer_id() -> int:
	var peer_ids := get_player_peer_ids()
	if peer_ids.is_empty():
		return 0
	return int(peer_ids[0])

func _build_players_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seat_indices: Array[int] = []
	for k in _seat_profile_by_seat_index.keys():
		seat_indices.append(int(k))
	seat_indices.sort()

	var forfeited_by_player_id: Dictionary = {}
	if status == STATUS_IN_GAME and game_engine != null:
		var state = game_engine.get_state()
		if state != null and (state.players is Array):
			for pid in range(state.players.size()):
				var pv = state.players[pid]
				if pv is Dictionary:
					forfeited_by_player_id[pid] = bool(Dictionary(pv).get("forfeited", false))

	for seat_index in seat_indices:
		var profile: Dictionary = Dictionary(_seat_profile_by_seat_index.get(seat_index, {}))
		var peer_id := int(_peer_id_by_seat_index.get(seat_index, 0))
		out.append({
			"peer_id": peer_id,
			"connected": peer_id > 0,
			"seat_index": seat_index,
			"name": str(profile.get("name", "")),
			"color_index": int(profile.get("color_index", 0)),
			"restaurant_logo_id": int(profile.get("restaurant_logo_id", -1)),
			"forfeited": bool(forfeited_by_player_id.get(seat_index, false)),
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
