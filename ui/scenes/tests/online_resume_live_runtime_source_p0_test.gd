class_name OnlineResumeLiveRuntimeSourceP0Test
extends RefCounted

const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")
const OnlineResumeRuntimeAnchorLiveSyncTestClass = preload("res://core/tests/online_resume_runtime_anchor_live_sync_test.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")

class _CallbackHost:
	extends RefCounted

	var runtime_engine: GameEngine = null
	var display_engine: GameEngine = null
	var update_count: int = 0

	func _init(engine: GameEngine) -> void:
		runtime_engine = engine
		display_engine = engine

	func get_game_engine():
		return runtime_engine

	func get_runtime_game_engine():
		return runtime_engine

	func set_active_game_engine(engine: GameEngine) -> void:
		runtime_engine = engine
		display_engine = engine

	func set_display_game_engine(engine: GameEngine) -> void:
		display_engine = engine

	func update_ui() -> void:
		update_count += 1

	func show_confirm(_title: String, _message: String, _confirm: Callable, _cancel: Callable) -> void:
		pass

	func show_game_log_panel_in_right_panel() -> void:
		pass

	func open_replay_load_dialog() -> void:
		pass

	func get_online_resync_in_progress() -> bool:
		return false

class _CommandCapture:
	extends RefCounted

	var last_cmd: Dictionary = {}
	var last_state_hash: String = ""

	func on_command_applied(cmd_dict: Dictionary, state_hash: String) -> void:
		last_cmd = Dictionary(cmd_dict).duplicate(true)
		last_state_hash = str(state_hash)

