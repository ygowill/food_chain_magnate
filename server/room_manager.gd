class_name RoomManager
extends RefCounted

const OnlineRoomClass = preload("res://server/room.gd")

const ROOM_CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const ROOM_CODE_MAX_ATTEMPTS := 64

var rooms: Dictionary = {} # room_code -> OnlineRoom
var peer_to_room: Dictionary = {} # peer_id -> room_code

var _rng: RandomNumberGenerator = null

func _init(rng: RandomNumberGenerator = null) -> void:
	if rng != null:
		_rng = rng
	else:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

func create_room(host_peer_id: int, profile: Dictionary, room_password: String, config: Dictionary) -> Result:
	if peer_to_room.has(host_peer_id):
		return Result.failure("Peer already in a room")

	var room_code := _generate_unique_room_code()
	if room_code.is_empty():
		return Result.failure("Failed to generate room code")

	var join_policy := "password" if not str(room_password).is_empty() else "public"
	var password_hash := _sha256_hex(room_password) if join_policy == "password" else ""
	var room = OnlineRoomClass.new(room_code, host_peer_id, join_policy, password_hash, config)
	room.owner_user_id = str(profile.get("user_id", "")).strip_edges()

	var ar: Result = room.add_peer(host_peer_id, profile)
	if not ar.ok:
		return ar

	rooms[room_code] = room
	peer_to_room[host_peer_id] = room_code

	return Result.success({
		"room_code": room_code,
		"room": room,
		"room_state": room.to_room_state_dict(),
	})

func create_room_with_code(
	host_peer_id: int,
	profile: Dictionary,
	room_code: String,
	config: Dictionary,
	join_policy: String = "public",
	password_hash: String = ""
) -> Result:
	if peer_to_room.has(host_peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)
	if rooms.has(code):
		return Result.failure("Room already exists: %s" % code)

	var normalized_join_policy := str(join_policy).strip_edges()
	if normalized_join_policy != "password":
		normalized_join_policy = "public"
	var normalized_password_hash := str(password_hash).strip_edges()
	if normalized_join_policy != "password":
		normalized_password_hash = ""
	elif normalized_password_hash.is_empty():
		return Result.failure("Missing password_hash for password room")
	var room = OnlineRoomClass.new(code, host_peer_id, normalized_join_policy, normalized_password_hash, config)
	room.owner_user_id = str(profile.get("user_id", "")).strip_edges()

	var ar: Result = room.add_peer(host_peer_id, profile)
	if not ar.ok:
		return ar

	rooms[code] = room
	peer_to_room[host_peer_id] = code

	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": "host",
	})

func join_room(peer_id: int, profile: Dictionary, room_code: String, room_password: String) -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	if room_code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(room_code, null)
	if room == null:
		return Result.failure("Room not found")

	if room.join_policy != "password" and room.join_policy != "public":
		return Result.failure("Unsupported join_policy: %s" % room.join_policy)
	if room.join_policy == "password" and room.is_password_required() and room.password_hash != _sha256_hex(room_password):
		return Result.failure("Invalid room_password")

	var ar: Result
	var role := "player"
	if str(room.status) == "InGame":
		ar = room.add_spectator(peer_id, profile)
		role = "spectator"
	else:
		if room.is_full():
			return Result.failure("Room is full")
		ar = room.add_peer(peer_id, profile)
	if not ar.ok:
		return ar

	var ar_value: Dictionary = Dictionary(ar.value) if ar.value is Dictionary else {}
	var replaced_peer_id := int(ar_value.get("replaced_peer_id", 0))
	if replaced_peer_id > 0:
		peer_to_room.erase(replaced_peer_id)
	peer_to_room[peer_id] = room_code

	return Result.success({
		"room_code": room_code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": role,
		"replaced_peer_id": replaced_peer_id,
	})

func join_room_with_seat(peer_id: int, profile: Dictionary, room_code: String, seat_index: int, role_label: String = "player") -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(code, null)
	if room == null:
		return Result.failure("Room not found")

	if str(room.status) != OnlineRoomClass.STATUS_LOBBY:
		return Result.failure("Room is not in Lobby")
	if room.is_full():
		return Result.failure("Room is full")
	if not room.has_method("add_peer_at_seat"):
		return Result.failure("Room.add_peer_at_seat missing")

	var ar: Result = room.add_peer_at_seat(peer_id, profile, seat_index)
	if not ar.ok:
		return ar

	peer_to_room[peer_id] = code
	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": str(role_label).strip_edges(),
	})

func reconnect_player(peer_id: int, profile: Dictionary, room_code: String, seat_index: int, user_id: String, role_label: String = "player") -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(code, null)
	if room == null:
		return Result.failure("Room not found")

	if not room.has_method("reconnect_player"):
		return Result.failure("Room.reconnect_player missing")
	var restore_host: bool = str(role_label).strip_edges() == "host"
	var rr: Result = room.reconnect_player(peer_id, profile, seat_index, user_id, restore_host)
	if not rr.ok:
		return rr
	var rr_value: Dictionary = Dictionary(rr.value) if rr.value is Dictionary else {}
	var replaced_peer_id := int(rr_value.get("replaced_peer_id", 0))
	if replaced_peer_id > 0:
		peer_to_room.erase(replaced_peer_id)

	peer_to_room[peer_id] = code
	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": str(role_label).strip_edges(),
		"replaced_peer_id": replaced_peer_id,
	})

