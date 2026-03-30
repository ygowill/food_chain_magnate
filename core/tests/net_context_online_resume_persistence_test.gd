# NetContext：联机 resume 状态持久化
class_name NetContextOnlineResumePersistenceTest
extends RefCounted

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_save_path := ""
	if NetContext.has_method("get_online_resume_save_path"):
		prev_save_path = str(NetContext.get_online_resume_save_path())
	var prev_session_id := str(PlatformSession.session_id)
	var prev_user_id := str(PlatformSession.user_id)

	if not NetContext.has_method("set_online_resume_save_path_for_test"):
		return Result.failure("NetContext.set_online_resume_save_path_for_test missing")
	if not NetContext.has_method("reload_online_resume_state_from_disk"):
		return Result.failure("NetContext.reload_online_resume_state_from_disk missing")

	var test_path := "user://net_context_online_resume_persistence_test.cfg"
	NetContext.set_online_resume_save_path_for_test(test_path)
	PlatformSession.session_id = "sess_resume_persist"
	PlatformSession.user_id = "u_resume_persist"

	NetContext.reset()
	NetContext.set_online_resume_context("ab12cd", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_reconnecting(true)

	NetContext.online_resume_state = {}
	var reload_r: Result = NetContext.reload_online_resume_state_from_disk()
	if not reload_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"reload_online_resume_state_from_disk 失败: %s" % reload_r.error
		)

	if NetContext.get_online_resume_room_code() != "AB12CD":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"room_code 持久化恢复失败: %s" % NetContext.get_online_resume_room_code()
		)
	if not NetContext.is_online_resume_in_game():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"in_game 持久化恢复失败"
		)
	if not NetContext.is_online_reconnecting():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"reconnecting 持久化恢复失败"
		)
	if NetContext.get_online_resume_session_id() != "sess_resume_persist":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"session_id 持久化恢复失败: %s" % NetContext.get_online_resume_session_id()
		)
	if NetContext.get_online_resume_user_id() != "u_resume_persist":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"user_id 持久化恢复失败: %s" % NetContext.get_online_resume_user_id()
		)

	NetContext.clear_online_resume_context()
	NetContext.online_resume_state = {
		"room_code": "SHOULD_CLEAR",
	}
	var reload_empty_r: Result = NetContext.reload_online_resume_state_from_disk()
	if not reload_empty_r.ok:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"reload empty 状态失败: %s" % reload_empty_r.error
		)
	if NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_save_path,
			prev_session_id,
			prev_user_id,
			"clear 后不应恢复出旧 resume 上下文"
		)

	_restore(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_save_path,
		prev_session_id,
		prev_user_id
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
	prev_resume_state: Dictionary,
	prev_save_path: String,
	prev_session_id: String,
	prev_user_id: String
) -> void:
	if NetContext.has_method("set_online_resume_save_path_for_test"):
		NetContext.set_online_resume_save_path_for_test(prev_save_path)
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	PlatformSession.session_id = prev_session_id
	PlatformSession.user_id = prev_user_id
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
	prev_save_path: String,
	prev_session_id: String,
	prev_user_id: String,
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
		prev_resume_state,
		prev_save_path,
		prev_session_id,
		prev_user_id
	)
	return Result.failure(message)
