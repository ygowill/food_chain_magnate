# fire action 状态访问回归测试
class_name FireActionStateAccessTest
extends RefCounted

const FireActionClass = preload("res://gameplay/actions/fire_action.gd")

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
	r = _test_can_fire_busy_marketer_tolerates_invalid_recruit_used(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_can_fire_busy_marketer_tolerates_invalid_busy_marketer_entries(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 6})

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

static func _test_can_fire_busy_marketer_tolerates_invalid_recruit_used(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	var player := state.players[0]
	player["employees"] = []
	player["reserve_employees"] = []
	player["busy_marketers"] = ["campaign_manager"]
	player["cash"] = 0
	state.players[0] = player
	state.round_state["recruit_used"] = {
		"0": 1,
		0: 0,
	}
	var action = FireActionClass.new()
	if action._can_fire_busy_marketer(state, 0, "campaign_manager"):
		return Result.failure("recruit_used 损坏时应 fail-soft 返回 false")
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
