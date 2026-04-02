# 联机：主动退出应立即 forfeit 并离房
class_name OnlineForfeitAndLeaveRoomTest
extends RefCounted

const ServerLogicClass = preload("res://autoload/net_client/server.gd")
const RoomManagerClass = preload("res://server/room_manager.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	NetContext.mode = NetContext.Mode.ONLINE_SERVER

	var rm = RoomManagerClass.new()
	var mock_net := _MockNetClient.new(rm)
	mock_net._profile_by_peer_id[10] = {"name": "Host"}
	mock_net._profile_by_peer_id[11] = {"name": "P2"}

	var server = ServerLogicClass.new()
	server.setup(mock_net)

	var cfg := {
		"desired_player_count": 2,
		"seed_mode": "fixed",
		"seed": 12345,
		"allow_spectators": true,
		"enabled_modules_v2": [],
		"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
	}

	var cr: Result = rm.create_room(10, {"name": "Host", "color_index": 1}, "", cfg)
	if not cr.ok:
		_reset_net_context()
		return Result.failure("CreateRoom 失败: %s" % cr.error)
	var room_code := str(Dictionary(cr.value).get("room_code", ""))
	var jr: Result = rm.join_room(11, {"name": "P2", "color_index": 2}, room_code, "")
	if not jr.ok:
		_reset_net_context()
		return Result.failure("JoinRoom 失败: %s" % jr.error)

	var room = rm.rooms.get(room_code, null)
	if room == null:
		_reset_net_context()
		return Result.failure("room missing")
	var sr: Result = room.start_game()
	if not sr.ok:
		_reset_net_context()
		return Result.failure("StartGame 失败: %s" % sr.error)

	mock_net.multiplayer.remote_sender_id = 11
	server.handle_rpc_forfeit_and_leave_room({"request_id": "r_quit"})

	var state = room.game_engine.get_state() if room.game_engine != null else null
	if state == null:
		_reset_net_context()
		return Result.failure("state missing after forfeit-and-leave")
	if not bool(state.players[1].get("forfeited", false)):
		_reset_net_context()
		return Result.failure("主动退出后玩家应立刻 forfeited")
	if rm.peer_to_room.has(11):
		_reset_net_context()
		return Result.failure("主动退出后 peer_to_room 不应保留玩家 11")
	if room.player_id_by_peer_id.has(11):
		_reset_net_context()
		return Result.failure("主动退出后 player_id_by_peer_id 不应保留玩家 11")
	var peers: Array[int] = room.get_peer_ids()
	if peers.size() != 1 or peers[0] != 10:
		_reset_net_context()
		return Result.failure("主动退出后房间在线 peer 应只剩 host: %s" % str(peers))
	if int(room.get_player_count()) != 1:
		_reset_net_context()
		return Result.failure("主动退出后 room.get_player_count 应更新为 1，实际: %d" % int(room.get_player_count()))
	if not _has_empty_room_state_push(mock_net.sent, 11):
		_reset_net_context()
		return Result.failure("主动退出后 quitter 未收到 empty room_state")
	if not _has_room_state_push(mock_net.sent, 10, room_code):
		_reset_net_context()
		return Result.failure("主动退出后 host 未收到最新 room_state")

	_reset_net_context()
	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

class _MockMultiplayer:
	extends RefCounted

	var remote_sender_id: int = 0

	func get_remote_sender_id() -> int:
		return int(remote_sender_id)

class _MockNetClient:
	extends RefCounted

	var multiplayer := _MockMultiplayer.new()
	var _room_manager = null
	var _profile_by_peer_id: Dictionary = {}
	var sent: Array[Dictionary] = []
	var room_directory_dirty_count: int = 0

	func _init(room_manager) -> void:
		_room_manager = room_manager

	func rpc_id(peer_id: int, method: String, payload: Dictionary) -> void:
		sent.append({
			"peer_id": int(peer_id),
			"method": str(method),
			"payload": payload.duplicate(true),
		})

	func mark_server_room_directory_dirty() -> void:
		room_directory_dirty_count += 1

static func _has_empty_room_state_push(sent: Array[Dictionary], peer_id: int) -> bool:
	for item in sent:
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_room_state":
			continue
		var payload = item.get("payload", null)
		if not (payload is Dictionary):
			continue
		var room_state: Dictionary = Dictionary(payload)
		if str(room_state.get("room_code", "")).strip_edges().is_empty():
			return true
	return false

static func _has_room_state_push(sent: Array[Dictionary], peer_id: int, room_code: String) -> bool:
	for item in sent:
		if int(item.get("peer_id", -1)) != int(peer_id):
			continue
		if str(item.get("method", "")) != "rpc_room_state":
			continue
		var payload = item.get("payload", null)
		if not (payload is Dictionary):
			continue
		var room_state: Dictionary = Dictionary(payload)
		if str(room_state.get("room_code", "")).strip_edges().to_upper() == str(room_code).strip_edges().to_upper():
			return true
	return false
