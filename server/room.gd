class_name OnlineRoom
extends RefCounted

const GameEngineClass = preload("res://core/engine/game_engine.gd")

const STATUS_LOBBY := "Lobby"
const STATUS_IN_GAME := "InGame"
const STATUS_ENDED := "Ended"

var room_code: String = ""
var host_peer_id: int = 0
var status: String = STATUS_LOBBY
var config: Dictionary = {}
var join_policy: String = "password"
var password_hash: String = ""

var game_engine = null
var player_id_by_peer_id: Dictionary = {} # peer_id -> player_id

# 玩家座位：seat_index -> profile（即便掉线/弃权也保留，用于“旁观者”占位）
var _seat_profile_by_seat_index: Dictionary = {} # seat_index -> { name, color_index }
var _peer_id_by_seat_index: Dictionary = {} # seat_index -> peer_id（在线；掉线则不存在或为 0）

# 在线成员：peer_id -> profile
var _player_profile_by_peer_id: Dictionary = {} # peer_id -> { name, color_index }
var _spectator_profile_by_peer_id: Dictionary = {} # peer_id -> { name, color_index }

var _seat_by_player_peer_id: Dictionary = {} # peer_id -> seat_index
var _desired_player_count: int = 0

func _init(p_room_code: String, p_host_peer_id: int, p_join_policy: String, p_password_hash: String, p_config: Dictionary) -> void:
	room_code = p_room_code
	host_peer_id = p_host_peer_id
	join_policy = p_join_policy
	password_hash = p_password_hash
	config = p_config.duplicate(true)
	_desired_player_count = int(config.get("desired_player_count", 0))

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
	return Result.success()

func add_spectator(peer_id: int, profile: Dictionary) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if status != STATUS_IN_GAME:
		return Result.failure("Room is not in game")

	_spectator_profile_by_peer_id[peer_id] = profile.duplicate(true)
	return Result.success()

func remove_peer(peer_id: int) -> Result:
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
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

	var host_changed := false
	if host_peer_id == peer_id:
		host_peer_id = _pick_new_host_peer_id()
		host_changed = true

	return Result.success({
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func disconnect_peer(peer_id: int) -> Result:
	# Spectator：直接移除（无座位）
	if _spectator_profile_by_peer_id.has(peer_id):
		_spectator_profile_by_peer_id.erase(peer_id)
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

	return Result.success({
		"host_changed": host_changed,
		"host_peer_id": host_peer_id,
	})

func to_room_state_dict() -> Dictionary:
	return {
		"room_code": room_code,
		"host_peer_id": host_peer_id,
		"players": _build_players_array(),
		"spectators": _build_spectators_array(),
		"config": config.duplicate(true),
		"status": status,
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
	for _i in range(player_count):
		logo_choices.append(-1)
	config["restaurant_logo_choices_by_player"] = logo_choices

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(player_count, seed, enabled_modules, base_dir, [], logo_choices)
	if not init_r.ok:
		return Result.failure("GameEngine.initialize failed: %s" % init_r.error)

	game_engine = engine
	player_id_by_peer_id = build_player_id_by_peer_id()
	status = STATUS_IN_GAME

	return Result.success({
		"player_id_by_peer_id": player_id_by_peer_id.duplicate(true),
		"config": config.duplicate(true),
	})

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
		})
	return out
