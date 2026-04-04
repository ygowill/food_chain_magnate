# GameOnlineResyncController：断线后在原场景内重连并恢复
class_name GameOnlineResyncReconnectFlowTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if PlatformSession == null:
		return Result.failure("PlatformSession autoload missing")

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return Result.failure("Main loop is not SceneTree")
	var tree: SceneTree = loop

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	var prev_session_id := str(PlatformSession.session_id)
	var prev_user_id := str(PlatformSession.user_id)
	var prev_is_guest := bool(PlatformSession.is_guest)
	var prev_display_name := str(PlatformSession.display_name)

	var host := Node.new()
	tree.root.add_child(host)

	var engine = GameEngineClass.new()
	var init_r: Result = engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_r.ok:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"初始化测试 engine 失败: %s" % init_r.error
		)
	var archive_r = engine.create_archive()
	if not archive_r.ok:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"创建测试 archive 失败: %s" % archive_r.error
		)
	Globals.set_current_game_engine(engine)

	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "ROOM03",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	PlatformSession.session_id = "sess_reconnect_test"
	PlatformSession.user_id = "u_reconnect_test"
	PlatformSession.is_guest = true
	PlatformSession.display_name = "游客#1234"
	NetContext.set_online_resume_context("ROOM03", "player", "https://platform.example.test")
	NetContext.mark_online_resume_in_game(true)

	var harness := _Harness.new(host, engine, Dictionary(archive_r.value).duplicate(true))
	var controller = ControllerClass.new(
		host,
		null,
		Callable(harness, "get_engine"),
		Callable(harness, "apply_timeline"),
		Callable(harness, "update_ui"),
		Callable(harness, "reset_timeline"),
		Callable(harness, "show_confirm"),
		Callable(harness, "goto_lobby"),
		Callable(harness, "show_loading"),
		Callable(harness, "hide_loading"),
		Callable(harness, "resume_room_request"),
		Callable(harness, "connect_to_server"),
		Callable(harness, "shutdown_net"),
		Callable(harness, "request_resync")
	)

	controller._on_online_disconnected("server_disconnected")
	await tree.process_frame
	await tree.process_frame
	controller._on_online_connected()
	await tree.process_frame
	controller._on_online_resync_archive_received(Dictionary(archive_r.value).duplicate(true))
	await tree.process_frame
	await tree.process_frame

	if harness.resume_calls != 1:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"resume_room_request 调用次数错误: %d" % harness.resume_calls
		)
	if harness.connect_urls.size() != 1:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"connect_to_server 调用次数错误: %s" % str(harness.connect_urls)
		)
	if harness.goto_lobby_calls != 0:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"重连成功后不应返回大厅"
		)
	if harness.hide_loading_calls <= 0:
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"重连成功后应隐藏 loading"
		)
	if NetContext.is_online_reconnecting():
		host.queue_free()
		return _restore_and_fail(
			prev_mode,
			prev_local_player_id,
			prev_server_url,
			prev_connect_token,
			prev_room_state,
			prev_room_list,
			prev_player_profile,
			prev_resume_state,
			prev_engine,
			prev_is_game_active,
			prev_session_id,
			prev_user_id,
			prev_is_guest,
			prev_display_name,
			"重连成功后应清理 reconnecting 状态"
		)

	host.queue_free()
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_engine,
		prev_is_game_active,
		prev_session_id,
		prev_user_id,
		prev_is_guest,
		prev_display_name
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
	prev_engine,
	prev_is_game_active: bool,
	prev_session_id: String,
	prev_user_id: String,
	prev_is_guest: bool,
	prev_display_name: String
) -> void:
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
	NetContext.server_url = prev_server_url
	NetContext.connect_token = prev_connect_token
	NetContext.room_state = prev_room_state.duplicate(true)
	NetContext.room_list = prev_room_list.duplicate(true)
	NetContext.player_profile = prev_player_profile.duplicate(true)
	NetContext.online_resume_state = prev_resume_state.duplicate(true)
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
	PlatformSession.session_id = prev_session_id
	PlatformSession.user_id = prev_user_id
	PlatformSession.is_guest = prev_is_guest
	PlatformSession.display_name = prev_display_name

static func _restore_and_fail(
	prev_mode,
	prev_local_player_id: int,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool,
	prev_session_id: String,
	prev_user_id: String,
	prev_is_guest: bool,
	prev_display_name: String,
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
		prev_engine,
		prev_is_game_active,
		prev_session_id,
		prev_user_id,
		prev_is_guest,
		prev_display_name
	)
	return Result.failure(message)

class _Harness:
	extends RefCounted

	var _host: Node = null
	var _engine = null
	var _archive: Dictionary = {}

	var resume_calls: int = 0
	var connect_urls: Array[String] = []
	var shutdown_reset_args: Array[bool] = []
	var request_resync_calls: int = 0
	var goto_lobby_calls: int = 0
	var show_confirm_calls: int = 0
	var loading_messages: Array[String] = []
	var hide_loading_calls: int = 0
	var update_ui_calls: int = 0
	var reset_timeline_calls: int = 0

	func _init(host: Node, engine, archive: Dictionary) -> void:
		_host = host
		_engine = engine
		_archive = archive.duplicate(true)

	func get_engine():
		return _engine

	func apply_timeline() -> void:
		pass

	func update_ui() -> void:
		update_ui_calls += 1

	func reset_timeline() -> void:
		reset_timeline_calls += 1

	func show_confirm(_title: String, _body: String, _confirmed: Callable, _cancelled: Callable, _ok: String, _close: String) -> void:
		show_confirm_calls += 1

	func goto_lobby() -> void:
		goto_lobby_calls += 1

	func show_loading(message: String) -> void:
		loading_messages.append(str(message))

	func hide_loading() -> void:
		hide_loading_calls += 1

	func resume_room_request(_room_code: String) -> Dictionary:
		resume_calls += 1
		return {
			"ok": {
				"room_code": "ROOM03",
				"ws_url": "ws://resume.example.test",
				"connect_token": "resume-token",
			},
		}

	func connect_to_server(url: String) -> Result:
		connect_urls.append(str(url))
		return Result.success()

	func shutdown_net(reset_context: bool = false) -> void:
		shutdown_reset_args.append(bool(reset_context))

	func request_resync(_force_snapshot: bool = false) -> String:
		request_resync_calls += 1
		return "mock_resync_%d" % request_resync_calls
