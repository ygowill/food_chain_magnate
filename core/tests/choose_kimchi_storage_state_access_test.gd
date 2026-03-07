# choose_kimchi_storage 状态访问回归测试
class_name ChooseKimchiStorageStateAccessTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionClass = preload("res://gameplay/actions/choose_kimchi_storage_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_missing_inventory_fails_fast(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

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

static func _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation(player_count: int, seed_val: int) -> Result:
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
		return Result.failure("初始化失败(case2): %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["cleanup"] = {"pending_choice_kind": "kimchi"}
	state.round_state["pending_phase_actions"] = []
	state.players[0]["inventory"] = {"kimchi": 12, "burger": 3}
	var inventory_before: String = str(state.players[0]["inventory"])
	var action = ActionClass.new()
	var r := action._apply_changes(state, Command.create("choose_kimchi_storage", 0, {"store": true}))
	if r.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(r.error)
	if err.find("pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions，实际: %s" % err)
	if str(state.players[0]["inventory"]) != inventory_before:
		return Result.failure("失败时不应提前改写 inventory")
	var cleanup_val = state.round_state.get("cleanup", null)
	if cleanup_val is Dictionary and (cleanup_val as Dictionary).has("inventory_discarded"):
		return Result.failure("失败时不应提前写入 cleanup.inventory_discarded")
	return Result.success()
