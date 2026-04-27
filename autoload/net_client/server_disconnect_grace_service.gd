extends RefCounted

const CommandClass = preload("res://core/types/command.gd")
const ServerLogFormatClass = preload("res://autoload/net_client/server_log_format.gd")

var _net = null
var _ticket_by_key: Dictionary = {} # "ROOM:kind:value" -> ticket (int)

var _get_grace_period_sec: Callable = Callable()
var _resolve_actor_id_for_peer: Callable = Callable()
var _mark_room_directory_dirty: Callable = Callable()
var _broadcast_room_state: Callable = Callable()
var _broadcast_room_list: Callable = Callable()
var _broadcast_command_applied: Callable = Callable()
var _drain_forfeited_auto_steps: Callable = Callable()
var _try_finalize_match: Callable = Callable()
var _is_player_forfeited: Callable = Callable()

func setup(net_client, callbacks: Dictionary = {}) -> void:
	_net = net_client
	_get_grace_period_sec = callbacks.get("get_grace_period_sec", Callable())
	_resolve_actor_id_for_peer = callbacks.get("resolve_actor_id_for_peer", Callable())
	_mark_room_directory_dirty = callbacks.get("mark_room_directory_dirty", Callable())
	_broadcast_room_state = callbacks.get("broadcast_room_state", Callable())
	_broadcast_room_list = callbacks.get("broadcast_room_list", Callable())
	_broadcast_command_applied = callbacks.get("broadcast_command_applied", Callable())
	_drain_forfeited_auto_steps = callbacks.get("drain_forfeited_auto_steps", Callable())
	_try_finalize_match = callbacks.get("try_finalize_match", Callable())
	_is_player_forfeited = callbacks.get("is_player_forfeited", Callable())

func resolve_target(room, peer_id: int) -> Dictionary:
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
		var seat_index := int(_resolve_actor_id_for_peer.call(room, peer_id))
		if seat_index >= 0:
			return {
				"kind": "seat",
				"value": str(seat_index),
			}
		return {}
	if room_status != "InGame":
		return {}
	var actor_id := int(_resolve_actor_id_for_peer.call(room, peer_id))
	if actor_id < 0:
		return {}
	return {
		"kind": "actor",
		"value": str(actor_id),
	}

func schedule(room, target: Dictionary) -> void:
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
	var grace_sec := float(_get_grace_period_sec.call())
	var room_code := str(room.room_code).strip_edges().to_upper()
	var key := _grace_key(room_code, target_kind, target_value)
	var ticket := int(_ticket_by_key.get(key, 0)) + 1
	_ticket_by_key[key] = ticket

	if grace_sec <= 0.0:
		_on_timeout(room_code, target_kind, target_value, ticket)
		return

	var tree = _net.get_tree()
	if tree == null or not (tree is SceneTree):
		return
	var timer = (tree as SceneTree).create_timer(grace_sec)
	timer.timeout.connect(Callable(self, "_on_timeout").bind(room_code, target_kind, target_value, ticket))
	GameLog.warn(
		"NetClient",
		"Disconnect grace scheduled room=%s kind=%s target=%s grace_sec=%.1f"
			% [
				ServerLogFormatClass.safe_text(room_code),
				ServerLogFormatClass.safe_text(target_kind),
				ServerLogFormatClass.safe_text(target_value),
				grace_sec,
			]
	)

func clear_actor(room_code: String, actor_id: int) -> void:
	_clear_key(_forfeit_key(room_code, actor_id))

func clear_lobby_seat(room_code: String, seat_index: int) -> void:
	_clear_key(_lobby_seat_key(room_code, seat_index))

func clear_waiting_member(room_code: String, user_id: String) -> void:
	_clear_key(_grace_key(room_code, "waiting", str(user_id).strip_edges()))

func _grace_key(room_code: String, target_kind: String, target_value: String) -> String:
	return "%s:%s:%s" % [
		str(room_code).strip_edges().to_upper(),
		str(target_kind).strip_edges(),
		str(target_value).strip_edges(),
	]

func _forfeit_key(room_code: String, actor_id: int) -> String:
	return _grace_key(room_code, "actor", str(int(actor_id)))

func _lobby_seat_key(room_code: String, seat_index: int) -> String:
	return _grace_key(room_code, "seat", str(int(seat_index)))

func _clear_key(key: String) -> void:
	if _ticket_by_key.has(key):
		_ticket_by_key.erase(key)

