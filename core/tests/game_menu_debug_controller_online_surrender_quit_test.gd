# Game 菜单：联机对局主动返回主菜单应先发起即时 surrender
class_name GameMenuDebugControllerOnlineSurrenderQuitTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/menu/debug_controller.gd")

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

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"Main loop is not SceneTree"
		)

	var host := Node.new()
	(loop as SceneTree).root.add_child(host)

	var mock_net := _MockNetClient.new()
	var mock_scene_manager := _MockSceneManager.new()
	var mock_globals := _MockGlobals.new()
	var controller = ControllerClass.new(host, null, {
		"net_client": mock_net,
		"scene_manager": mock_scene_manager,
		"globals": mock_globals,
	})

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 1
	NetContext.server_url = "ws://quit.example.test"
	NetContext.connect_token = "quit-token"
	NetContext.room_state = {
		"room_code": "QUIT02",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("QUIT02", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	controller.quit_to_menu()

	if mock_net.forfeit_and_leave_requests.size() != 1:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"quit_to_menu 应发起一次 forfeit_and_leave，请求记录=%s" % str(mock_net.forfeit_and_leave_requests)
		)
	if NetContext.has_method("has_online_resume_context") and NetContext.has_online_resume_context():
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"发起即时 surrender 后，本地不应再保留可恢复上下文"
		)
	if mock_scene_manager.show_loading_messages.size() != 1:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"quit_to_menu 应显示 loading，一共调用=%d" % mock_scene_manager.show_loading_messages.size()
		)
	if mock_scene_manager.goto_main_menu_count != 0:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"在服务器确认前不应立即跳转主菜单"
		)

	mock_net.emit_signal("room_state_updated", {"room_code": "", "status": "Lobby"})
	await (loop as SceneTree).process_frame

	if mock_net.shutdown_args.size() != 1 or not bool(mock_net.shutdown_args[0]):
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"服务器确认后应调用 shutdown(true): %s" % str(mock_net.shutdown_args)
		)
	if mock_globals.reset_game_config_count != 1:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"服务器确认后应重置游戏配置，实际=%d" % mock_globals.reset_game_config_count
		)
	if mock_scene_manager.hide_loading_count != 1:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"服务器确认后应隐藏 loading，实际=%d" % mock_scene_manager.hide_loading_count
		)
	if mock_scene_manager.goto_main_menu_count != 1:
		return await _cleanup_and_fail(
			controller,
			host,
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"服务器确认后应跳转主菜单，实际=%d" % mock_scene_manager.goto_main_menu_count
		)

	controller.dispose()
	host.queue_free()
	await (loop as SceneTree).process_frame
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state
	)
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

static func _restore_and_fail(
	prev_mode,
	prev_local_player_id: int,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	message: String
) -> Result:
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state
	)
	return Result.failure(message)

static func _cleanup_and_fail(
	controller,
	host: Node,
	prev_mode,
	prev_local_player_id: int,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	message: String
) -> Result:
	if controller != null and controller.has_method("dispose"):
		controller.dispose()
	if host != null and is_instance_valid(host):
		host.queue_free()
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		await (loop as SceneTree).process_frame
	return _restore_and_fail(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		message
	)

class _MockNetClient:
	extends RefCounted

	signal room_state_updated(room_state: Dictionary)
	signal request_rejected(request_id: String, code: String, message: String)
	signal disconnected(reason: String)

	var forfeit_and_leave_requests: Array[String] = []
	var shutdown_args: Array[bool] = []
	var connected: bool = true

	func is_online_client_connected() -> bool:
		return connected

	func request_forfeit_and_leave_room() -> String:
		var request_id := "req_quit_1"
		forfeit_and_leave_requests.append(request_id)
		return request_id

	func shutdown(reset_context: bool = true) -> void:
		shutdown_args.append(bool(reset_context))

class _MockSceneManager:
	extends RefCounted

	var show_loading_messages: Array[String] = []
	var hide_loading_count: int = 0
	var goto_main_menu_count: int = 0

	func show_loading(message: String) -> void:
		show_loading_messages.append(str(message))

	func hide_loading() -> void:
		hide_loading_count += 1

	func goto_main_menu() -> void:
		goto_main_menu_count += 1

class _MockGlobals:
	extends RefCounted

	var reset_game_config_count: int = 0

	func reset_game_config() -> void:
		reset_game_config_count += 1
