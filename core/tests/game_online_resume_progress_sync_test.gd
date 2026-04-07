# GameOnlineResyncController：正常联机推进与快照恢复后应刷新本地 resume 游标
class_name GameOnlineResumeProgressSyncTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/controllers/online_resync_controller.gd")
const GameEngineClass = preload("res://core/engine/game_engine.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")

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
	var prev_pending_archive := Dictionary(NetClient._pending_resync_archive).duplicate(true) if NetClient != null else {}

	var server_engine = GameEngineClass.new()
	var init_server_r: Result = server_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_server_r.ok:
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
			"server engine 初始化失败: %s" % init_server_r.error
		)
	var setup_r: Result = TestPhaseUtilsClass.complete_setup(server_engine)
	if not setup_r.ok:
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
			"server complete_setup 失败: %s" % setup_r.error
		)

	var history: Array = server_engine.get_command_history()
	if history.size() < 2:
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
			"测试需要至少 2 条命令历史，实际: %d" % history.size()
		)

	var hash_probe = GameEngineClass.new()
	var init_probe_r: Result = hash_probe.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_probe_r.ok:
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
			"hash probe 初始化失败: %s" % init_probe_r.error
		)
	var hashes_by_sequence := {
		0: str(hash_probe.get_state().compute_hash()),
	}
	for cmd_val in history:
		var parsed_probe: Result = Command.from_dict(cmd_val.to_dict())
		if not parsed_probe.ok:
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
				"hash probe 命令解析失败: %s" % parsed_probe.error
			)
		var probe_cmd: Command = parsed_probe.value
		var exec_probe_r: Result = hash_probe.execute_command(probe_cmd, true)
		if not exec_probe_r.ok:
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
				"hash probe 命令执行失败: %s" % exec_probe_r.error
			)
		hashes_by_sequence[int(hash_probe.command_history.size())] = str(hash_probe.get_state().compute_hash())

	var partial_count := maxi(1, int(floor(float(history.size()) / 2.0)))
	var client_engine = GameEngineClass.new()
	var init_client_r: Result = client_engine.initialize(2, 12345, [], GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR, [], [-1, -1])
	if not init_client_r.ok:
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
			"client engine 初始化失败: %s" % init_client_r.error
		)
	for i in range(partial_count):
		var parsed_client: Result = Command.from_dict(history[i].to_dict())
		if not parsed_client.ok:
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
				"client partial 命令解析失败: %s" % parsed_client.error
			)
		var client_cmd: Command = parsed_client.value
		var exec_client_r: Result = client_engine.execute_command(client_cmd, true)
		if not exec_client_r.ok:
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
				"client partial 命令执行失败: %s" % exec_client_r.error
			)

	var host := Node.new()
	tree.root.add_child(host)
	var harness := _Harness.new(client_engine)
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

	Globals.set_current_game_engine(client_engine)
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "SYNC01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context("SYNC01", "player", "https://platform.example.test", NetContext.ONLINE_RESUME_TARGET_GAME)
	NetContext.mark_online_resume_in_game(true)
	NetContext.set_online_resume_progress(
		partial_count,
		str(hashes_by_sequence.get(partial_count, "")),
		"cp_sync_progress"
	)

	var next_cmd = history[partial_count]
	controller._on_online_command_applied(next_cmd.to_dict(), str(hashes_by_sequence.get(partial_count + 1, "")))
	if NetContext.get_online_resume_last_applied_sequence() != partial_count + 1:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"正常联机推进后未刷新 resume sequence: %d" % NetContext.get_online_resume_last_applied_sequence()
		)
	if NetContext.get_online_resume_last_state_hash() != str(hashes_by_sequence.get(partial_count + 1, "")):
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"正常联机推进后未刷新 resume hash: %s" % NetContext.get_online_resume_last_state_hash()
		)

	var archive_r = server_engine.create_archive()
	if not archive_r.ok:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"server archive 创建失败: %s" % archive_r.error
		)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var archive_probe = GameEngineClass.new()
	var archive_load_r: Result = archive_probe.load_from_archive(archive)
	if not archive_load_r.ok:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"快照恢复 probe 加载失败: %s" % archive_load_r.error
		)
	_apply_online_dinnertime_confirm_to_engine(archive_probe)
	var archive_hash := str(archive_probe.get_state().compute_hash()) if archive_probe.get_state() != null else ""
	if archive_hash.is_empty():
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"快照恢复 probe 缺少可比较的 state hash"
		)
	if NetClient != null:
		NetClient._pending_resync_archive = archive.duplicate(true)
	controller._on_online_resync_archive_received(archive)
	if NetContext.get_online_resume_last_applied_sequence() != history.size():
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"快照恢复后未刷新 resume sequence: %d" % NetContext.get_online_resume_last_applied_sequence(),
			prev_pending_archive
		)
	if NetContext.get_online_resume_last_state_hash() != archive_hash:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"快照恢复后未刷新 resume hash: %s" % NetContext.get_online_resume_last_state_hash(),
			prev_pending_archive
		)
	if NetClient != null and not Dictionary(NetClient._pending_resync_archive).is_empty():
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"快照恢复后未清理 pending archive",
			prev_pending_archive
		)

	var rewind_target := maxi(0, history.size() - 2)
	var rewind_archive: Dictionary = archive.duplicate(true)
	rewind_archive["current_index"] = rewind_target
	var rewind_probe = GameEngineClass.new()
	var rewind_load_r: Result = rewind_probe.load_from_archive(rewind_archive)
	if not rewind_load_r.ok:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"历史点 archive 加载失败: %s" % rewind_load_r.error,
			prev_pending_archive
		)
	_apply_online_dinnertime_confirm_to_engine(rewind_probe)
	var rewind_hash := str(rewind_probe.get_state().compute_hash()) if rewind_probe.get_state() != null else ""
	if rewind_hash.is_empty():
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"历史点 archive 缺少可比较的 state hash",
			prev_pending_archive
		)
	rewind_archive["final_hash"] = rewind_hash
	if NetClient != null:
		NetClient._pending_resync_archive = rewind_archive.duplicate(true)
	controller._on_online_resync_archive_received(rewind_archive)
	if NetContext.get_online_resume_last_applied_sequence() != rewind_target + 1:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"历史点快照恢复后未按 current_index 刷新 resume sequence: %d" % NetContext.get_online_resume_last_applied_sequence(),
			prev_pending_archive
		)
	if NetContext.get_online_resume_last_state_hash() != rewind_hash:
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"历史点快照恢复后未刷新 resume hash: %s" % NetContext.get_online_resume_last_state_hash(),
			prev_pending_archive
		)
	if NetClient != null and not Dictionary(NetClient._pending_resync_archive).is_empty():
		controller.dispose()
		host.queue_free()
		await tree.process_frame
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
			"历史点快照恢复后未清理 pending archive",
			prev_pending_archive
		)

	controller.dispose()
	host.queue_free()
	await tree.process_frame
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
		prev_pending_archive
	)
	return Result.success()

