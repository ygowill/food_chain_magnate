class_name UiSyncDirtyFallbackTest
extends RefCounted

const GameUiSyncControllerClass = preload("res://ui/scenes/game/controllers/ui_sync_controller.gd")

class FakeMapView:
	extends Control

	var set_game_state_calls: int = 0

	func set_game_state(_state: GameState) -> void:
		set_game_state_calls += 1

class FakePanelController:
	extends RefCounted

	var sync_calls: int = 0
	var action_state_calls: int = 0
	var action_flow_calls: int = 0

	func sync(_state: GameState, _force_refresh: bool = false) -> void:
		sync_calls += 1

	func sync_action_state(_state: GameState, _force_refresh: bool = false) -> void:
		action_state_calls += 1

	func sync_action_flow_controls() -> void:
		action_flow_calls += 1

	func get_reserve_cards_full_screen_view():
		return null

class FakeOverlayController:
	extends RefCounted

	var demand_calls: int = 0
	var dinnertime_calls: int = 0
	var marketing_calls: int = 0

	func sync_demand_indicator(_state: GameState) -> void:
		demand_calls += 1

	func sync_dinnertime_overlay(_state: GameState, _is_live: bool = true) -> void:
		dinnertime_calls += 1

	func sync_marketing_overlay(_state: GameState, _is_live: bool = true) -> void:
		marketing_calls += 1

class FakeTimelineController:
	extends RefCounted

	var sync_calls: int = 0

	func get_ui_head_cursor(engine: GameEngine) -> Vector2i:
		return Vector2i(int(engine.command_history.size()) - 1, int(engine.current_command_index))

	func sync_timeline_ui(_head_index: int, _cursor_index: int, _state: GameState) -> void:
		sync_calls += 1

	func consume_force_full_panel_sync_next_update() -> bool:
		return false

	func is_timeline_read_only_active(_engine: GameEngine) -> bool:
		return false

	func is_replay_mode_active() -> bool:
		return false

	func is_history_step_timeline_active() -> bool:
		return false

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, engine, null)

	var map_view := FakeMapView.new()
	var panel := FakePanelController.new()
	var overlay := FakeOverlayController.new()
	var timeline := FakeTimelineController.new()
	var ctrl := GameUiSyncControllerClass.new(
		func() -> GameEngine: return engine,
		Callable(),
		Callable(),
		null,
		null,
		null,
		null,
		null,
		map_view,
		panel,
		overlay,
		timeline
	)

	ctrl.sync_dirty(
		GameUiSyncControllerClass.DIRTY_TOP_STATUS | GameUiSyncControllerClass.DIRTY_TIMELINE_CURSOR,
		{"source": "test_partial_supported"},
		false
	)
	var supported_partial_r := _assert_supported_partial_counts(map_view, panel, overlay, timeline)
	if not supported_partial_r.ok:
		return _finish(supported_partial_r, ctrl, engine, map_view)

	ctrl.sync_dirty(
		GameUiSyncControllerClass.DIRTY_MAP_VIEW
			| GameUiSyncControllerClass.DIRTY_OVERLAYS
			| GameUiSyncControllerClass.DIRTY_ACTION_CONTROLS,
		{"source": "test_surface_partial"},
		false
	)
	var surface_partial_r := _assert_surface_partial_counts(map_view, panel, overlay, timeline)
	if not surface_partial_r.ok:
		return _finish(surface_partial_r, ctrl, engine, map_view)

	ctrl.sync_dirty(GameUiSyncControllerClass.DIRTY_LOG_APPEND, {"source": "test_log_append_noop"}, false)
	var log_append_r := _assert_surface_partial_counts(map_view, panel, overlay, timeline)
	if not log_append_r.ok:
		return _finish(log_append_r, ctrl, engine, map_view)

	ctrl.sync_dirty(GameUiSyncControllerClass.DIRTY_PANEL_STATE, {"source": "test_panel_partial"}, false)
	var panel_partial_r := _assert_panel_partial_counts(map_view, panel, overlay, timeline)
	if not panel_partial_r.ok:
		return _finish(panel_partial_r, ctrl, engine, map_view)

	ctrl.sync_dirty(GameUiSyncControllerClass.DIRTY_FULL, {"source": "test_full"}, false)
	var full_r := _assert_full_sync_counts(map_view, panel, overlay, timeline, 2, 1, 1, 2, 2, "DIRTY_FULL")
	if not full_r.ok:
		return _finish(full_r, ctrl, engine, map_view)

	ctrl.sync_dirty(1 << 29, {"source": "test_unknown"}, false)
	var unknown_r := _assert_full_sync_counts(map_view, panel, overlay, timeline, 3, 2, 1, 3, 3, "unknown dirty fallback")
	if not unknown_r.ok:
		return _finish(unknown_r, ctrl, engine, map_view)

	return _finish(Result.success({}), ctrl, engine, map_view)

