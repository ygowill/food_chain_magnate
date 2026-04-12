# restructure_employee apply 状态访问回归测试
class_name RestructureEmployeeStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/restructure_employee_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_missing_to_reserve_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_to_reserve_type_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_ceo_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_validate_allows_active_employee_when_same_id_is_busy(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _build_restructuring_state(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.round_number = 2
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["restructuring"] = {
		"submitted": {0: false, 1: false},
		"finalized": false,
	}
	state.players[0]["employees"] = ["trainer"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 1,
		"structure": [
			{"employee_id": "trainer", "reports": []},
		],
	}
	return Result.success(state)

static func _test_apply_changes_fails_fast_on_missing_to_reserve_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("restructure_employee", 0, {
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("缺少 to_reserve 时应失败")
	var err := str(result.error)
	if err.find("to_reserve") < 0:
		return Result.failure("错误信息应包含 to_reserve，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_to_reserve_type_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("restructure_employee", 0, {
		"employee_id": "trainer",
		"to_reserve": "bad",
	}))
	if result.ok:
		return Result.failure("to_reserve 类型错误时应失败")
	var err := str(result.error)
	if err.find("to_reserve") < 0:
		return Result.failure("错误信息应包含 to_reserve，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_apply_changes_fails_fast_on_ceo_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("restructure_employee", 0, {
		"employee_id": "ceo",
		"to_reserve": true,
	}))
	if result.ok:
		return Result.failure("移动 CEO 时应失败")
	var err := str(result.error)
	if err.find("CEO") < 0:
		return Result.failure("错误信息应包含 CEO，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = {}
	var player_before := str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("restructure_employee", 0, {
		"employee_id": "trainer",
		"to_reserve": true,
	}))
	if result.ok:
		return Result.failure("player.employees 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_validate_allows_active_employee_when_same_id_is_busy(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = ["marketing_trainee"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = ["marketing_trainee"]
	state.players[0]["company_structure"] = {
		"ceo_slots": 1,
		"structure": [
			{"employee_id": "marketing_trainee", "reports": []},
		],
	}
	var action = ActionClass.new()
	var result := action._validate_specific(state, Command.create("restructure_employee", 0, {
		"employee_id": "marketing_trainee",
		"to_reserve": true,
	}))
	if not result.ok:
		return Result.failure("active 中存在可用副本时不应被 busy 同名副本拦截，实际: %s" % result.error)
	return Result.success()
