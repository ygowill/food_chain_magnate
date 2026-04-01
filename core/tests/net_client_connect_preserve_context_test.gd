# NetClient.connect_to_server：preserve_context 应保留联机 resume 上下文
class_name NetClientConnectPreserveContextTest
extends RefCounted

static func run() -> Result:
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
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

	NetClient.shutdown()
	NetContext.set_online_resume_context("ROOM77", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	var preserve_r = NetClient.connect_to_server("http://127.0.0.1:7000/ws?connect_token=test-token", true)
	if preserve_r.ok:
		NetClient.shutdown(false)
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"非法 ws_url 应立即失败，避免测试依赖真实网络环境"
		)
	if not NetContext.has_online_resume_context():
		NetClient.shutdown(false)
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"preserve_context=true 时不应清理 resume 上下文"
		)
	if NetContext.get_online_resume_room_code() != "ROOM77":
		NetClient.shutdown(false)
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"preserve_context=true 后 room_code 丢失: %s" % NetContext.get_online_resume_room_code()
		)

	NetClient.shutdown(false)
	NetContext.set_online_resume_context("ROOM88", "player", "https://platform.example.test")
	var clear_r = NetClient.connect_to_server("http://127.0.0.1:7000/ws?connect_token=test-token", false)
	if clear_r.ok:
		NetClient.shutdown(false)
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"非法 ws_url 应立即失败，避免测试依赖真实网络环境"
		)
	if NetContext.has_online_resume_context():
		NetClient.shutdown(false)
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"preserve_context=false 时应清理 resume 上下文"
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
	NetClient.shutdown(false)
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
