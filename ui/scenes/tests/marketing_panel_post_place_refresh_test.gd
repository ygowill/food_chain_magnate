# GamePanelMarketingPanels regression test
# After a successful marketing placement, if the player can still market, keep panel open and refresh options.
extends RefCounted

const GamePanelMarketingPanelsClass = preload("res://ui/scenes/game/panel/marketing_panels.gd")
const MarketingCampaignsTestClass = preload("res://core/tests/marketing_campaigns_test.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	var r1 := _case_request_refresh_uses_authoritative_state()
	if not r1.ok:
		return r1

	var r2 := _case_visible_sync_refreshes_on_state_change()
	if not r2.ok:
		return r2

	return Result.success({})

static func _case_request_refresh_uses_authoritative_state() -> Result:
	var setup := _build_marketing_refresh_fixture()
	if not setup.ok:
		return setup
	var ctx: Dictionary = setup.value
	var engine: GameEngine = ctx.get("engine", null)
	var panels = ctx.get("panels", null)
	var panel = ctx.get("panel", null)
	var hide_spy = ctx.get("hide_spy", null)
	if engine == null or panels == null or panel == null or hide_spy == null:
		return Result.failure("测试夹具无效")

	panels.sync(engine.get_state(), true)
	var initial_board_calls: int = int(panel.set_boards_calls)
	var initial_marketer_calls: int = int(panel.set_marketers_calls)

	panels._on_marketing_requested("marketing_trainee", 11, Vector2i(0, 2), "burger", 1, 0, "")

	if hide_spy.hide_count != 0:
		return Result.failure("仍可继续营销时不应关闭面板，hide_count=%d" % hide_spy.hide_count)
	if panel.set_marketers_calls <= initial_marketer_calls:
		return Result.failure("营销成功后应基于最新状态刷新可用营销员列表")
	if panel.set_boards_calls <= initial_board_calls:
		return Result.failure("营销成功后应基于最新状态刷新可用板件列表")
	if panel.last_marketers.size() != 1:
		return Result.failure("放置第一张后应只剩 1 名营销实习生可用，实际: %s" % str(panel.last_marketers))
	if not panel.last_boards.has("billboard"):
		return Result.failure("刷新后缺少 billboard 可用板件列表")
	var boards_val = panel.last_boards.get("billboard", null)
	if not (boards_val is Array):
		return Result.failure("billboard 可用板件列表类型错误: %s" % str(boards_val))
	var boards: Array = boards_val
	if boards.has(11):
		return Result.failure("已放置的 billboard #11 不应仍出现在可用列表中: %s" % str(boards))

	return Result.success({})

static func _case_visible_sync_refreshes_on_state_change() -> Result:
	var setup := _build_marketing_refresh_fixture()
	if not setup.ok:
		return setup
	var ctx: Dictionary = setup.value
	var engine: GameEngine = ctx.get("engine", null)
	var panels = ctx.get("panels", null)
	var panel = ctx.get("panel", null)
	if engine == null or panels == null or panel == null:
		return Result.failure("测试夹具无效")

	panels.sync(engine.get_state(), true)
	var initial_board_calls: int = int(panel.set_boards_calls)
	var initial_marketer_calls: int = int(panel.set_marketers_calls)
	var exec_r := engine.execute_command(Command.create("initiate_marketing", 0, {
		"employee_type": "marketing_trainee",
		"board_number": 11,
		"product": "burger",
		"duration": 1,
		"position": [0, 2],
	}))
	if not exec_r.ok:
		return Result.failure("预期营销放置成功，但失败: %s" % exec_r.error)

	panels.sync(engine.get_state(), false)

	if panel.set_marketers_calls <= initial_marketer_calls:
		return Result.failure("普通 sync 在营销状态变化后应刷新营销员列表")
	if panel.set_boards_calls <= initial_board_calls:
		return Result.failure("普通 sync 在营销状态变化后应刷新板件列表")
	if panel.last_marketers.size() != 1:
		return Result.failure("sync 后应只剩 1 名营销实习生可用，实际: %s" % str(panel.last_marketers))
	var boards_val = panel.last_boards.get("billboard", null)
	if not (boards_val is Array):
		return Result.failure("sync 后 billboard 可用板件列表类型错误: %s" % str(boards_val))
	var boards: Array = boards_val
	if boards.has(11):
		return Result.failure("普通 sync 后不应仍保留已使用的 billboard #11: %s" % str(boards))

	return Result.success({})

static func _build_marketing_refresh_fixture() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	MarketingCampaignsTestClass._force_turn_order(state, 2)
	var map_r := MarketingCampaignsTestClass._build_test_map(0)
	if not map_r.ok:
		return map_r
	state.map = map_r.value
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[0]["restaurants"] = ["rest_0"]
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING

	var add_r1 := _take_marketer_to_active(state, 0)
	if not add_r1.ok:
		return add_r1
	var add_r2 := _take_marketer_to_active(state, 0)
	if not add_r2.ok:
		return add_r2

	var scene := _MockScene.new(engine)
	var map_controller := _MockMapController.new()
	var overlay_controller := _MockOverlayController.new()
	var hide_spy := _HideSpy.new()

	var panels := GamePanelMarketingPanelsClass.new(
		scene,
		map_controller,
		overlay_controller,
		Callable(engine, "execute_command"),
		Callable(hide_spy, "hide_all"),
		Callable()
	)

	var panel := _MockMarketingPanel.new()
	panels.marketing_panel = panel

	return Result.success({
		"engine": engine,
		"panels": panels,
		"panel": panel,
		"hide_spy": hide_spy,
	})

static func _take_marketer_to_active(state: GameState, player_id: int) -> Result:
	var pool_count := int(state.employee_pool.get("marketing_trainee", 0))
	if pool_count <= 0:
		return Result.failure("员工池中没有 marketing_trainee")
	state.employee_pool["marketing_trainee"] = pool_count - 1
	state.players[player_id]["employees"].append("marketing_trainee")
	return Result.success({})


class _MockScene:
	extends RefCounted

	var game_engine: GameEngine = null
	var game_log_panel = null

	func _init(engine: GameEngine) -> void:
		game_engine = engine

	func add_child(_node: Node) -> void:
		pass


class _MockMapController:
	extends RefCounted

	func clear_selection() -> void:
		pass

	func on_marketing_map_selection_requested(_marketing_type: String, _employee_type: String = "", _board_number: int = 0, _rotation: int = 0) -> void:
		pass

	func set_marketing_panel(_panel) -> void:
		pass


class _MockOverlayController:
	extends RefCounted

	func hide_marketing_range_overlay() -> void:
		pass


class _HideSpy:
	extends RefCounted

	var hide_count: int = 0

	func hide_all() -> void:
		hide_count += 1


class _MockMarketingPanel:
	extends RefCounted

	var visible: bool = true
	var set_marketers_calls: int = 0
	var set_boards_calls: int = 0
	var last_marketers: Array[Dictionary] = []
	var last_boards: Dictionary = {}

	func clear_selection() -> void:
		pass

	func set_available_marketers(marketers: Array[Dictionary]) -> void:
		set_marketers_calls += 1
		last_marketers = marketers.duplicate(true)

	func set_available_boards(boards_by_type: Dictionary) -> void:
		set_boards_calls += 1
		last_boards = boards_by_type.duplicate(true)

	func set_map_selection_callback(_callback: Callable) -> void:
		pass

	func set_error(_message: String) -> void:
		pass
