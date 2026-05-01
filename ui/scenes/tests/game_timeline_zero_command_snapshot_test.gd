class_name GameTimelineZeroCommandSnapshotTest
extends RefCounted

const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const SAVE_RES_PATH := "res://testdata/saves/manual_cases/employees/lobbyist.json"
const UNMARKED_SAVE_USER_PATH := "user://zero_command_unmarked_snapshot_test.json"

class _FakeGameLogPanel:
	extends Control

	signal log_entry_clicked(entry_id: int)
	signal timeline_seek_requested(step_index: int)

	var load_entries_count: int = 0
	var timeline_head: int = -999
	var timeline_cursor: int = -999
	var replay_toggle_active: bool = false

	func get_entries() -> Array:
		return []

	func load_entries(_entries: Array) -> void:
		load_entries_count += 1

	func set_timeline_head_cursor(head_index: int, cursor_index: int, _update_visible_items: bool = true) -> void:
		timeline_head = int(head_index)
		timeline_cursor = int(cursor_index)

	func set_timeline_head(head_index: int, _update_visible_items: bool = true) -> void:
		timeline_head = int(head_index)

	func set_timeline_cursor(cursor_index: int, _update_visible_items: bool = true) -> void:
		timeline_cursor = int(cursor_index)

	func set_replay_toggle_availability(_available: bool, _inactive_text: String = "进入回放", _disabled_reason: String = "") -> void:
		pass

	func set_replay_toggle_active(active: bool) -> void:
		replay_toggle_active = bool(active)

	func get_replay_bar():
		return null

class _FakeActionPanel:
	extends Control

	var disabled_reason: String = "__unset__"

	func set_globally_disabled(reason: String) -> void:
		disabled_reason = str(reason)

class _Harness:
	extends RefCounted

	var controller = null
	var action_panel: _FakeActionPanel = null
	var active_engine: GameEngine = null
	var display_engine: GameEngine = null
	var show_log_count: int = 0
	var update_ui_count: int = 0
	var confirm_messages: Array[String] = []

	func get_engine() -> GameEngine:
		return active_engine

	func get_runtime_engine() -> GameEngine:
		return active_engine

	func set_active_engine(engine: GameEngine) -> void:
		active_engine = engine

	func set_display_engine(engine: GameEngine) -> void:
		display_engine = engine

	func update_ui() -> void:
		update_ui_count += 1
		if controller == null or active_engine == null:
			return
		var head_index := active_engine.command_history.size() - 1
		var cursor_index := int(active_engine.current_command_index)
		controller.sync_timeline_ui(head_index, cursor_index, active_engine.get_state())

	func show_confirm(title: String, message: String, _ok: Callable = Callable(), _cancel: Callable = Callable()) -> void:
		confirm_messages.append("%s: %s" % [str(title), str(message)])

	func show_game_log_panel_in_right_panel() -> void:
		show_log_count += 1

	func open_replay_load_dialog() -> void:
		pass

	func get_online_resync_in_progress() -> bool:
		return false

static func run() -> Result:
	var r := _case_controller_loads_zero_command_snapshot_as_playable()
	if not r.ok:
		return r
	r = _case_controller_keeps_unmarked_zero_command_archive_as_replay()
	if not r.ok:
		return r
	return await _case_game_scene_loads_lobbyist_snapshot_with_action_panel()

