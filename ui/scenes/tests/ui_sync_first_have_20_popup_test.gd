class_name UiSyncFirstHave20PopupTest
extends RefCounted

const GameUiSyncControllerClass = preload("res://ui/scenes/game/controllers/ui_sync_controller.gd")

class FakePanelController:
	extends RefCounted

	var shown_focus_ids: Array[int] = []
	var reserve_view: Control = null

	func _init() -> void:
		reserve_view = Control.new()
		reserve_view.visible = false

	func show_reserve_cards_overview(focus_player_id: int = -1) -> void:
		shown_focus_ids.append(focus_player_id)
		reserve_view.visible = true

	func get_reserve_cards_full_screen_view():
		return reserve_view

	func dispose() -> void:
		if reserve_view != null and is_instance_valid(reserve_view):
			reserve_view.free()
		reserve_view = null
		shown_focus_ids.clear()

class FakeTimelineController:
	extends RefCounted

	func get_ui_head_cursor(_engine: GameEngine) -> Vector2i:
		return Vector2i(-1, -1)

	func sync_timeline_ui(_head_index: int, _cursor_index: int, _state: GameState) -> void:
		return

	func is_history_step_timeline_active() -> bool:
		return true

	func is_replay_mode_active() -> bool:
		return false

	func is_timeline_read_only_active(_engine: GameEngine) -> bool:
		return false

	func consume_force_full_panel_sync_next_update() -> bool:
		return false

class FakeOverlayController:
	extends RefCounted

	func sync_demand_indicator(_state: GameState) -> void:
		return

	func sync_dinnertime_overlay(_state: GameState, _is_live: bool = true) -> void:
		return

static func run(seed_val: int = 12345) -> Result:
	var prev_mode = NetContext.mode if NetContext != null else 0
	var prev_local_player_id := int(NetContext.local_player_id) if NetContext != null else -1
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, engine, prev_mode, prev_local_player_id)
	if NetContext != null:
		NetContext.mode = NetContext.Mode.HOTSEAT
		NetContext.local_player_id = -1

	var panel := FakePanelController.new()
	var timeline := FakeTimelineController.new()
	var overlay := FakeOverlayController.new()
	var ctrl := GameUiSyncControllerClass.new(
		func() -> GameEngine: return engine,
		Callable(),
		Callable(),
		null,
		null,
		null,
		null,
		null,
		null,
		panel,
		overlay,
		timeline
	)

	ctrl.update_ui(false)
	if not panel.shown_focus_ids.is_empty():
		return _finish(Result.failure("初始同步不应弹出储备卡总览"), ctrl, engine, prev_mode, prev_local_player_id)

	engine.get_state().players[0]["can_peek_all_reserve_cards"] = true
	engine.get_state().phase = "Dinnertime"
	ctrl.update_ui(false)
	if not panel.shown_focus_ids.is_empty():
		return _finish(Result.failure("晚餐阶段中不应立刻弹出储备卡总览，实际: %s" % str(panel.shown_focus_ids)), ctrl, engine, prev_mode, prev_local_player_id)

	engine.get_state().phase = "Payday"
	panel.reserve_view.visible = false
	ctrl.update_ui(false)
	if panel.shown_focus_ids.size() != 1 or int(panel.shown_focus_ids[0]) != 0:
		return _finish(Result.failure("peek 权限从 false->true 时应弹出玩家0 的储备卡总览，实际: %s" % str(panel.shown_focus_ids)), ctrl, engine, prev_mode, prev_local_player_id)

	ctrl.update_ui(false)
	if panel.shown_focus_ids.size() != 1:
		return _finish(Result.failure("同一状态不应重复弹出储备卡总览，实际: %s" % str(panel.shown_focus_ids)), ctrl, engine, prev_mode, prev_local_player_id)

	return _finish(Result.success({}), ctrl, engine, prev_mode, prev_local_player_id)

static func _finish(result: Result, ctrl, engine, prev_mode, prev_local_player_id: int) -> Result:
	if ctrl != null and ctrl.has_method("get"):
		var panel = ctrl.get("_panel_controller")
		if panel != null and panel.has_method("dispose"):
			panel.dispose()
	if ctrl != null and ctrl.has_method("dispose"):
		ctrl.dispose()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	if NetContext != null:
		NetContext.mode = prev_mode
		NetContext.local_player_id = prev_local_player_id
	return result
