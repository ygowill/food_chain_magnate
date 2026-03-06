# initiate_marketing can_initiate 状态访问回归测试
class_name InitiateMarketingActionStateAccessTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const InitiateMarketingActionClass = preload("res://gameplay/actions/initiate_marketing_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_can_initiate_tolerates_invalid_employees_field(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_can_initiate_ignores_invalid_marketing_placements(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _init_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return init
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.turn_order = [0, 1]
	state.current_player_index = 0
	return Result.success(engine)

static func _test_can_initiate_tolerates_invalid_employees_field(player_count: int, seed_val: int) -> Result:
	var engine_r := _init_engine(player_count, seed_val)
	if not engine_r.ok:
		return Result.failure("初始化失败: %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	state.players[0]["employees"] = "bad"
	var action = InitiateMarketingActionClass.new()
	if not action.can_initiate(state, 0):
		return Result.failure("employees 字段损坏时应 fail-soft 返回 true，避免 UI 误隐藏动作")
	return Result.success()

static func _test_can_initiate_ignores_invalid_marketing_placements(player_count: int, seed_val: int) -> Result:
	var engine_r := _init_engine(player_count, seed_val)
	if not engine_r.ok:
		return Result.failure("初始化失败(case2): %s" % engine_r.error)
	var engine: GameEngine = engine_r.value
	var state := engine.get_state()
	state.players[0]["employees"] = ["marketing_trainee"]
	state.map["marketing_placements"] = "bad"
	var action = InitiateMarketingActionClass.new()
	if not action.can_initiate(state, 0):
		return Result.failure("marketing_placements 字段损坏时应忽略该字段而非误判不可发起")
	return Result.success()
