# 放置房屋规则测试（P1）
# 验证：放置房屋需要在岗的“可放置房屋员工”（数据驱动：usage_tags）；每名员工每子阶段仅可使用一次。
class_name PlaceHouseRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	# 推进到 PlaceHouses 子阶段（Recruit -> Train -> Marketing -> GetFood -> GetDrinks -> PlaceHouses）
	for i in range(5):
		var pass_all := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
		if not pass_all.ok:
			return pass_all
		var sub := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
		if not sub.ok:
			return Result.failure("推进到 PlaceHouses 子阶段失败(step=%d): %s" % [i, sub.error])

	var state := engine.get_state()
	if state.phase != "Working" or state.sub_phase != "PlaceHouses":
		return Result.failure("应处于 Working/PlaceHouses，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	# 1) 没有可放置房屋员工：应拒绝放置
	var cmd_fail := Command.create("place_house", actor, {"position": [0, 0], "rotation": 0})
	var exec_fail := engine.execute_command(cmd_fail)
	if exec_fail.ok:
		return Result.failure("没有可放置房屋员工时不应允许放置房屋")
	if str(exec_fail.error).find("可放置房屋") < 0:
		return Result.failure("拒绝原因应包含'可放置房屋'，实际: %s" % exec_fail.error)

	# 2) 给玩家添加 1 名在岗员工（从池取卡，保持守恒）
	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "new_business_dev", 1)
	if not take.ok:
		return Result.failure("从员工池取出 new_business_dev 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "new_business_dev", false)
	if not add.ok:
		return Result.failure("添加 new_business_dev 失败: %s" % add.error)

	# 找一个合法的放置点
	var cmd_ok := _find_first_valid_house_placement(engine, actor)
	if cmd_ok == null:
		return Result.failure("找不到合法的房屋放置点（可能是地图数据异常）")

	var exec_ok := engine.execute_command(cmd_ok)
	if not exec_ok.ok:
		return Result.failure("有新业务开发员时放置房屋应成功，但失败: %s (%s)" % [exec_ok.error, str(cmd_ok)])

	# 3) 同一子阶段再次放置：应因“每张卡一次”被拒绝
	var exec_again := engine.execute_command(cmd_ok)
	if exec_again.ok:
		return Result.failure("同一子阶段不应允许再次放置房屋（新业务开发员次数应耗尽）")

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
	})

static func _find_first_valid_house_placement(engine: GameEngine, actor: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_house")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var cmd := Command.create("place_house", actor, {"position": [x, y], "rotation": r})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null