static func _case_controller_loads_zero_command_snapshot_as_playable() -> Result:
	var prev_replay_load_playable := false
	if Globals != null:
		prev_replay_load_playable = bool(Globals.replay_load_playable)
		Globals.replay_load_playable = false

	var host := Control.new()
	var log_panel := _FakeGameLogPanel.new()
	var action_panel := _FakeActionPanel.new()
	host.add_child(log_panel)
	host.add_child(action_panel)

	var harness := _Harness.new()
	harness.action_panel = action_panel
	harness.controller = GameTimelineControllerClass.new(
		host,
		log_panel,
		action_panel,
		Callable(harness, "get_engine"),
		Callable(harness, "get_runtime_engine"),
		Callable(harness, "set_active_engine"),
		Callable(harness, "set_display_engine"),
		Callable(harness, "update_ui"),
		Callable(harness, "show_confirm"),
		Callable(harness, "show_game_log_panel_in_right_panel"),
		Callable(harness, "open_replay_load_dialog"),
		Callable(harness, "get_online_resync_in_progress")
	)

	harness.controller.start_replay_from_file(SAVE_RES_PATH)
	var result := _assert_loaded_as_playable_snapshot(harness)

	if harness.controller != null and harness.controller.has_method("dispose"):
		harness.controller.dispose()
	host.free()
	if Globals != null:
		Globals.replay_load_playable = prev_replay_load_playable
	return result