class _FakeGameLogPanel:
	extends Control

	signal log_entry_clicked(entry_id: int)
	signal timeline_seek_requested(timeline_index: int)
	signal replay_toggle_changed(active: bool)

	var _timeline: Dictionary = {}
	var _entries: Array[Dictionary] = []
	var _head_index: int = -1
	var _cursor_index: int = -1
	var _replay_toggle_available: bool = true
	var _replay_toggle_text: String = ""
	var _replay_toggle_reason: String = ""
	var load_step_timeline_call_count: int = 0
	var append_step_timeline_call_count: int = 0
	var last_update_mode: String = ""

	func has_step_timeline_loaded() -> bool:
		return not _timeline.is_empty() and _timeline.get("steps", null) is Array

	func load_step_timeline(timeline: Dictionary, entries: Array[Dictionary], _reset_extra_entries: bool = false) -> void:
		load_step_timeline_call_count += 1
		last_update_mode = "load"
		_timeline = Dictionary(timeline).duplicate(true)
		_entries.clear()
		for entry_val in entries:
			if entry_val is Dictionary:
				_entries.append(Dictionary(entry_val).duplicate(true))

	func append_step_timeline(timeline: Dictionary, appended_entries: Array[Dictionary], _reset_extra_entries: bool = false) -> bool:
		if not has_step_timeline_loaded():
			return false
		append_step_timeline_call_count += 1
		last_update_mode = "append"
		_timeline = Dictionary(timeline).duplicate(true)
		for entry_val in appended_entries:
			if entry_val is Dictionary:
				_entries.append(Dictionary(entry_val).duplicate(true))
		return true

	func load_entries(entries: Array[Dictionary]) -> void:
		_entries.clear()
		for entry_val in entries:
			if entry_val is Dictionary:
				_entries.append(Dictionary(entry_val).duplicate(true))

	func get_step_timeline_entries() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for entry_val in _entries:
			if entry_val is Dictionary:
				out.append(Dictionary(entry_val).duplicate(true))
		return out

	func set_timeline_head(head_index: int) -> void:
		_head_index = int(head_index)

	func set_timeline_cursor(cursor_index: int) -> void:
		_cursor_index = int(cursor_index)

	func set_timeline_head_cursor(head_index: int, cursor_index: int) -> void:
		_head_index = int(head_index)
		_cursor_index = int(cursor_index)

	func set_replay_toggle_availability(available: bool, inactive_text: String, disabled_reason: String) -> void:
		_replay_toggle_available = bool(available)
		_replay_toggle_text = str(inactive_text)
		_replay_toggle_reason = str(disabled_reason)

	func get_replay_bar():
		return null

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")
	if NetClient == null:
		return Result.failure("NetClient autoload missing")
	if Globals == null:
		return Result.failure("Globals autoload missing")
	if EventBus == null:
		return Result.failure("EventBus autoload missing")

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		return Result.failure("SceneTree.root 不可用")

	var prev_mode := NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)
	var prev_local_role := str(NetContext.local_role)
	var prev_server_url := str(NetContext.server_url)
	var prev_connect_token := str(NetContext.connect_token)
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)
	var prev_room_list := Array(NetContext.room_list).duplicate(true)
	var prev_player_profile := Dictionary(NetContext.player_profile).duplicate(true)
	var prev_resume_state := Dictionary(NetContext.online_resume_state).duplicate(true)
	var prev_engine = Globals.current_game_engine
	var prev_is_game_active := bool(Globals.is_game_active)
	var prev_event_history := EventBus.get_history()

	var build_r := OnlineResumeRuntimeAnchorLiveSyncTestClass._build_resume_point_and_follow_up_history()
	if not build_r.ok:
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"构造恢复房 bundle 失败: %s" % build_r.error
		)
	var build_info: Dictionary = Dictionary(build_r.value)
	var bundle: Dictionary = Dictionary(build_info.get("bundle", {})).duplicate(true)
	var next_cmd: Dictionary = Dictionary(build_info.get("next_cmd", {})).duplicate(true)
	var runtime_history_size := int(build_info.get("runtime_history_size", -1))
	if next_cmd.is_empty():
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"测试 follow-up 命令缺失"
		)

	NetClient.shutdown()
	EventBus.clear_history_and_reset_sequence()
	Globals.current_game_engine = null
	Globals.is_game_active = false
	NetContext.reset()
	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "P0RT01",
		"room_mode": "resume_archive",
		"status": "InGame",
		"self_seat_index": 0,
		"self_role": "player",
		"players": [],
		"spectators": [],
	}
	NetContext.set_online_resume_context(
		"P0RT01",
		"player",
		"https://platform.example.test",
		NetContext.ONLINE_RESUME_TARGET_GAME
	)
	NetContext.mark_online_resume_in_game(true)

	NetClient.rpc_game_started({
		"player_id_by_peer_id": {
			7: 0,
			8: 1,
		},
		"local_player_id": 0,
		"config": {
			"desired_player_count": 2,
			"seed": 12345,
			"allow_spectators": true,
			"enabled_modules_v2": [],
			"modules_v2_base_dir": GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR,
			"restaurant_logo_choices_by_player": [-1, -1],
		},
		"resume_fast_start_bundle": bundle,
	})
	await tree.process_frame

	var runtime_engine = Globals.current_game_engine
	if runtime_engine == null or runtime_engine.get_state() == null:
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"fast-start 后 runtime_engine 缺失"
		)

	var ensure_history_r := NetClient.ensure_online_resume_full_history_timeline_current(false)
	if not ensure_history_r.ok:
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"构建完整历史失败: %s" % ensure_history_r.error
		)
	var snapshot := NetClient.get_online_resume_session_snapshot()
	if not bool(snapshot.get("full_replay_ready", false)):
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"完整历史应已就绪"
		)
	var cached_history_entries := NetClient.get_online_resume_full_replay_step_timeline_entries()
	if cached_history_entries.is_empty():
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"完整历史 entries cache 应已就绪"
		)

	var host := Control.new()
	tree.root.add_child(host)
	var game_log_panel := _FakeGameLogPanel.new()
	host.add_child(game_log_panel)
	var action_panel := Control.new()
	host.add_child(action_panel)
	await tree.process_frame

	var callbacks := _CallbackHost.new(runtime_engine)
	var controller := GameTimelineControllerClass.new(
		host,
		game_log_panel,
		action_panel,
		Callable(callbacks, "get_game_engine"),
		Callable(callbacks, "get_runtime_game_engine"),
		Callable(callbacks, "set_active_game_engine"),
		Callable(callbacks, "set_display_game_engine"),
		Callable(callbacks, "update_ui"),
		Callable(callbacks, "show_confirm"),
		Callable(callbacks, "show_game_log_panel_in_right_panel"),
		Callable(callbacks, "open_replay_load_dialog"),
		Callable(callbacks, "get_online_resync_in_progress")
	)
	controller.initialize()
	controller.apply_live_log_timeline_from_engine(true)

	if str(controller._history_timeline_source) != "runtime":
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"P0 失败：live 日志默认源应为 runtime，实际=%s" % str(controller._history_timeline_source)
		)
	if bool(controller._live_history_uses_global_timeline):
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"首次 live 构建不应直接进入 global baseline 模式"
		)
	var runtime_only_entries := game_log_panel.get_step_timeline_entries()
	if runtime_only_entries.is_empty():
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"首次 live 构建仍应先显示 runtime 日志"
		)

	var hydrated := await _wait_until(func() -> bool:
		return bool(controller._live_history_uses_global_timeline)
	, tree, 30)
	if not hydrated:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"完整历史 ready 后应异步补完默认 live 日志 baseline"
		)
	var displayed_entries := game_log_panel.get_step_timeline_entries()
	if displayed_entries.size() != cached_history_entries.size():
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"baseline 补完后默认日志应显示完整历史前缀：displayed=%d cached=%d"
				% [displayed_entries.size(), cached_history_entries.size()]
		)
	if displayed_entries.size() < runtime_only_entries.size():
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"baseline 补完后条目数不应少于 runtime-only：runtime=%d merged=%d"
				% [runtime_only_entries.size(), displayed_entries.size()]
		)

	var entries_before_append_count := displayed_entries.size()
	var load_count_before_append := int(game_log_panel.load_step_timeline_call_count)
	var append_count_before_append := int(game_log_panel.append_step_timeline_call_count)
	var capture := _CommandCapture.new()
	var capture_cb := Callable(capture, "on_command_applied")
	if NetClient.command_applied.is_connected(capture_cb):
		NetClient.command_applied.disconnect(capture_cb)
	NetClient.command_applied.connect(capture_cb)
	NetClient.rpc_command_applied({
		"cmd": next_cmd,
		"state_hash": "",
	})
	if NetClient.command_applied.is_connected(capture_cb):
		NetClient.command_applied.disconnect(capture_cb)
	if capture.last_cmd.is_empty():
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 命令应先被翻译成 runtime cmd"
		)
	var parsed_follow_up_r := Command.from_dict(capture.last_cmd)
	if not parsed_follow_up_r.ok:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up runtime cmd 解析失败: %s" % parsed_follow_up_r.error
		)
	var follow_up_cmd: Command = parsed_follow_up_r.value
	var follow_up_apply_r: Result = runtime_engine.execute_command(follow_up_cmd, true)
	if not follow_up_apply_r.ok:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up runtime cmd 执行失败: %s" % follow_up_apply_r.error
		)
	NetClient.record_online_resume_runtime_command_applied(capture.last_cmd, capture.last_state_hash)
	if runtime_history_size >= 0 and runtime_engine.command_history.size() != runtime_history_size + 1:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 命令后 runtime history size 应 +1：actual=%d expected=%d"
				% [runtime_engine.command_history.size(), runtime_history_size + 1]
		)
	controller.apply_live_log_timeline_from_engine()
	var displayed_entries_after_follow_up := game_log_panel.get_step_timeline_entries()
	if int(game_log_panel.append_step_timeline_call_count) != append_count_before_append:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 已被 baseline 预取时不应重复 append：before=%d after=%d"
				% [append_count_before_append, int(game_log_panel.append_step_timeline_call_count)]
		)
	if int(game_log_panel.load_step_timeline_call_count) != load_count_before_append:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 已被 baseline 预取时不应重新走整表 load：before=%d after=%d"
				% [load_count_before_append, int(game_log_panel.load_step_timeline_call_count)]
		)
	if displayed_entries_after_follow_up.size() != entries_before_append_count:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 已被 baseline 预取时，日志条目数应保持不变：before=%d after=%d"
				% [entries_before_append_count, displayed_entries_after_follow_up.size()]
		)
	if not bool(controller._live_history_uses_global_timeline):
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"append 后 live baseline 模式不应丢失"
		)
	var runtime_timeline_after_follow_up := Dictionary(
		controller._history_step_timeline.get(
			OnlineResumeFullHistoryAdapterClass.META_LIVE_RUNTIME_TIMELINE,
			{}
		)
	).duplicate(true)
	if StepTimelineHelpersClass.read_processed_command_count(runtime_timeline_after_follow_up) != runtime_history_size + 1:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"follow-up 命令后隐藏 runtime timeline 应前进：actual=%d expected=%d"
				% [
					StepTimelineHelpersClass.read_processed_command_count(runtime_timeline_after_follow_up),
					runtime_history_size + 1
				]
		)

	var target_runtime_command_index := maxi(0, runtime_engine.command_history.size() - 2)
	var target_step_index := controller._enter_history_step_timeline_for_command(target_runtime_command_index)
	if target_step_index < -1:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"进入按需完整历史视图失败"
		)
	if str(controller._history_timeline_source) != "online_resume_full_history":
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"按需历史视图应切到完整历史源，实际=%s" % str(controller._history_timeline_source)
		)

	controller._exit_history_step_timeline()
	if str(controller._history_timeline_source) != "runtime":
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"退出完整历史后应恢复 runtime live 源，实际=%s" % str(controller._history_timeline_source)
		)
	if callbacks.display_engine != runtime_engine:
		_cleanup_nodes(controller, host)
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
			prev_engine,
			prev_is_game_active,
			prev_event_history,
			"退出完整历史后 display_engine 应恢复为 runtime_engine"
		)

	_cleanup_nodes(controller, host)
	_restore(
		prev_mode,
		prev_local_player_id,
		prev_local_role,
		prev_server_url,
		prev_connect_token,
		prev_room_state,
		prev_room_list,
		prev_player_profile,
		prev_resume_state,
		prev_engine,
		prev_is_game_active,
		prev_event_history
	)
	return Result.success({})

