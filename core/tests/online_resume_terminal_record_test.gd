# 联机恢复：主动 leave/forfeit 应写入终态，后续空 room_state 不应抹掉终态记录
class_name OnlineResumeTerminalRecordTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if OnlineSessionCoordinator == null:
		return Result.failure("OnlineSessionCoordinator autoload missing")

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)

	var client := ClientLogicClass.new()
	var mock_net := _MockNet.new()
	client.setup(mock_net)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.set_online_resume_context("leave01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var leave_request_id := str(OnlineSessionCoordinator.request_leave_room(mock_net))
	if leave_request_id != "leave_req_1":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"request_leave_room 返回 request_id 错误: %s" % leave_request_id
		)
	if mock_net.leave_requests.size() != 1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"request_leave_room 未透传到底层 net: %s" % str(mock_net.leave_requests)
		)
	if NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 leave 后不应再保留可恢复上下文"
		)
	if not NetContext.has_online_resume_record():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 leave 后应保留终态记录"
		)
	if NetContext.get_online_resume_terminal_reason() != "leave_room":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 leave 后终态原因错误: %s" % NetContext.get_online_resume_terminal_reason()
		)
	if NetContext.get_online_resume_room_code() != "LEAVE01":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 leave 后应保留 room_code，实际: %s" % NetContext.get_online_resume_room_code()
		)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.set_online_resume_context("forfeit01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	var forfeit_request_id := str(OnlineSessionCoordinator.request_forfeit_and_leave_room(mock_net))
	if forfeit_request_id != "forfeit_req_1":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"request_forfeit_and_leave_room 返回 request_id 错误: %s" % forfeit_request_id
		)
	if mock_net.forfeit_requests.size() != 1:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"request_forfeit_and_leave_room 未透传到底层 net: %s" % str(mock_net.forfeit_requests)
		)
	if NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 forfeit 后不应再保留可恢复上下文"
		)
	if not NetContext.has_online_resume_record():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 forfeit 后应保留终态记录"
		)
	if NetContext.get_online_resume_terminal_reason() != "forfeit_and_leave_room":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"主动 forfeit 后终态原因错误: %s" % NetContext.get_online_resume_terminal_reason()
		)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.set_online_resume_context("clear01", "player", "https://platform.example.test")
	client.handle_rpc_room_state({})
	if NetContext.has_online_resume_record():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"普通空 room_state 应清理可恢复记录"
		)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.set_online_resume_context("term01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_resume_terminal("leave_room")
	client.handle_rpc_room_state({})
	if not NetContext.has_online_resume_record():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"终态记录遇到空 room_state 后不应被清理"
		)
	if NetContext.has_online_resume_context():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"终态记录不应重新变为可恢复上下文"
		)
	if NetContext.get_online_resume_room_code() != "TERM01":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"空 room_state 后应保留终态 room_code，实际: %s" % NetContext.get_online_resume_room_code()
		)
	if NetContext.get_online_resume_terminal_reason() != "leave_room":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_local_role,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"空 room_state 后终态原因丢失: %s" % NetContext.get_online_resume_terminal_reason()
		)

	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
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
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary
) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.local_role = prev_local_role
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
	prev_local_role: String,
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
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state
	)
	return Result.failure(message)

class _MockNet:
	extends RefCounted

	signal room_state_updated(room_state: Dictionary)

	var leave_requests: Array[String] = []
	var forfeit_requests: Array[String] = []

	func request_leave_room() -> String:
		var request_id := "leave_req_1"
		leave_requests.append(request_id)
		return request_id

	func request_forfeit_and_leave_room() -> String:
		var request_id := "forfeit_req_1"
		forfeit_requests.append(request_id)
		return request_id