static func _case_controller_keeps_unmarked_zero_command_archive_as_replay() -> Result:
	var archive_r: Result = ArchiveClass.load_archive_from_file(SAVE_RES_PATH)
	if not archive_r.ok:
		return Result.failure("读取测试存档失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	archive.erase("ui_load_mode")
	var save_r: Result = ArchiveClass.save_archive_to_file(archive, UNMARKED_SAVE_USER_PATH)
	if not save_r.ok:
		return Result.failure("写入未标记测试存档失败: %s" % save_r.error)

	var prev_replay_load_playable := false
	if Globals != null:
		prev_replay_load_playable = bool(Globals.replay_load_playable)
		Globals.replay_load_playable = false

	var host := Control.new()
	var log_panel := _FakeGameLogPanel.new()
	var action_panel := _FakeActionPanel.new()
	host.add_child(log_panel)
	host.add_child(action_panel)

	var harness := _Harness.new()
	harness.action_panel = action_panel
	harness.controller = GameTimelineControllerClass.new(
		host,
		log_panel,
		action_panel,
		Callable(harness, "get_engine"),
		Callable(harness, "get_runtime_engine"),
		Callable(harness, "set_active_engine"),
		Callable(harness, "set_display_engine"),
		Callable(harness, "update_ui"),
		Callable(harness, "show_confirm"),
		Callable(harness, "show_game_log_panel_in_right_panel"),
		Callable(harness, "open_replay_load_dialog"),
		Callable(harness, "get_online_resync_in_progress")
	)

	harness.controller.start_replay_from_file(UNMARKED_SAVE_USER_PATH)
	var result := _assert_unmarked_loaded_as_readonly_replay(harness)

	if harness.controller != null and harness.controller.has_method("dispose"):
		harness.controller.dispose()
	host.free()
	if Globals != null:
		Globals.replay_load_playable = prev_replay_load_playable
	var abs_path := ProjectSettings.globalize_path(UNMARKED_SAVE_USER_PATH)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	return result

static func _case_game_scene_loads_lobbyist_snapshot_with_action_panel() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 Game 场景载入测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 Game 场景载入测试）")
	if GameScene == null:
		return Result.failure("预加载 game.tscn 失败（PackedScene 为空）")

	var prev_pending := ""
	var prev_playable := false
	if Globals != null:
		prev_pending = str(Globals.pending_replay_file_path)
		prev_playable = bool(Globals.replay_load_playable)
		Globals.pending_replay_file_path = ProjectSettings.globalize_path(SAVE_RES_PATH)
		Globals.replay_load_playable = false

	var game = GameScene.instantiate()
	if game == null or not is_instance_valid(game):
		if Globals != null:
			Globals.pending_replay_file_path = prev_pending
			Globals.replay_load_playable = prev_playable
		return Result.failure("实例化 game.tscn 失败")
	host.add_child(game)

	for _i in range(10):
		await st.process_frame

	var result := await _assert_game_scene_action_panel_visible(game)
	if game != null and is_instance_valid(game):
		game.queue_free()
	for _i in range(6):
		await st.process_frame
	if Globals != null:
		Globals.pending_replay_file_path = prev_pending
		Globals.replay_load_playable = prev_playable
		Globals.reset_game_config()
	return result

static func _assert_game_scene_action_panel_visible(game: Node) -> Result:
	if game == null or not is_instance_valid(game):
		return Result.failure("Game 场景无效")
	if Globals.current_game_engine == null:
		return Result.failure("载入 lobbyist 后 Globals.current_game_engine 为空")
	if game.has_method("is_replay_mode_active") and bool(game.call("is_replay_mode_active")):
		return Result.failure("lobbyist 零命令快照不应进入只读回放模式")

	var default_stack = game.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack")
	var dock_host = game.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DockHost")
	var action_panel = game.get_node_or_null("UIRoot/MainContent/CenterSplit/RightPanel/DefaultStack/ActionPanel")
	var game_log_panel = game.get_node_or_null("UIRoot/MainContent/LeftArea/GameLogPanel")

	if not (default_stack is Control):
		return Result.failure("RightPanel/DefaultStack 缺失")
	if not (dock_host is Control):
		return Result.failure("RightPanel/DockHost 缺失")
	if not (action_panel is ActionPanel):
		return Result.failure("RightPanel/ActionPanel 缺失或类型错误")
	if not bool((default_stack as Control).visible):
		return Result.failure("载入 lobbyist 后 DefaultStack 应可见，但被隐藏；DockHost.visible=%s" % str((dock_host as Control).visible))
	if bool((dock_host as Control).visible):
		return Result.failure("载入 lobbyist 后 DockHost 不应覆盖默认动作区")
	if game_log_panel is Control and bool((game_log_panel as Control).visible) and (game_log_panel as Control).get_parent() == dock_host:
		return Result.failure("载入 lobbyist 后不应自动打开右侧日志面板")

	var panel: ActionPanel = action_panel
	if not panel.context_panel.visible:
		return Result.failure("载入 lobbyist 后 ActionPanel ContextPanel 应可见；%s" % _describe_action_panel_state(game, panel, default_stack as Control, dock_host as Control))
	if panel.custom_context_container.get_child_count() <= 0:
		return Result.failure("载入 lobbyist 后 ActionPanel 自定义上下文不应为空")
	var text := _collect_visible_text(panel.custom_context_container)
	for expected in ["选择员工", "选择效果", "放置道路", "放置公园"]:
		if not text.contains(expected):
			return Result.failure("载入 lobbyist 后 ActionPanel 缺少文本：%s，实际=%s" % [expected, text])
	return Result.success()

static func _describe_action_panel_state(game: Node, panel: ActionPanel, default_stack: Control, dock_host: Control) -> String:
	var state = Globals.current_game_engine.get_state() if Globals != null and Globals.current_game_engine is GameEngine else null
	var phase := str(state.phase) if state != null else "<null>"
	var sub_phase := str(state.sub_phase) if state != null else "<null>"
	var current_player := int(state.get_current_player_id()) if state != null else -1
	var guided := str(panel.get_guided_action_id()) if panel.has_method("get_guided_action_id") else "<missing>"
	var visible_ids := str(panel.get_visible_action_ids()) if panel.has_method("get_visible_action_ids") else "<missing>"
	var road_enabled := bool(panel.get_action_enabled("place_lobbyists_road")) if panel.has_method("get_action_enabled") else false
	var park_enabled := bool(panel.get_action_enabled("place_lobbyists_park")) if panel.has_method("get_action_enabled") else false
	var road_reason := str(panel.get_action_disabled_reason("place_lobbyists_road")) if panel.has_method("get_action_disabled_reason") else ""
	var park_reason := str(panel.get_action_disabled_reason("place_lobbyists_park")) if panel.has_method("get_action_disabled_reason") else ""
	var active_docked := ""
	if game != null and game.has_method("get_active_docked_panel"):
		var docked = game.call("get_active_docked_panel")
		active_docked = str(docked.name) if docked is Node else str(docked)
	return "phase=%s sub_phase=%s current=%d guided=%s visible=%s road_enabled=%s road_reason=%s park_enabled=%s park_reason=%s default_visible=%s dock_visible=%s active_docked=%s" % [
		phase,
		sub_phase,
		current_player,
		guided,
		visible_ids,
		str(road_enabled),
		road_reason,
		str(park_enabled),
		park_reason,
		str(default_stack.visible),
		str(dock_host.visible),
		active_docked,
	]

static func _collect_visible_text(node: Node) -> String:
	if node == null:
		return ""
	var parts: Array[String] = []
	_collect_visible_text_into(node, parts)
	return "\n".join(parts)

static func _collect_visible_text_into(node: Node, out: Array[String]) -> void:
	if node == null:
		return
	if node is CanvasItem and not bool((node as CanvasItem).visible):
		return
	if node is Label:
		out.append(str((node as Label).text))
	elif node is Button:
		out.append(str((node as Button).text))
	elif node is OptionButton:
		var opt: OptionButton = node
		for i in range(opt.item_count):
			out.append(str(opt.get_item_text(i)))
	for child in node.get_children():
		if child is Node:
			_collect_visible_text_into(child, out)

static func _assert_loaded_as_playable_snapshot(harness: _Harness) -> Result:
	if not harness.confirm_messages.is_empty():
		return Result.failure("零命令手工存档不应弹出回放加载错误: %s" % str(harness.confirm_messages))
	if harness.active_engine == null:
		return Result.failure("零命令手工存档应进入可操作模式并设置 active_engine")
	if harness.active_engine.command_history.size() != 0:
		return Result.failure("测试前提错误：lobbyist 手工存档应为零命令快照，实际命令数=%d" % harness.active_engine.command_history.size())
	if int(harness.active_engine.current_command_index) != -1:
		return Result.failure("零命令快照 current_command_index 应保持 -1，实际=%d" % int(harness.active_engine.current_command_index))
	if harness.controller.is_replay_mode_active():
		return Result.failure("零命令手工存档不应进入只读回放模式")
	if harness.show_log_count != 0:
		return Result.failure("零命令手工存档不应自动打开右侧日志面板，实际 show_log_count=%d" % harness.show_log_count)
	if str(harness.action_panel.disabled_reason) != "":
		return Result.failure("零命令手工存档进入可操作模式后 ActionPanel 不应全局禁用，实际=%s" % str(harness.action_panel.disabled_reason))
	if harness.update_ui_count != 1:
		return Result.failure("进入可操作模式应触发一次 UI 刷新，实际=%d" % harness.update_ui_count)
	return Result.success()

static func _assert_unmarked_loaded_as_readonly_replay(harness: _Harness) -> Result:
	if not harness.confirm_messages.is_empty():
		return Result.failure("未标记零命令 archive 不应加载失败: %s" % str(harness.confirm_messages))
	if harness.active_engine == null:
		return Result.failure("未标记零命令 archive 仍应加载为回放 engine")
	if harness.active_engine.command_history.size() != 0:
		return Result.failure("测试前提错误：未标记 archive 应为零命令，实际命令数=%d" % harness.active_engine.command_history.size())
	if not harness.controller.is_replay_mode_active():
		return Result.failure("未标记零命令 archive 不应仅凭空命令历史进入可操作模式")
	if harness.show_log_count != 1:
		return Result.failure("未标记零命令 archive 应按只读回放打开日志面板，实际 show_log_count=%d" % harness.show_log_count)
	if harness.update_ui_count != 1:
		return Result.failure("未标记零命令 archive 回放加载应触发一次 UI 刷新，实际=%d" % harness.update_ui_count)
	return Result.success()
