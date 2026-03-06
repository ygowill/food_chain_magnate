# choose_fridge_keep 状态访问回归测试
class_name ChooseFridgeKeepStateAccessTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_missing_inventory_fails_fast(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_missing_milestones_fails_fast(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _test_missing_inventory_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [{"kind": "fridge_keep", "player_id": 0}],
	}
	state.players[0].erase("inventory")
	var r := engine.execute_command(Command.create("choose_fridge_keep", 0, {"keep": {}}))
	if r.ok:
		return Result.failure("缺失 inventory 时应失败")
	var err := str(r.error)
	if err.find("player[0].inventory") < 0:
		return Result.failure("错误信息应包含 inventory 路径，实际: %s" % err)
	return Result.success()

static func _test_missing_milestones_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败(case2): %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [{"kind": "fridge_keep", "player_id": 0}],
	}
	state.players[0]["inventory"] = {"burger": 12, "beer": 5}
	state.players[0].erase("milestones")
	var r := engine.execute_command(Command.create("choose_fridge_keep", 0, {"keep": {"burger": 5}}))
	if r.ok:
		return Result.failure("缺失 milestones 时应失败")
	var err := str(r.error)
	if err.find("player[0].milestones") < 0:
		return Result.failure("错误信息应包含 milestones 路径，实际: %s" % err)
	return Result.success()
