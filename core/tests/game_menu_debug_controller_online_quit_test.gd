# Game 菜单：主动返回主菜单时应清理联机恢复上下文
class_name GameMenuDebugControllerOnlineQuitTest
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

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 1
	NetContext.server_url = "ws://quit.example.test"
	NetContext.connect_token = "quit-token"
	NetContext.room_state = {
		"room_code": "QUIT01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.room_list = [{
		"room_code": "QUIT01",
	}]
	NetContext.set_online_resume_context("QUIT01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	ControllerClass.cleanup_online_state_before_quit()

	if NetContext.mode != NetContext.Mode.HOTSEAT:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"返回主菜单时应退出 ONLINE_CLIENT，实际: %s" % str(NetContext.mode)
		)
	if NetContext.local_player_id != -1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"返回主菜单时应清理 local_player_id，实际: %d" % int(NetContext.local_player_id)
		)
	if not Dictionary(NetContext.room_state).is_empty():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"返回主菜单时应清理 room_state: %s" % str(NetContext.room_state)
		)
	if NetContext.has_method("has_online_resume_context") and NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"返回主菜单时不应保留 resume 上下文"
		)

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
