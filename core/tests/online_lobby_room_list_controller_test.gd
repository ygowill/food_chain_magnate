class_name OnlineLobbyRoomListControllerTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/online/online_lobby_room_list_controller.gd")

class FakeLobby extends RefCounted:
	var rooms_list_container = null
	var current_room_code: String = ""

	func _get_current_room_code() -> String:
		return current_room_code

static func run() -> Result:
	var controller = ControllerClass.new()
	controller.setup(FakeLobby.new())

	var base_rooms: Array = [{
		"room_code": "ABCD12",
		"status": "Lobby",
		"desired_player_count": 4,
		"player_count": 1,
		"password_required": false,
		"allow_spectators": true,
		"host_name": "Host A",
		"updated_at_ms": 1000,
	}]
	var timestamp_only_changed: Array = [{
		"room_code": "ABCD12",
		"status": "Lobby",
		"desired_player_count": 4,
		"player_count": 1,
		"password_required": false,
		"allow_spectators": true,
		"host_name": "Host A",
		"updated_at_ms": 2000,
	}]
	if controller.has_visible_room_list_change(base_rooms, timestamp_only_changed):
		return Result.failure("仅 updated_at_ms 变化时不应触发房间列表重绘")

	var player_count_changed: Array = [{
		"room_code": "ABCD12",
		"status": "Lobby",
		"desired_player_count": 4,
		"player_count": 2,
		"password_required": false,
		"allow_spectators": true,
		"host_name": "Host A",
		"updated_at_ms": 3000,
	}]
	if not controller.has_visible_room_list_change(base_rooms, player_count_changed):
		return Result.failure("player_count 变化时应触发房间列表重绘")

	var host_name_changed: Array = [{
		"room_code": "ABCD12",
		"status": "Lobby",
		"desired_player_count": 4,
		"player_count": 1,
		"password_required": false,
		"allow_spectators": true,
		"host_name": "Host B",
		"updated_at_ms": 4000,
	}]
	if not controller.has_visible_room_list_change(base_rooms, host_name_changed):
		return Result.failure("host_name 变化时应触发房间列表重绘")

	return Result.success()
