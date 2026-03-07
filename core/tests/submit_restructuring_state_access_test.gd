# submit_restructuring 状态访问回归测试
class_name SubmitRestructuringStateAccessTest
extends RefCounted

const ActionClass = preload("res://gameplay/actions/submit_restructuring_action.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _build_submit_restructuring_state(player_count: int, seed_val: int) -> Result:
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
	state.round_state["pending_phase_actions"] = {DefsClass.PHASE_RESTRUCTURING: [0, 1]}
	return Result.success(state)

static func _test_apply_changes_fails_fast_on_invalid_pending_phase_actions_without_partial_mutation(player_count: int, seed_val: int) -> Result:
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
	state.round_state["pending_phase_actions"] = []
	var player_before: String = str(state.players[0])
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("submit_restructuring", 0, {}))
	if result.ok:
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var err := str(result.error)
	if err.find("pending_phase_actions") < 0:
		return Result.failure("错误信息应包含 pending_phase_actions，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家结构或员工状态")
	var restructuring_val = state.round_state.get("restructuring", null)
	if not (restructuring_val is Dictionary):
		return Result.failure("失败后 restructuring 应仍为 Dictionary")
	var restructuring: Dictionary = restructuring_val
	var submitted_val = restructuring.get("submitted", null)
	if not (submitted_val is Dictionary):
		return Result.failure("失败后 submitted 应仍为 Dictionary")
	if bool((submitted_val as Dictionary).get(0, false)):
		return Result.failure("失败时不应提前标记 player 0 已提交")
	if bool(restructuring.get("finalized", true)):
		return Result.failure("失败时 finalized 不应提前变为 true")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_player_employees_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_submit_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["employees"] = {}
	var player_before := str(state.players[0])
	var restructuring_before := str(state.round_state.get("restructuring", {}))
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("submit_restructuring", 0, {}))
	if result.ok:
		return Result.failure("player.employees 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].employees") < 0:
		return Result.failure("错误信息应包含 player[0].employees，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家结构或员工状态")
	if str(state.round_state.get("restructuring", {})) != restructuring_before:
		return Result.failure("失败时 restructuring 不应提前变化")
	return Result.success()

static func _test_apply_changes_fails_fast_on_invalid_company_structure_without_partial_mutation(player_count: int, seed_val: int) -> Result:
	var built := _build_submit_restructuring_state(player_count, seed_val)
	if not built.ok:
		return built
	var state: GameState = built.value
	state.players[0]["company_structure"] = []
	var player_before := str(state.players[0])
	var restructuring_before := str(state.round_state.get("restructuring", {}))
	var action = ActionClass.new()
	var result := action._apply_changes(state, Command.create("submit_restructuring", 0, {}))
	if result.ok:
		return Result.failure("player.company_structure 类型错误时应失败")
	var err := str(result.error)
	if err.find("player[0].company_structure") < 0:
		return Result.failure("错误信息应包含 player[0].company_structure，实际: %s" % err)
	if str(state.players[0]) != player_before:
		return Result.failure("失败时不应提前改写玩家结构或员工状态")
	if str(state.round_state.get("restructuring", {})) != restructuring_before:
		return Result.failure("失败时 restructuring 不应提前变化")
	return Result.success()
