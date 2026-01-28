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

func join_room(peer_id: int, profile: Dictionary, room_code: String, room_password: String) -> Result:
	if peer_to_room.has(peer_id):
		return Result.failure("Peer already in a room")

	if room_code.is_empty():
		return Result.failure("Missing room_code", Result.ErrorCode.MISSING_PARAMS)

	var room = rooms.get(room_code, null)
	if room == null:
		return Result.failure("Room not found")
	if room.is_full():
		return Result.failure("Room is full")

	if room.join_policy != "password":
		return Result.failure("Unsupported join_policy: %s" % room.join_policy)
	if room.password_hash != _sha256_hex(room_password):
		return Result.failure("Invalid room_password")

	var ar: Result = room.add_peer(peer_id, profile)
	if not ar.ok:
		return ar

	peer_to_room[peer_id] = room_code

	return Result.success({
		"room_code": room_code,
		"room": room,
		"room_state": room.to_room_state_dict(),
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
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(secret.to_utf8_buffer())
	return ctx.finish().hex_encode()
