class_name MilestoneControllerVisibleSyncTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/game/panel/working/milestone_controller.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	var controller = ControllerClass.new(null, Callable(), Callable())
	var panel := _MockMilestonePanel.new()
	controller.milestone_panel = panel

	controller.sync(state, true)
	var initial_pool_calls := panel.set_pool_calls
	var initial_players_calls := panel.set_players_calls

	state.milestone_pool.append("test_dynamic_pool_refresh")
	var p0: Dictionary = state.players[0]
	var milestones := Array(p0.get("milestones", []))
	milestones.append("test_dynamic_player_refresh")
	p0["milestones"] = milestones
	state.players[0] = p0

	controller.sync(state, false)

	if panel.set_pool_calls <= initial_pool_calls:
		engine.dispose()
		return Result.failure("普通 sync 下，可见里程碑面板应刷新 milestone_pool")
	if panel.set_players_calls <= initial_players_calls:
		engine.dispose()
		return Result.failure("普通 sync 下，可见里程碑面板应刷新 players")
	if not panel.last_pool.has("test_dynamic_pool_refresh"):
		engine.dispose()
		return Result.failure("普通 sync 后未拿到最新 milestone_pool: %s" % str(panel.last_pool))
	if panel.last_players.is_empty():
		engine.dispose()
		return Result.failure("普通 sync 后未拿到 players 快照")
	var last_player0_val = panel.last_players[0]
	if not (last_player0_val is Dictionary):
		engine.dispose()
		return Result.failure("players[0] 类型错误: %s" % str(last_player0_val))
	var last_player0: Dictionary = last_player0_val
	var last_milestones := Array(last_player0.get("milestones", []))
	if not last_milestones.has("test_dynamic_player_refresh"):
		engine.dispose()
		return Result.failure("普通 sync 后未反映玩家新增里程碑: %s" % str(last_milestones))

	engine.dispose()
	return Result.success({})


class _MockMilestonePanel:
	extends RefCounted

	var visible: bool = true
	var set_pool_calls: int = 0
	var set_players_calls: int = 0
	var set_global_view_calls: int = 0
	var set_rules_calls: int = 0

	var last_pool: Array[String] = []
	var last_players: Array = []

	func set_milestone_pool(pool: Array) -> void:
		set_pool_calls += 1
		last_pool.clear()
		for v in pool:
			last_pool.append(str(v))

	func set_players(players: Array) -> void:
		set_players_calls += 1
		last_players = Array(players, TYPE_DICTIONARY, "", null) if players != null else []

	func set_global_view(global_view: bool) -> void:
		set_global_view_calls += 1
		if global_view:
			pass

	func set_rules(_rules: Dictionary) -> void:
		set_rules_calls += 1
