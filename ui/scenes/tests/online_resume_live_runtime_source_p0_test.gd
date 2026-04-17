class_name OnlineResumeLiveRuntimeSourceP0Test
extends RefCounted

const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")
const OnlineResumeClientDualEngineBootstrapTestClass = preload("res://core/tests/online_resume_client_dual_engine_bootstrap_test.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

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

	func has_step_timeline_loaded() -> bool:
		return not _timeline.is_empty() and _timeline.get("steps", null) is Array

	func load_step_timeline(timeline: Dictionary, entries: Array[Dictionary], _reset_extra_entries: bool = false) -> void:
		_timeline = Dictionary(timeline).duplicate(true)
		_entries.clear()
		for entry_val in entries:
			if entry_val is Dictionary:
				_entries.append(Dictionary(entry_val).duplicate(true))

	func append_step_timeline(timeline: Dictionary, appended_entries: Array[Dictionary], _reset_extra_entries: bool = false) -> bool:
		if not has_step_timeline_loaded():
			return false
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

	var build_r := OnlineResumeClientDualEngineBootstrapTestClass._build_resume_fast_start_bundle()
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

	var snapshot_before_ready := NetClient.get_online_resume_session_snapshot()
	if bool(snapshot_before_ready.get("full_replay_ready", false)):
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
			"完整历史在 deferred bootstrap 前不应已就绪"
		)

	var host := Control.new()
	tree.root.add_child(host)
	var game_log_panel := _FakeGameLogPanel.new()
	host.add_child(game_log_panel)
	var action_panel := Control.new()
	host.add_child(action_panel)

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
			"完整历史未 ready 前不应提前进入 global baseline live 模式"
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
			"完整历史未 ready 前仍应先显示 runtime live 日志"
		)

	var ensure_history_r := NetClient.ensure_online_resume_full_history_timeline_current(false)
	if not ensure_history_r.ok:
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
			"构建完整历史失败: %s" % ensure_history_r.error
		)
	var snapshot := NetClient.get_online_resume_session_snapshot()
	if not bool(snapshot.get("full_replay_ready", false)):
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
			"完整历史应已就绪"
		)
	var cached_history_entries := NetClient.get_online_resume_full_replay_step_timeline_entries()
	if cached_history_entries.is_empty():
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
			"完整历史 entries cache 应已就绪"
		)

	controller.on_online_resume_full_history_ready()
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
			"恢复房默认 live 日志应复用 full-history baseline"
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
			"恢复房默认日志应显示完整历史前缀：displayed=%d cached=%d"
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
			"完整历史回填后日志条目数不应少于 runtime live：runtime=%d merged=%d"
				% [runtime_only_entries.size(), displayed_entries.size()]
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
