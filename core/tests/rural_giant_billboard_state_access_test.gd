# rural giant billboard 状态访问回归测试
class_name RuralGiantBillboardStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/rural_marketeers/actions/place_giant_billboard_action.gd")
const EntryClass = preload("res://modules/rural_marketeers/rules/entry.gd")

static var _held_engines: Array = []

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	_held_engines.clear()
	var r := _test_validate_specific_succeeds_with_initialized_houses(seed_val)
	if not r.ok:
		return r
	r = _test_can_initiate_returns_false_on_missing_houses(seed_val)
	if not r.ok:
		return r
	r = _test_can_initiate_returns_false_on_invalid_rural_area_type(seed_val)
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_houses(seed_val)
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_invalid_rural_area_type(seed_val)
	if not r.ok:
		return r
	r = _test_validate_specific_rejects_unknown_product(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_writes_giant_billboard(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_unknown_product_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_without_partial_mutation(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 9})

static func _make_state(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"rural_marketeers",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return init
	_held_engines.append(engine)
	var state := engine.get_state()
	state.phase = "Working"
	state.sub_phase = "Marketing"
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["sub_phase_passed"] = {0: false, 1: false}
	var entry = EntryClass.new()
	var init_r := entry._on_restructuring_before_enter(state)
	if not init_r.ok:
		return Result.failure("初始化 rural_area 失败: %s" % init_r.error)
	var player: Dictionary = state.players[0]
	player["employees"] = ["ceo", "rural_marketeer"]
	player["busy_marketers"] = []
	state.players[0] = player
	return Result.success(state)

static func _make_command() -> Command:
	var command := Command.create("place_giant_billboard", 0)
	command.params = {
		"side": "N",
		"product": "burger",
	}
	return command

static func _test_validate_specific_succeeds_with_initialized_houses(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败: %s" % state_r.error)
	var state: GameState = state_r.value
	var action = ActionClass.new()
	var result := action._validate_specific(state, _make_command())
	if not result.ok:
		return Result.failure("_validate_specific 不应失败: %s" % result.error)
	return Result.success()

static func _test_can_initiate_returns_false_on_missing_houses(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case2): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map.erase("houses")
	var action = ActionClass.new()
	if action.can_initiate(state, 0):
		return Result.failure("缺失 houses 时 can_initiate 应返回 false")
	return Result.success()

static func _test_can_initiate_returns_false_on_invalid_rural_area_type(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case3): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map["houses"]["rural_area"] = []
	var action = ActionClass.new()
	if action.can_initiate(state, 0):
		return Result.failure("rural_area 类型错误时 can_initiate 应返回 false")
	return Result.success()

static func _test_validate_specific_fails_fast_on_missing_houses(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case2): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map.erase("houses")
	var action = ActionClass.new()
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_invalid_rural_area_type(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case3): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map["houses"]["rural_area"] = []
	var action = ActionClass.new()
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("rural_area 类型错误时应失败")
	var err := str(result.error)
	if err.find("缺少 rural_area") < 0:
		return Result.failure("错误信息应提示 rural_area 无效，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_rejects_unknown_product(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case4a): %s" % state_r.error)
	var state: GameState = state_r.value
	var action = ActionClass.new()
	var command := _make_command()
	command.params["product"] = "ghost_product"
	var result := action._validate_specific(state, command)
	if result.ok:
		return Result.failure("未知产品应失败")
	var err := str(result.error)
	if err.find("未知的产品") < 0:
		return Result.failure("错误信息应包含未知产品，实际: %s" % err)
	return Result.success()

static func _test_apply_changes_fails_fast_on_unknown_product_without_partial_mutation(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case4b): %s" % state_r.error)
	var state: GameState = state_r.value
	var action = ActionClass.new()
	var command := _make_command()
	command.params["product"] = "ghost_product"
	var result := action._apply_changes(state, command)
	if result.ok:
		return Result.failure("未知产品时 _apply_changes 应失败")
	var err := str(result.error)
	if err.find("未知的产品") < 0:
		return Result.failure("错误信息应包含未知产品，实际: %s" % err)
	var boards: Dictionary = state.map["houses"]["rural_area"]["giant_billboards"]
	if not boards.is_empty():
		return Result.failure("失败时不应提前写入 giant_billboards")
	if not Array(state.players[0].get("employees", [])).has("rural_marketeer"):
		return Result.failure("失败时不应提前移除 rural_marketeer")
	if Array(state.players[0].get("busy_marketers", [])).has("rural_marketeer"):
		return Result.failure("失败时不应提前写入 busy_marketers")
	return Result.success()

static func _test_apply_changes_writes_giant_billboard(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case4): %s" % state_r.error)
	var state: GameState = state_r.value
	var action = ActionClass.new()
	var result := action._apply_changes(state, _make_command())
	if not result.ok:
		return Result.failure("_apply_changes 不应失败: %s" % result.error)
	var boards: Dictionary = state.map["houses"]["rural_area"]["giant_billboards"]
	if not boards.has("N"):
		return Result.failure("giant_billboards 应写入 N 边")
	if Array(state.players[0].get("employees", [])).has("rural_marketeer"):
		return Result.failure("成功后 employees 不应保留 rural_marketeer")
	if not Array(state.players[0].get("busy_marketers", [])).has("rural_marketeer"):
		return Result.failure("成功后 busy_marketers 应包含 rural_marketeer")
	return Result.success()

static func _test_apply_changes_fails_fast_without_partial_mutation(seed_val: int) -> Result:
	var state_r := _make_state(seed_val)
	if not state_r.ok:
		return Result.failure("初始化失败(case5): %s" % state_r.error)
	var state: GameState = state_r.value
	state.map.erase("houses")
	var action = ActionClass.new()
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	if not Array(state.players[0].get("employees", [])).has("rural_marketeer"):
		return Result.failure("失败时不应提前移除 rural_marketeer")
	if Array(state.players[0].get("busy_marketers", [])).has("rural_marketeer"):
		return Result.failure("失败时不应提前写入 busy_marketers")
	return Result.success()