static func _assert_supported_partial_counts(
	map_view: FakeMapView,
	panel: FakePanelController,
	overlay: FakeOverlayController,
	timeline: FakeTimelineController
) -> Result:
	if timeline.sync_calls != 1:
		return Result.failure("supported partial dirty 应同步 timeline，实际=%d" % timeline.sync_calls)
	if map_view.set_game_state_calls != 0:
		return Result.failure("supported partial dirty 不应同步 map_view，实际=%d" % map_view.set_game_state_calls)
	if panel.sync_calls != 0 or panel.action_flow_calls != 0:
		return Result.failure(
			"supported partial dirty 不应同步 panel_controller，实际 sync=%d action_flow=%d"
				% [panel.sync_calls, panel.action_flow_calls]
		)
	if overlay.demand_calls != 0 or overlay.dinnertime_calls != 0 or overlay.marketing_calls != 0:
		return Result.failure(
			"supported partial dirty 不应同步 overlays，实际 demand=%d dinner=%d marketing=%d"
				% [overlay.demand_calls, overlay.dinnertime_calls, overlay.marketing_calls]
		)
	return Result.success({})

static func _assert_surface_partial_counts(
	map_view: FakeMapView,
	panel: FakePanelController,
	overlay: FakeOverlayController,
	timeline: FakeTimelineController
) -> Result:
	if timeline.sync_calls != 1:
		return Result.failure("surface partial dirty 不应同步 timeline，实际=%d" % timeline.sync_calls)
	if map_view.set_game_state_calls != 1:
		return Result.failure("surface partial dirty 应同步 map_view，实际=%d" % map_view.set_game_state_calls)
	if panel.sync_calls != 0:
		return Result.failure("surface partial dirty 不应 full sync panel_controller，实际=%d" % panel.sync_calls)
	if panel.action_state_calls != 0:
		return Result.failure("surface partial dirty 不应同步 panel action state，实际=%d" % panel.action_state_calls)
	if panel.action_flow_calls != 1:
		return Result.failure("surface partial dirty 应同步 action flow controls，实际=%d" % panel.action_flow_calls)
	if overlay.demand_calls != 1 or overlay.dinnertime_calls != 1 or overlay.marketing_calls != 1:
		return Result.failure(
			"surface partial dirty 应同步 overlays，实际 demand=%d dinner=%d marketing=%d"
				% [overlay.demand_calls, overlay.dinnertime_calls, overlay.marketing_calls]
		)
	return Result.success({})

static func _assert_panel_partial_counts(
	map_view: FakeMapView,
	panel: FakePanelController,
	overlay: FakeOverlayController,
	timeline: FakeTimelineController
) -> Result:
	if timeline.sync_calls != 1:
		return Result.failure("panel partial dirty 不应同步 timeline，实际=%d" % timeline.sync_calls)
	if map_view.set_game_state_calls != 1:
		return Result.failure("panel partial dirty 不应同步 map_view，实际=%d" % map_view.set_game_state_calls)
	if panel.sync_calls != 0:
		return Result.failure("panel partial dirty 不应 full sync panel_controller，实际=%d" % panel.sync_calls)
	if panel.action_state_calls != 1:
		return Result.failure("panel partial dirty 应同步 panel action state，实际=%d" % panel.action_state_calls)
	if panel.action_flow_calls != 1:
		return Result.failure("panel partial dirty 不应额外同步 action flow controls，实际=%d" % panel.action_flow_calls)
	if overlay.demand_calls != 1 or overlay.dinnertime_calls != 1 or overlay.marketing_calls != 1:
		return Result.failure(
			"panel partial dirty 不应同步 overlays，实际 demand=%d dinner=%d marketing=%d"
				% [overlay.demand_calls, overlay.dinnertime_calls, overlay.marketing_calls]
		)
	return Result.success({})

static func _assert_full_sync_counts(
	map_view: FakeMapView,
	panel: FakePanelController,
	overlay: FakeOverlayController,
	timeline: FakeTimelineController,
	expected: int,
	expected_panel: int,
	expected_action_state: int,
	expected_timeline: int,
	expected_action_flow: int,
	label: String
) -> Result:
	if timeline.sync_calls != expected_timeline:
		return Result.failure("%s 应同步 timeline，实际=%d 期望=%d" % [label, timeline.sync_calls, expected_timeline])
	if map_view.set_game_state_calls != expected:
		return Result.failure("%s 应同步 map_view，实际=%d 期望=%d" % [label, map_view.set_game_state_calls, expected])
	if panel.sync_calls != expected_panel:
		return Result.failure("%s 应同步 panel_controller，实际=%d 期望=%d" % [label, panel.sync_calls, expected_panel])
	if panel.action_state_calls != expected_action_state:
		return Result.failure("%s panel action state 计数错误，实际=%d 期望=%d" % [label, panel.action_state_calls, expected_action_state])
	if panel.action_flow_calls != expected_action_flow:
		return Result.failure("%s 应同步 action flow controls，实际=%d 期望=%d" % [label, panel.action_flow_calls, expected_action_flow])
	if overlay.demand_calls != expected or overlay.dinnertime_calls != expected or overlay.marketing_calls != expected:
		return Result.failure(
			"%s 应同步 overlays，实际 demand=%d dinner=%d marketing=%d 期望=%d"
				% [label, overlay.demand_calls, overlay.dinnertime_calls, overlay.marketing_calls, expected]
		)
	return Result.success({})

static func _finish(result: Result, ctrl, engine, map_view: Node) -> Result:
	if ctrl != null and ctrl.has_method("dispose"):
		ctrl.dispose()
	if map_view != null and is_instance_valid(map_view):
		map_view.free()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
