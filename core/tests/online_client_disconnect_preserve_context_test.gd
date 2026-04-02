# Online client：意外断线时保留/清理上下文策略
class_name OnlineClientDisconnectPreserveContextTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")

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

	var client = ClientLogicClass.new()

	NetContext.reset()
	NetContext.set_online_resume_context("ROOM_LOBBY", "player", "https://platform.example.test")
	if NetClient == null or not NetClient.should_preserve_online_context_on_disconnect():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"Lobby resume 上下文存在时应保留联机上下文"
		)
	NetContext.clear_online_resume_context()
	if NetClient != null and NetClient.should_preserve_online_context_on_disconnect():
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"无 resume 上下文时不应保留联机上下文"
		)

	var resumable_net := _MockNet.new()
	var resumable_reasons: Array[String] = []
	resumable_net.disconnected.connect(func(reason: String) -> void:
		resumable_reasons.append(reason)
	)
	client.setup(resumable_net)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = "ws://resume.test"
	NetContext.set_online_resume_context("ROOM01", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)
	resumable_net.preserve_disconnect = true
	client.on_server_disconnected()

	if resumable_reasons.size() != 1 or resumable_reasons[0] != "server_disconnected":
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"server_disconnected 未正确发出: %s" % str(resumable_reasons)
		)
	if resumable_net.shutdown_args.size() != 1 or bool(resumable_net.shutdown_args[0]) != false:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"可恢复断线应调用 shutdown(false): %s" % str(resumable_net.shutdown_args)
		)

	var non_resumable_net := _MockNet.new()
	client.setup(non_resumable_net)
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.server_url = "ws://non-resume.test"
	non_resumable_net.preserve_disconnect = false
	client.on_connection_failed()

	if non_resumable_net.shutdown_args.size() != 1 or bool(non_resumable_net.shutdown_args[0]) != true:
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			"非恢复场景应调用 shutdown(true): %s" % str(non_resumable_net.shutdown_args)
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

class _MockNet:
	extends RefCounted

	signal disconnected(reason: String)

	var _client_transport_connected: bool = false
	var shutdown_args: Array[bool] = []
	var preserve_disconnect: bool = false

	func shutdown(reset_context: bool = true) -> void:
		shutdown_args.append(bool(reset_context))

	func should_preserve_online_context_on_disconnect() -> bool:
		return preserve_disconnect
