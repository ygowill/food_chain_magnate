# company structure apply 状态访问回归测试
class_name CompanyStructureStateAccessTest
extends RefCounted

const DirectActionClass = preload("res://gameplay/actions/set_company_structure_direct_action.gd")
const ReportActionClass = preload("res://gameplay/actions/set_company_structure_report_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_direct_apply_fails_fast_on_invalid_slot_param_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_direct_apply_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_direct_apply_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_direct_apply_fails_fast_on_fractional_ceo_slots_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_report_apply_fails_fast_on_invalid_slot_param_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_report_apply_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_report_apply_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_report_apply_fails_fast_on_fractional_ceo_slots_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 8})

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
	state.players[0]["employees"] = []
	state.players[0]["reserve_employees"] = ["trainer"]
	state.players[0]["busy_marketers"] = []
	state.players[0]["company_structure"] = {
		"ceo_slots": 1,
		"structure": [],
	}
	return Result.success(state)

static func _build_report_restructuring_state(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = ["local_manager"]
	state.players[0]["reserve_employees"] = ["trainer"]
	state.players[0]["company_structure"] = {
		"ceo_slots": 1,
		"structure": [
			{"employee_id": "local_manager", "reports": []},
		],
	}
	return Result.success(state)

static func _test_direct_apply_fails_fast_on_invalid_slot_param_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var action = DirectActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_direct", 0, {
		"slot_index": "bad",
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("slot_index 类型错误时应失败")
	var err := str(result.error)
	if err.find("slot_index") < 0:
		return Result.failure("错误信息应包含 slot_index，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_direct_apply_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = {}
	var player_before := str(state.players[0])
	var action = DirectActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_direct", 0, {
		"slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("player.employees 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_direct_apply_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["company_structure"] = []
	var player_before := str(state.players[0])
	var action = DirectActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_direct", 0, {
		"slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("player.company_structure 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].company_structure") < 0:
		return Result.failure("错误信息应包含 player[0].company_structure，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_direct_apply_fails_fast_on_fractional_ceo_slots_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["company_structure"] = {
		"ceo_slots": 1.5,
		"structure": [],
	}
	var player_before := str(state.players[0])
	var action = DirectActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_direct", 0, {
		"slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("fractional ceo_slots 时应失败")
	var err := str(result.error)
	if err.find("player.company_structure.ceo_slots") < 0:
		return Result.failure("错误信息应包含 player.company_structure.ceo_slots，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_report_apply_fails_fast_on_invalid_slot_param_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_report_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	var player_before := str(state.players[0])
	var action = ReportActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_report", 0, {
		"manager_slot_index": "bad",
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("manager_slot_index 类型错误时应失败")
	var err := str(result.error)
	if err.find("manager_slot_index") < 0:
		return Result.failure("错误信息应包含 manager_slot_index，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_report_apply_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_report_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = {}
	var player_before := str(state.players[0])
	var action = ReportActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_report", 0, {
		"manager_slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("player.employees 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_report_apply_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_report_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["company_structure"] = []
	var player_before := str(state.players[0])
	var action = ReportActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_report", 0, {
		"manager_slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("player.company_structure 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].company_structure") < 0:
		return Result.failure("错误信息应包含 player[0].company_structure，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()

static func _test_report_apply_fails_fast_on_fractional_ceo_slots_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_report_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["company_structure"] = {
		"ceo_slots": 1.5,
		"structure": [
			{"employee_id": "local_manager", "reports": []},
		],
	}
	var player_before := str(state.players[0])
	var action = ReportActionClass.new()
	var result := action._apply_changes(state, Command.create("set_company_structure_report", 0, {
		"manager_slot_index": 0,
		"employee_id": "trainer",
	}))
	if result.ok:
		return Result.failure("fractional ceo_slots 时应失败")
	var err := str(result.error)
	if err.find("player.company_structure.ceo_slots") < 0:
		return Result.failure("错误信息应包含 player.company_structure.ceo_slots，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写 player")
	return Result.success()
