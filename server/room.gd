class_name OnlineRoom
extends RefCounted

const STATUS_LOBBY := "Lobby"

var room_code: String = ""
var host_peer_id: int = 0
var status: String = STATUS_LOBBY
var config: Dictionary = {}
var join_policy: String = "password"
var password_hash: String = ""

var _profile_by_peer_id: Dictionary = {} # peer_id -> { name, color_index }
var _seat_by_peer_id: Dictionary = {} # peer_id -> seat_index
var _desired_player_count: int = 0

func _init(p_room_code: String, p_host_peer_id: int, p_join_policy: String, p_password_hash: String, p_config: Dictionary) -> void:
	room_code = p_room_code
	host_peer_id = p_host_peer_id
	join_policy = p_join_policy
	password_hash = p_password_hash
	config = p_config.duplicate(true)
	_desired_player_count = int(config.get("desired_player_count", 0))

func has_peer(peer_id: int) -> bool:
	return _profile_by_peer_id.has(peer_id)

func get_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for k in _profile_by_peer_id.keys():
		peer_ids.append(int(k))
	peer_ids.sort_custom(func(a: int, b: int) -> bool:
		return int(_seat_by_peer_id.get(a, 999999)) < int(_seat_by_peer_id.get(b, 999999))
	)
	return peer_ids

func get_player_count() -> int:
	return _profile_by_peer_id.size()

func is_full() -> bool:
	if _desired_player_count <= 0:
		return false
	return get_player_count() >= _desired_player_count

func is_empty() -> bool:
	return _profile_by_peer_id.is_empty()

func add_peer(peer_id: int, profile: Dictionary) -> Result:
	if has_peer(peer_id):
		return Result.failure("Peer already in room")
	if is_full():
		return Result.failure("Room is full")

	var seat_index := _pick_seat_index()
	_profile_by_peer_id[peer_id] = profile.duplicate(true)
	_seat_by_peer_id[peer_id] = seat_index
	return Result.success()

func remove_peer(peer_id: int) -> Result:
	if not has_peer(peer_id):
		return Result.failure("Peer not in room")

	_profile_by_peer_id.erase(peer_id)
	_seat_by_peer_id.erase(peer_id)

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
		"config": config.duplicate(true),
		"status": status,
	}

func _pick_seat_index() -> int:
	var max_seats := maxi(1, _desired_player_count)
	for i in range(max_seats):
		if not _seat_by_peer_id.values().has(i):
			return i
	return max_seats

func _pick_new_host_peer_id() -> int:
	var peer_ids := get_peer_ids()
	if peer_ids.is_empty():
		return 0
	return int(peer_ids[0])

func _build_players_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for peer_id in get_peer_ids():
		var profile: Dictionary = Dictionary(_profile_by_peer_id.get(peer_id, {}))
		out.append({
			"peer_id": peer_id,
			"seat_index": int(_seat_by_peer_id.get(peer_id, 0)),
			"name": str(profile.get("name", "")),
			"color_index": int(profile.get("color_index", 0)),
		})
	return out

