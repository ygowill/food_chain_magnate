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
	r = _test_generate_specific_events_returns_empty_on_invalid_employee_type_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_board_number_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_unknown_product()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_position_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_unknown_board_number()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_unknown_employee_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_non_marketing_employee()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_duration_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_duration_exceeds_max()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_airplane_axis_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_uninferrable_airplane_axis()
	if not r.ok:
		return r
	return Result.success({"cases": 13})

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

static func _make_event_state(grid_size: Vector2i = Vector2i(5, 5)) -> GameState:
	var state := GameState.new()
	state.map = {"grid_size": grid_size}
	return state

static func _make_valid_event_command(extra_params: Dictionary = {}) -> Command:
	var params := {
		"employee_type": "marketing_trainee",
		"board_number": 11,
		"product": "pizza",
		"position": [0, 0],
	}
	for key in extra_params.keys():
		params[key] = extra_params[key]
	return Command.create("initiate_marketing", 0, params)

static func _test_generate_specific_events_returns_empty_on_invalid_employee_type_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"employee_type": 1}))
	if not events.is_empty():
		return Result.failure("employee_type 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_board_number_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"board_number": "bad"}))
	if not events.is_empty():
		return Result.failure("board_number 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_unknown_product() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"product": "unknown_product"}))
	if not events.is_empty():
		return Result.failure("未知 product 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_position_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"position": "bad"}))
	if not events.is_empty():
		return Result.failure("position 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_unknown_board_number() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"board_number": 9999}))
	if not events.is_empty():
		return Result.failure("未知 board_number 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_unknown_employee_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"employee_type": "ghost_employee"}))
	if not events.is_empty():
		return Result.failure("未知 employee_type 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_non_marketing_employee() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"employee_type": "waitress"}))
	if not events.is_empty():
		return Result.failure("无营销时长的员工应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_duration_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"duration": "bad"}))
	if not events.is_empty():
		return Result.failure("duration 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_duration_exceeds_max() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"duration": 99}))
	if not events.is_empty():
		return Result.failure("duration 超出上限时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_airplane_axis_type() -> Result:
	var action = InitiateMarketingActionClass.new()
	var events := action._generate_specific_events(null, _make_event_state(), _make_valid_event_command({"board_number": 6, "axis": 1}))
	if not events.is_empty():
		return Result.failure("airplane axis 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_uninferrable_airplane_axis() -> Result:
	var action = InitiateMarketingActionClass.new()
	var state := _make_event_state(Vector2i(5, 5))
	var events := action._generate_specific_events(null, state, _make_valid_event_command({"board_number": 6, "position": [1, 1]}))
	if not events.is_empty():
		return Result.failure("无法推断 airplane axis 时应返回空事件列表")
	return Result.success()
