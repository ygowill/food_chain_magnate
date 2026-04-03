# NetContext：联机 resume 状态生命周期
class_name NetContextOnlineResumeTest
extends RefCounted

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)

	NetContext.reset()
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.set_online_resume_context("ab12cd", "player", "https://platform.example.test")

	if not NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"set_online_resume_context 后应存在 resume 上下文"
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
			"room_code 规范化失败: %s" % NetContext.get_online_resume_room_code()
		)
	if NetContext.get_online_resume_role() != "player":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"role 写入失败: %s" % NetContext.get_online_resume_role()
		)
	if NetContext.get_online_resume_platform_base_url() != "https://platform.example.test":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"platform_base_url 写入失败: %s" % NetContext.get_online_resume_platform_base_url()
		)
	if NetContext.is_online_resume_in_game():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"新建 resume 上下文不应默认处于 in_game"
		)

	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_reconnecting(true)
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
			"mark_online_resume_in_game(true) 未生效"
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
			"set_online_reconnecting(true) 未生效"
		)

	NetContext.mark_online_resume_in_game(false)
	if NetContext.is_online_resume_in_game():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"mark_online_resume_in_game(false) 未清理 in_game"
		)
	if NetContext.is_online_reconnecting():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"离开 in_game 时应同步清理 reconnecting"
		)

	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_resume_terminal("explicit_leave")
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
			"set_online_resume_terminal 后不应再视为可恢复上下文"
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
			"terminal 记录应保留 room_code"
		)
	if NetContext.get_online_resume_terminal_reason() != "explicit_leave":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"terminal_reason 写入失败: %s" % NetContext.get_online_resume_terminal_reason()
		)

	NetContext.clear_online_resume_context()
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
			"clear_online_resume_context 后仍存在上下文"
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
