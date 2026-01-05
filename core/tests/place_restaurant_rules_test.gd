# 放置餐厅规则测试（P1）
# 验证：Working/PlaceRestaurants 需要在岗的本地/大区经理；每张卡每子阶段仅可使用一次；
# 使用后本回合启用 drive_thru_active，并在 Cleanup 重置。
class_name PlaceRestaurantRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 为避免测试推进到 Payday 时因薪水不足中断，给每位玩家少量现金（保持现金守恒）。
	var s := engine.get_state()
	for pid in range(player_count):
		var grant := StateUpdaterClass.player_receive_from_bank(s, pid, 20)
		if not grant.ok:
			return Result.failure("发放测试现金失败: %s" % grant.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	# 推进到 PlaceRestaurants 子阶段（Recruit -> Train -> Marketing -> GetFood -> GetDrinks -> PlaceHouses -> PlaceRestaurants）
	for i in range(6):
		var pass_all := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
		if not pass_all.ok:
			return pass_all
		var sub := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
		if not sub.ok:
			return Result.failure("推进到 PlaceRestaurants 子阶段失败(step=%d): %s" % [i, sub.error])

	var state := engine.get_state()
	if state.phase != "Working" or state.sub_phase != "PlaceRestaurants":
		return Result.failure("应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	# 1) 没有本地/大区经理：应拒绝放置
	var cmd_fail := Command.create("place_restaurant", actor, {"position": [0, 0], "rotation": 0})
	var exec_fail := engine.execute_command(cmd_fail)
	if exec_fail.ok:
		return Result.failure("没有本地/大区经理时不应允许放置餐厅")
	if str(exec_fail.error).find("本地经理") < 0 and str(exec_fail.error).find("区域经理") < 0 and str(exec_fail.error).find("大区经理") < 0:
		return Result.failure("拒绝原因应包含'本地经理/区域经理'，实际: %s" % exec_fail.error)

	# 2) 给玩家添加 1 名在岗本地经理（从池取卡，保持守恒）
	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add.ok:
		return Result.failure("添加 local_manager 失败: %s" % add.error)

	# 找一个合法的餐厅放置点
	var cmd_ok := _find_first_valid_restaurant_placement(engine, actor)
	if cmd_ok == null:
		return Result.failure("找不到合法的餐厅放置点（可能是地图数据异常）")

	var exec_ok := engine.execute_command(cmd_ok)
	if not exec_ok.ok:
		return Result.failure("有本地经理时放置餐厅应成功，但失败: %s (%s)" % [exec_ok.error, str(cmd_ok)])

	# 使用经理后：本回合启用免下车
	var player_after := engine.get_state().players[actor]
	if not bool(player_after.get("drive_thru_active", false)):
		return Result.failure("使用本地经理放置餐厅后 drive_thru_active 应为 true")

	# 3) 同一子阶段再次放置：应因“每张卡一次”被拒绝
	var exec_again := engine.execute_command(Command.create("place_restaurant", actor, {"position": [0, 0], "rotation": 0}))
	if exec_again.ok:
		return Result.failure("同一子阶段不应允许再次放置餐厅（经理次数应耗尽）")
	if str(exec_again.error).find("已用完") < 0:
		return Result.failure("第二次放置应提示次数已用完，实际: %s" % exec_again.error)

	# 4) 推进到 Cleanup：drive_thru_active 应被重置为 false
	var to_cleanup := TestPhaseUtilsClass.advance_until_phase(engine, "Cleanup", 20)
	if not to_cleanup.ok:
		return to_cleanup
	if bool(engine.get_state().players[actor].get("drive_thru_active", true)):
		return Result.failure("进入 Cleanup 后 drive_thru_active 应被重置为 false")

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
	})

static func _find_first_valid_restaurant_placement(engine: GameEngine, actor: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var cmd := Command.create("place_restaurant", actor, {"position": [x, y], "rotation": r})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null
