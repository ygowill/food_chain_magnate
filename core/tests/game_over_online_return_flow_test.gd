# GameOver 在线结束返回：应等待 leave_room 的空 room_state 确认后再跳转联机大厅
class_name GameOverOnlineReturnFlowTest
extends RefCounted

const EndPanelsClass = preload("res://ui/scenes/game/panel/end_panels.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode = NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 1
	NetContext.room_state = {
		"room_code": "FLOW01",
		"status": "InGame",
	}
	NetContext.set_online_resume_context("FLOW01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	var mock_scene_manager := _MockSceneManager.new()
	var mock_net := _MockNetClient.new()
	var mock_globals := _MockGlobals.new()

	var panels = EndPanelsClass.new(
		null,
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		{
			"net_client": mock_net,
			"scene_manager": mock_scene_manager,
			"globals": mock_globals,
		}
	)
	panels._on_game_over_return()

	if mock_net.request_leave_room_calls != 1:
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("GameOver 返回应请求一次 leave_room")
	if mock_scene_manager.goto_online_lobby_count != 0:
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("leave_room 尚未确认前不应立即跳转联机大厅")
	if not mock_net.room_state_updated.is_connected(Callable(panels, "_on_online_game_over_leave_room_state_updated")):
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("GameOver 返回后应监听 room_state_updated 等待离房确认")

	mock_net.emit_signal("room_state_updated", {"room_code": "FLOW01", "status": "InGame"})
	if mock_scene_manager.goto_online_lobby_count != 0:
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("收到非空 room_state 时不应提前跳转联机大厅")

	mock_net.emit_signal("room_state_updated", {})
	if mock_scene_manager.goto_online_lobby_count != 1:
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("收到空 room_state 后应跳转联机大厅")
	if mock_globals.reset_game_config_calls != 1:
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("返回大厅前应重置游戏配置")
	if mock_net.room_state_updated.is_connected(Callable(panels, "_on_online_game_over_leave_room_state_updated")):
		_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
		return Result.failure("完成跳转后应解除 room_state_updated 监听")

	panels.dispose()
	_restore(prev_mode, prev_local_player_id, prev_server_url, prev_connect_token, prev_room_state, prev_room_list, prev_player_profile, prev_resume_state)
	return Result.success()

static func _restore(
	prev_mode,
	prev_local_player_id: int,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary
) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	if NetContext.has_method("save_online_resume_state_to_disk"):
		NetContext.save_online_resume_state_to_disk()

class _MockSceneManager:
	extends RefCounted

	var show_loading_count: int = 0
	var hide_loading_count: int = 0
	var goto_online_lobby_count: int = 0

	func show_loading(_message: String = "") -> void:
		show_loading_count += 1

	func hide_loading() -> void:
		hide_loading_count += 1

	func goto_online_lobby() -> void:
		goto_online_lobby_count += 1

class _MockGlobals:
	extends RefCounted

	var reset_game_config_calls: int = 0

	func reset_game_config() -> void:
		reset_game_config_calls += 1

class _MockNetClient:
	extends RefCounted

	signal room_state_updated(room_state: Dictionary)

	var request_leave_room_calls: int = 0

	func request_leave_room() -> String:
		request_leave_room_calls += 1
		return "leave_req_1"
