extends RefCounted

static func safe_text(value: String) -> String:
	var out := str(value).strip_edges()
	if out.is_empty():
		return "-"
	return out

static func short_hash(hash_value: String) -> String:
	var h := str(hash_value).strip_edges()
	if h.is_empty():
		return "-"
	if h.length() <= 12:
		return h
	return "%s..." % h.substr(0, 12)

static func request_tag(peer_id: int, request_id: String) -> String:
	return "peer=%d request_id=%s" % [peer_id, safe_text(request_id)]

static func room_brief(room) -> String:
	if room == null:
		return "room=- status=- host=0 players=0 spectators=0 peers=0"
	var room_code := safe_text(str(room.room_code).to_upper())
	var status := safe_text(str(room.status))
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

static func command_brief(cmd) -> String:
	if cmd == null:
		return "action=- actor=-1 index=-1"
	return "action=%s actor=%d index=%d" % [
		safe_text(str(cmd.action_id)),
		int(cmd.actor),
		int(cmd.index)
	]