func reclaim_room_seat(peer_id: int, profile: Dictionary, room_code: String, seat_index: int, user_id: String, role_label: String = "player") -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(code, null)
	if room == null:
		return Result.failure("Room not found")

	if not room.has_method("reclaim_peer_at_seat"):
		return Result.failure("Room.reclaim_peer_at_seat missing")
	var rr: Result = room.reclaim_peer_at_seat(peer_id, profile, seat_index, user_id)
	if not rr.ok:
		return rr
	var rr_value: Dictionary = Dictionary(rr.value) if rr.value is Dictionary else {}
	var replaced_peer_id := int(rr_value.get("replaced_peer_id", 0))
	if replaced_peer_id > 0:
		peer_to_room.erase(replaced_peer_id)

	peer_to_room[peer_id] = code
	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": str(role_label).strip_edges(),
		"replaced_peer_id": replaced_peer_id,
	})

func spectate_room(peer_id: int, profile: Dictionary, room_code: String) -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(code, null)
	if room == null:
		return Result.failure("Room not found")

	var ar: Result = room.add_spectator(peer_id, profile)
	if not ar.ok:
		return ar

	var ar_value: Dictionary = Dictionary(ar.value) if ar.value is Dictionary else {}
	var replaced_peer_id := int(ar_value.get("replaced_peer_id", 0))
	if replaced_peer_id > 0:
		peer_to_room.erase(replaced_peer_id)
	peer_to_room[peer_id] = code

	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": "spectator",
		"replaced_peer_id": replaced_peer_id,
	})

func list_room_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room_val in rooms.values():
		var room = room_val
		if room == null:
			continue
		if not room.has_method("to_room_summary_dict"):
			continue
		out.append(Dictionary(room.to_room_summary_dict()))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a.get("updated_at_ms", 0))
		var tb := int(b.get("updated_at_ms", 0))
		if ta != tb:
			return ta > tb
		return str(a.get("room_code", "")) > str(b.get("room_code", ""))
	)
	return out

func create_persistence_snapshot(include_runtime_membership: bool = false) -> Result:
	var room_codes: Array[String] = []
	for code_val in rooms.keys():
		var code := str(code_val).strip_edges().to_upper()
		if code.is_empty():
			continue
		room_codes.append(code)
	room_codes.sort()

	var persisted_rooms: Array[Dictionary] = []
	for room_code in room_codes:
		var room = rooms.get(room_code, null)
		if room == null:
			continue
		if str(room.status) != OnlineRoomClass.STATUS_IN_GAME and str(room.status) != OnlineRoomClass.STATUS_LOBBY:
			continue
		if not room.has_method("to_persistence_dict"):
			return Result.failure("Room.to_persistence_dict missing")
		var snapshot_r: Result = room.to_persistence_dict(include_runtime_membership)
		if not snapshot_r.ok:
			return Result.failure("persist room %s 失败: %s" % [room_code, snapshot_r.error])
		persisted_rooms.append(Dictionary(snapshot_r.value).duplicate(true))

	return Result.success({
		"version": 1,
		"saved_at_unix_sec": int(Time.get_unix_time_from_system()),
		"rooms": persisted_rooms,
	})

func restore_from_persistence(snapshot: Dictionary, allowed_room_codes: Array[String] = []) -> Result:
	var rooms_val = snapshot.get("rooms", null)
	if rooms_val == null:
		return Result.success({
			"restored_rooms": 0,
		})
	if not (rooms_val is Array):
		return Result.failure("snapshot.rooms 类型错误（期望 Array）")

	rooms = {}
	peer_to_room = {}
	var allow_all := allowed_room_codes.is_empty()
	var allowed_lookup: Dictionary = {}
	for code in allowed_room_codes:
		var normalized := str(code).strip_edges().to_upper()
		if normalized.is_empty():
			continue
		allowed_lookup[normalized] = true

	for item in Array(rooms_val):
		if not (item is Dictionary):
			return Result.failure("snapshot.rooms 元素类型错误（期望 Dictionary）")
		var room_dict: Dictionary = Dictionary(item)
		var room_code := str(room_dict.get("room_code", "")).strip_edges().to_upper()
		if not allow_all and not allowed_lookup.has(room_code):
			continue
		var restore_r: Result = OnlineRoomClass.from_persistence_dict(room_dict)
		if not restore_r.ok:
			return Result.failure("restore room 失败: %s" % restore_r.error)
		var room = restore_r.value
		if room == null:
			return Result.failure("restore room 返回空对象")
		var code := str(room.room_code).strip_edges().to_upper()
		if code.is_empty():
			return Result.failure("restore room 返回空 room_code")
		if rooms.has(code):
			return Result.failure("restore room 重复 room_code: %s" % code)
		rooms[code] = room

	return Result.success({
		"restored_rooms": rooms.size(),
	})

