# fire action 状态访问回归测试
class_name FireActionStateAccessTest
extends RefCounted

const FireActionClass = preload("res://gameplay/actions/fire_action.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_find_employee_location_reads_player_arrays()
	if not r.ok:
		return r
	r = _test_find_employee_location_returns_empty_when_absent()
	if not r.ok:
		return r
	r = _test_find_employee_location_tolerates_invalid_array_entries()
	if not r.ok:
		return r
	r = _test_can_fire_busy_marketer_tolerates_invalid_cash_field(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_can_fire_busy_marketer_tolerates_invalid_staff_usage(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_can_fire_busy_marketer_tolerates_invalid_busy_marketer_entries(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_missing_employee_id()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_on_invalid_location_type()
	if not r.ok:
		return r
	r = _test_generate_specific_events_returns_empty_when_location_cannot_be_inferred()
	if not r.ok:
		return r
	return Result.success({"cases": 9})

static func _test_find_employee_location_reads_player_arrays() -> Result:
	var action = FireActionClass.new()
	var player := {
		"employees": ["pizza_cook"],
		"reserve_employees": ["burger_cook"],
		"busy_marketers": ["campaign_manager"],
	}
	if action._find_employee_location(player, "pizza_cook") != "active":
		return Result.failure("pizza_cook 应识别为 active")
	if action._find_employee_location(player, "burger_cook") != "reserve":
		return Result.failure("burger_cook 应识别为 reserve")
	if action._find_employee_location(player, "campaign_manager") != "busy":
		return Result.failure("campaign_manager 应识别为 busy")
	return Result.success()

static func _test_find_employee_location_returns_empty_when_absent() -> Result:
	var action = FireActionClass.new()
	var player := {
		"employees": ["pizza_cook"],
		"reserve_employees": [],
		"busy_marketers": [],
	}
	if not action._find_employee_location(player, "trainer").is_empty():
		return Result.failure("不存在的员工应返回空 location")
	return Result.success()

static func _test_find_employee_location_tolerates_invalid_array_entries() -> Result:
	var action = FireActionClass.new()
	var player := {
		"employees": ["pizza_cook", 1],
		"reserve_employees": [],
		"busy_marketers": [],
	}
	if not action._find_employee_location(player, "pizza_cook").is_empty():
		return Result.failure("数组元素损坏时应 fail-soft 返回空 location")
	return Result.success()

static func _test_can_fire_busy_marketer_tolerates_invalid_cash_field(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	var player := state.players[0]
	player["employees"] = []
	player["reserve_employees"] = []
	player["busy_marketers"] = ["campaign_manager"]
	player["cash"] = "bad"
	state.players[0] = player
	var action = FireActionClass.new()
	if action._can_fire_busy_marketer(state, 0, "campaign_manager"):
		return Result.failure("cash 字段损坏时应 fail-soft 返回 false")
	return Result.success()

static func _test_can_fire_busy_marketer_tolerates_invalid_staff_usage(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	var player := state.players[0]
	player["employees"] = ["recruiting_manager"]
	player["reserve_employees"] = []
	player["busy_marketers"] = ["campaign_manager"]
	player["cash"] = 0
	state.players[0] = player
	var sync := StaffStateClass.ensure_state_staff_support(state)
	if not sync.ok:
		return Result.failure("同步 staff 支持失败: %s" % sync.error)
	var manager_staff_id := int(Array(state.players[0].get("employees_staff_ids", []))[0])
	state.round_state["staff_usage"] = {manager_staff_id: {"recruit": -1}}
	var action = FireActionClass.new()
	if action._can_fire_busy_marketer(state, 0, "campaign_manager"):
		return Result.failure("staff_usage 损坏时应 fail-soft 返回 false")
	return Result.success()

static func _test_can_fire_busy_marketer_tolerates_invalid_busy_marketer_entries(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	var player := state.players[0]
	player["employees"] = []
	player["reserve_employees"] = []
	player["busy_marketers"] = ["campaign_manager", 1]
	player["cash"] = 0
	state.players[0] = player
	var action = FireActionClass.new()
	if action._can_fire_busy_marketer(state, 0, "campaign_manager"):
		return Result.failure("busy_marketers 条目损坏时应 fail-soft 返回 false")
	return Result.success()

static func _make_event_state() -> GameState:
	var state := GameState.new()
	state.players = [{
		"employees": ["pizza_cook"],
		"reserve_employees": [],
		"busy_marketers": [],
	}]
	return state

static func _test_generate_specific_events_returns_empty_on_missing_employee_id() -> Result:
	var action = FireActionClass.new()
	var state := _make_event_state()
	var events := action._generate_specific_events(state, state, Command.create("fire", 0, {}))
	if not events.is_empty():
		return Result.failure("缺失 employee_id 时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_on_invalid_location_type() -> Result:
	var action = FireActionClass.new()
	var state := _make_event_state()
	var events := action._generate_specific_events(state, state, Command.create("fire", 0, {
		"employee_id": "pizza_cook",
		"location": 1,
	}))
	if not events.is_empty():
		return Result.failure("location 类型错误时应返回空事件列表")
	return Result.success()

static func _test_generate_specific_events_returns_empty_when_location_cannot_be_inferred() -> Result:
	var action = FireActionClass.new()
	var state := _make_event_state()
	var events := action._generate_specific_events(state, state, Command.create("fire", 0, {
		"employee_id": "trainer",
	}))
	if not events.is_empty():
		return Result.failure("无法推断 location 时应返回空事件列表")
	return Result.success()