func _on_timeout(room_code: String, target_kind: String, target_value: String, ticket: int) -> void:
	if _net == null or not is_instance_valid(_net):
		return
	if NetContext.mode != NetContext.Mode.ONLINE_SERVER:
		return
	var key := _grace_key(room_code, target_kind, target_value)
	if int(_ticket_by_key.get(key, 0)) != int(ticket):
		return
	_ticket_by_key.erase(key)

	if _net._room_manager == null:
		return
	var rm = _net._room_manager
	if not (rm.rooms is Dictionary):
		return
	var room = rm.rooms.get(str(room_code).strip_edges().to_upper(), null)
	if room == null:
		return
	if _is_target_connected(room, target_kind, target_value):
		return
	if str(room.status) == "Lobby":
		_handle_lobby_timeout(rm, room_code, target_kind, target_value)
		return
	_handle_in_game_timeout(room, room_code, target_kind, target_value)

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

func _is_target_connected(room, target_kind: String, target_value: String) -> bool:
	var normalized_kind := str(target_kind).strip_edges()
	if normalized_kind == "waiting":
		if room == null or not room.has_method("get_waiting_member_peer_id"):
			return false
		return int(room.get_waiting_member_peer_id(str(target_value).strip_edges())) > 0
	if not str(target_value).is_valid_int():
		return false
	return _is_actor_connected(room, int(target_value))

func _handle_lobby_timeout(rm, room_code: String, target_kind: String, target_value: String) -> void:
	if str(target_kind).strip_edges() == "waiting":
		if not rm.has_method("release_reconnecting_waiting_member"):
			return
		var waiting_release_r: Result = rm.release_reconnecting_waiting_member(room_code, str(target_value))
		if not waiting_release_r.ok:
			GameLog.error(
				"NetClient",
				"release_reconnecting_waiting_member failed after disconnect grace room=%s user=%s err=%s"
					% [
						ServerLogFormatClass.safe_text(room_code),
						ServerLogFormatClass.safe_text(str(target_value)),
						waiting_release_r.error,
					]
			)
			return
		var waiting_release_payload: Dictionary = Dictionary(waiting_release_r.value) if waiting_release_r.value is Dictionary else {}
		if not bool(waiting_release_payload.get("released", false)):
			return
		var waiting_removed := bool(waiting_release_payload.get("removed", false))
		var waiting_room_after = waiting_release_payload.get("room", null)
		_mark_room_directory_dirty.call()
		if not waiting_removed and waiting_room_after != null:
			_broadcast_room_state.call(waiting_room_after)
		_broadcast_room_list.call("")
		GameLog.warn(
			"NetClient",
			"Released lobby reconnecting waiting member after disconnect grace room=%s user=%s removed=%s"
				% [
					ServerLogFormatClass.safe_text(room_code),
					ServerLogFormatClass.safe_text(str(target_value)),
					str(waiting_removed),
				]
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
				% [
					ServerLogFormatClass.safe_text(room_code),
					ServerLogFormatClass.safe_text(str(target_value)),
					release_r.error,
				]
		)
		return
	var release_payload: Dictionary = Dictionary(release_r.value) if release_r.value is Dictionary else {}
	if not bool(release_payload.get("released", false)):
		return
	var removed := bool(release_payload.get("removed", false))
	var room_after = release_payload.get("room", null)
	_mark_room_directory_dirty.call()
	if not removed and room_after != null:
		_broadcast_room_state.call(room_after)
	_broadcast_room_list.call("")
	GameLog.warn(
		"NetClient",
		"Released lobby reconnecting seat after disconnect grace room=%s seat=%s removed=%s"
			% [ServerLogFormatClass.safe_text(room_code), ServerLogFormatClass.safe_text(str(target_value)), str(removed)]
	)

func _handle_in_game_timeout(room, room_code: String, target_kind: String, target_value: String) -> void:
	if room.game_engine == null or str(room.status) != "InGame":
		return
	if str(target_kind).strip_edges() != "actor" or not str(target_value).is_valid_int():
		return
	var actor_id := int(target_value)

	var state = room.game_engine.get_state()
	if bool(_is_player_forfeited.call(state, actor_id)):
		return

	var cmd = CommandClass.create("forfeit_player", actor_id, {})
	var fr = room.game_engine.execute_command(cmd)
	if fr.ok:
		GameLog.warn(
			"NetClient",
			"Applied forfeit after disconnect grace room=%s actor=%d"
				% [ServerLogFormatClass.safe_text(room_code), actor_id]
		)
		_broadcast_command_applied.call(room, cmd)
		_drain_forfeited_auto_steps.call(room)
		_try_finalize_match.call(room)
		_broadcast_room_state.call(room)
		_broadcast_room_list.call("")
	else:
		GameLog.error(
			"NetClient",
			"forfeit_player failed after disconnect grace room=%s actor=%d err=%s"
				% [ServerLogFormatClass.safe_text(room_code), actor_id, fr.error]
		)
