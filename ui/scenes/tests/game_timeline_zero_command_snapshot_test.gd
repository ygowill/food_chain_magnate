class_name GameTimelineZeroCommandSnapshotTest
extends RefCounted

const GameTimelineControllerClass = preload("res://ui/scenes/game/timeline/controller.gd")
const SAVE_RES_PATH := "res://testdata/saves/manual_cases/employees/lobbyist.json"

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