static func _cleanup_nodes(controller, host: Node) -> void:
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	if host != null and is_instance_valid(host):
		host.queue_free()

static func _wait_until(predicate: Callable, st: SceneTree, max_frames: int) -> bool:
	for _i in range(maxi(1, int(max_frames))):
		if predicate.is_valid() and bool(predicate.call()):
			return true
		await st.process_frame
	return predicate.is_valid() and bool(predicate.call())

static func _restore(
	prev_mode,
	prev_local_player_id: int,
	prev_local_role: String,
	prev_server_url: String,
	prev_connect_token: String,
	prev_room_state: Dictionary,
	prev_room_list: Array,
	prev_player_profile: Dictionary,
	prev_resume_state: Dictionary,
	prev_engine,
	prev_is_game_active: bool,
	prev_event_history: Array
) -> void:
	NetClient.shutdown()
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
	Globals.current_game_engine = prev_engine
	Globals.is_game_active = prev_is_game_active
	EventBus.clear_history_and_reset_sequence()
	for item_val in prev_event_history:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val)
		if not EventBus.has_method("record_event"):
			continue
		EventBus.record_event(str(item.get("type", "")), Dictionary(item.get("data", {})).duplicate(true))

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
	prev_engine,
	prev_is_game_active: bool,
	prev_event_history: Array,
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
		prev_resume_state,
		prev_engine,
		prev_is_game_active,
		prev_event_history
	)
	return Result.failure(message)
