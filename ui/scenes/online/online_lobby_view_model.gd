# OnlineLobby：RoomState ViewModel（减少 UI 层 Dictionary 操作）
extends RefCounted

static func get_room_code(room_state: Dictionary) -> String:
	if room_state == null:
		return ""
	return str(room_state.get("room_code", "")).strip_edges().to_upper()

static func get_room_status(room_state: Dictionary) -> String:
	if room_state == null:
		return ""
	return str(room_state.get("status", "")).strip_edges()

static func get_room_config(room_state: Dictionary) -> Dictionary:
	if room_state == null:
		return {}
	return Dictionary(room_state.get("config", {}))

static func get_host_peer_id(room_state: Dictionary) -> int:
	if room_state == null:
		return 0
	return int(room_state.get("host_peer_id", 0))

static func get_host_seat_index(room_state: Dictionary) -> int:
	if room_state == null:
		return -1
	return int(room_state.get("host_seat_index", -1))

static func get_players(room_state: Dictionary) -> Array:
	if room_state == null:
		return []
	return Array(room_state.get("players", []))

static func get_spectators(room_state: Dictionary) -> Array:
	if room_state == null:
		return []
	return Array(room_state.get("spectators", []))

static func is_in_room(room_state: Dictionary) -> bool:
	return not get_room_code(room_state).is_empty()

static func is_host(room_state: Dictionary, local_peer_id: int) -> bool:
	var host_peer_id := get_host_peer_id(room_state)
	if host_peer_id <= 0:
		return false
	return int(local_peer_id) == host_peer_id

static func can_start_game(room_state: Dictionary, local_peer_id: int) -> bool:
	if not is_host(room_state, local_peer_id):
		return false
	if get_room_status(room_state) != "Lobby":
		return false
	var cfg: Dictionary = get_room_config(room_state)
	var desired := int(cfg.get("desired_player_count", 0))
	if desired <= 0:
		return false
	var players: Array = get_players(room_state)
	if players.size() != desired:
		return false
	var connected_players := 0
	for p_val in players:
		if not (p_val is Dictionary):
			continue
		if bool(Dictionary(p_val).get("connected", false)):
			connected_players += 1
	return connected_players == desired
