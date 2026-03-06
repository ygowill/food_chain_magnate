# choose_kimchi_storage 状态访问回归测试
class_name ChooseKimchiStorageStateAccessTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	return _test_missing_inventory_fails_fast(player_count, seed_val)

static func _test_missing_inventory_fails_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	])
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["cleanup"] = {"pending_choice_kind": "kimchi"}
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_CLEANUP: [0],
	}
	state.players[0].erase("inventory")
	var r := engine.execute_command(Command.create("choose_kimchi_storage", 0, {"store": true}))
	if r.ok:
		return Result.failure("缺失 inventory 时应失败")
	var err := str(r.error)
	if err.find("player[0].inventory") < 0:
		return Result.failure("错误信息应包含 inventory 路径，实际: %s" % err)
	return Result.success()
