# GamePanelMarketingPanels regression test
# After a successful marketing placement, if the player can still market, keep panel open and refresh options.
extends RefCounted

const GamePanelMarketingPanelsClass = preload("res://ui/scenes/game/panel/marketing_panels.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.players[0]["employees"].append("marketing_trainee")
	state.players[0]["employees"].append("marketing_trainee")

	var scene := _MockScene.new(engine)
	var map_controller := _MockMapController.new()
	var overlay_controller := _MockOverlayController.new()
	var hide_spy := _HideSpy.new()
	var execute_spy := _ExecuteSuccessSpy.new()

	var panels := GamePanelMarketingPanelsClass.new(
		scene,
		map_controller,
		overlay_controller,
		Callable(execute_spy, "execute"),
		Callable(hide_spy, "hide_all"),
		Callable()
	)

	var panel := _MockMarketingPanel.new()
	panels.marketing_panel = panel

	panels._on_marketing_requested("marketing_trainee", 11, Vector2i(0, 2), "burger", 1, 0, "")

	if hide_spy.hide_count != 0:
		return Result.failure("仍可继续营销时不应关闭面板，hide_count=%d" % hide_spy.hide_count)
	if panel.set_marketers_calls <= 0:
		return Result.failure("营销成功后应刷新可用营销员列表")
	if panel.set_boards_calls <= 0:
		return Result.failure("营销成功后应刷新可用板件列表")
	if panel.last_marketers.is_empty():
		return Result.failure("放置第一张后仍应存在可用营销员（第二名同名营销员）")

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


class _ExecuteSuccessSpy:
	extends RefCounted

	func execute(_command: Command) -> Result:
		return Result.success({})


class _MockMarketingPanel:
	extends RefCounted

	var visible: bool = true
	var set_marketers_calls: int = 0
	var set_boards_calls: int = 0
	var last_marketers: Array[Dictionary] = []

	func clear_selection() -> void:
		pass

	func set_available_marketers(marketers: Array[Dictionary]) -> void:
		set_marketers_calls += 1
		last_marketers = marketers.duplicate(true)

	func set_available_boards(_boards_by_type: Dictionary) -> void:
		set_boards_calls += 1

	func set_map_selection_callback(_callback: Callable) -> void:
		pass

	func set_error(_message: String) -> void:
		pass
