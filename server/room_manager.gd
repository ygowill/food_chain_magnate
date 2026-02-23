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

	var password_hash := _sha256_hex(room_password)
	var join_policy := "password"
	var room = OnlineRoomClass.new(room_code, host_peer_id, join_policy, password_hash, config)

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

func create_room_with_code(host_peer_id: int, profile: Dictionary, room_code: String, config: Dictionary) -> Result:
	if peer_to_room.has(host_peer_id):
		return Result.failure("Peer already in a room")

	var code := str(room_code).strip_edges().to_upper()
	if code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)
	if rooms.has(code):
		return Result.failure("Room already exists: %s" % code)

	# 平台模式：后端已完成密码/权限校验；server 侧不再强依赖 room_password。
	var join_policy := "password"
	var password_hash := ""
	var room = OnlineRoomClass.new(code, host_peer_id, join_policy, password_hash, config)

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

	if room.join_policy != "password":
		return Result.failure("Unsupported join_policy: %s" % room.join_policy)
	if room.is_password_required() and room.password_hash != _sha256_hex(room_password):
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

	peer_to_room[peer_id] = room_code

	return Result.success({
		"room_code": room_code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": role,
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
	var rr: Result = room.reconnect_player(peer_id, profile, seat_index, user_id)
	if not rr.ok:
		return rr

	peer_to_room[peer_id] = code
	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": str(role_label).strip_edges(),
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

	peer_to_room[peer_id] = code

	return Result.success({
		"room_code": code,
		"room": room,
		"room_state": room.to_room_state_dict(),
		"role": "spectator",
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

	# 若房间内已无任何在线成员（玩家/旁观者），则直接清理房间，避免目录残留。
	# 注意：InGame 模式会保留掉线玩家的座位信息（用于占位/重连），因此不能仅用 is_empty() 判断。
	if room.get_peer_ids().is_empty():
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