static func _apply_online_dinnertime_confirm_to_engine(engine) -> void:
	if engine == null or not engine.has_method("get_state"):
		return
	var state = engine.get_state()
	if state == null:
		return
	if not (state.rules is Dictionary):
		state.rules = {}
	state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1

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
	prev_pending_archive: Dictionary = {}
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
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
	if NetClient != null:
		NetClient._pending_resync_archive = prev_pending_archive.duplicate(true)

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
	message: String,
	prev_pending_archive: Dictionary = {}
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
		prev_pending_archive
	)
	return Result.failure(message)

class _Harness:
	extends RefCounted

	var _engine = null

	func _init(engine) -> void:
		_engine = engine

	func get_engine():
		return _engine

	func apply_timeline() -> void:
		pass

	func update_ui() -> void:
		pass

	func reset_timeline() -> void:
		pass

	func show_confirm(_title: String, _message: String, _on_confirm: Callable, _on_cancel: Callable, _confirm_text: String, _cancel_text: String) -> void:
		pass

	func goto_lobby() -> void:
		pass

	func show_loading(_message: String) -> void:
		pass

	func hide_loading() -> void:
		pass

	func resume_room_request(_room_code: String) -> Dictionary:
		return {}

	func connect_to_server(_url: String) -> Result:
		return Result.success()

	func shutdown_net(_reset_context: bool = false) -> void:
		pass

	func request_resync(_force_snapshot: bool = false) -> String:
		return ""