func leave_room(peer_id: int) -> Result:
	if not peer_to_room.has(peer_id):
		return Result.success({
			"room_code": "",
			"room": null,
			"removed": false,
			"room_state": null,
		})

	var room_code := str(peer_to_room.get(peer_id, ""))
	peer_to_room.erase(peer_id)

	var room = rooms.get(room_code, null)
	if room == null:
		rooms.erase(room_code)
		return Result.success({
			"room_code": room_code,
			"room": null,
			"removed": true,
			"room_state": null,
		})

	var rr: Result = room.remove_peer(peer_id)
	if not rr.ok:
		return rr

	if room.is_empty():
		rooms.erase(room_code)
		return Result.success({
			"room_code": room_code,
			"room": null,
			"removed": true,
			"room_state": null,
		})

	return Result.success({
		"room_code": room_code,
		"room": room,
		"removed": false,
		"room_state": room.to_room_state_dict(),
	})

func disconnect_peer(peer_id: int) -> Result:
	if not peer_to_room.has(peer_id):
		return Result.success({
			"room_code": "",
			"room": null,
			"removed": false,
			"room_state": null,
		})

	var room_code := str(peer_to_room.get(peer_id, ""))
	peer_to_room.erase(peer_id)

	var room = rooms.get(room_code, null)
	if room == null:
		rooms.erase(room_code)
		return Result.success({
			"room_code": room_code,
			"room": null,
			"removed": true,
			"room_state": null,
		})

	var dr: Result = room.disconnect_peer(peer_id)
	if not dr.ok:
		return dr

	# 若房间内已无任何在线成员（玩家/旁观者），优先按房间状态决定是否保留：
	# - Lobby：保留已占座房间，支持刷新/重连 reclaim。
	# - InGame：保留已开局房间，支持最后一名在线玩家掉线后的恢复。
	# 只有真正无保留价值的空房间才立刻清理，避免把进行中的恢复窗口直接删掉。
	var keep_reserved_lobby_room: bool = str(room.status) == OnlineRoomClass.STATUS_LOBBY and room.get_player_count() > 0
	var keep_reserved_in_game_room: bool = str(room.status) == OnlineRoomClass.STATUS_IN_GAME and room.get_player_count() > 0
	if room.get_peer_ids().is_empty() and not keep_reserved_lobby_room and not keep_reserved_in_game_room:
		rooms.erase(room_code)
		return Result.success({
			"room_code": room_code,
			"room": null,
			"removed": true,
			"room_state": null,
		})

	# 注意：InGame 断线保留座位（旁观者占位），因此通常不会为空；这里仍保持兜底清理。
	if room.is_empty():
		rooms.erase(room_code)
		return Result.success({
			"room_code": room_code,
			"room": null,
			"removed": true,
			"room_state": null,
		})

	return Result.success({
		"room_code": room_code,
		"room": room,
		"removed": false,
		"room_state": room.to_room_state_dict(),
	})

func release_reconnecting_seat(room_code: String, seat_index: int) -> Result:
	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(code, null)
	if room == null:
		return Result.success({
			"room_code": code,
			"room": null,
			"removed": true,
			"released": false,
			"room_state": null,
		})

	if not room.has_method("release_reconnecting_seat"):
		return Result.failure("Room.release_reconnecting_seat missing")
	var rr: Result = room.release_reconnecting_seat(seat_index)
	if not rr.ok:
		return rr

	var rr_value: Dictionary = Dictionary(rr.value) if rr.value is Dictionary else {}
	var released := bool(rr_value.get("released", false))
	if room.is_empty():
		rooms.erase(code)
		return Result.success({
			"room_code": code,
			"room": null,
			"removed": true,
			"released": released,
			"room_state": null,
		})

	return Result.success({
		"room_code": code,
		"room": room,
		"removed": false,
		"released": released,
		"room_state": room.to_room_state_dict(),
		"host_changed": bool(rr_value.get("host_changed", false)),
		"host_peer_id": int(rr_value.get("host_peer_id", 0)),
	})

func get_room_by_peer(peer_id: int):
	var room_code := str(peer_to_room.get(peer_id, ""))
	if room_code.is_empty():
		return null
	return rooms.get(room_code, null)

func _generate_unique_room_code() -> String:
	for _i in range(ROOM_CODE_MAX_ATTEMPTS):
		var code := _generate_room_code()
		if not rooms.has(code):
			return code
	return ""

func _generate_room_code() -> String:
	var out := ""
	for _i in range(ROOM_CODE_LENGTH):
		var idx := _rng.randi_range(0, ROOM_CODE_ALPHABET.length() - 1)
		out += ROOM_CODE_ALPHABET.substr(idx, 1)
	return out

func _sha256_hex(secret: String) -> String:
	if secret.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(secret.to_utf8_buffer())
	return ctx.finish().hex_encode()
