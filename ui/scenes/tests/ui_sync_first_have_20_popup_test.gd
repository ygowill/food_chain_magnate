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

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, engine)

	var panel := FakePanelController.new()
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
		null,
		null
	)

	ctrl.update_ui(false)
	if not panel.shown_focus_ids.is_empty():
		return _finish(Result.failure("初始同步不应弹出储备卡总览"), ctrl, engine)

	engine.get_state().players[0]["can_peek_all_reserve_cards"] = true
	ctrl.update_ui(false)
	if panel.shown_focus_ids.size() != 1 or int(panel.shown_focus_ids[0]) != 0:
		return _finish(Result.failure("peek 权限从 false->true 时应弹出玩家0 的储备卡总览，实际: %s" % str(panel.shown_focus_ids)), ctrl, engine)

	ctrl.update_ui(false)
	if panel.shown_focus_ids.size() != 1:
		return _finish(Result.failure("同一状态不应重复弹出储备卡总览，实际: %s" % str(panel.shown_focus_ids)), ctrl, engine)

	return _finish(Result.success({}), ctrl, engine)

static func _finish(result: Result, ctrl, engine) -> Result:
	if ctrl != null and ctrl.has_method("dispose"):
		ctrl.dispose()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
