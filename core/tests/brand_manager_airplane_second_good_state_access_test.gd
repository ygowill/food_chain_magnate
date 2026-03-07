# brand manager airplane second good 状态访问回归测试
class_name BrandManagerAirplaneSecondGoodStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/new_milestones/actions/set_brand_manager_airplane_second_good_action.gd")
const PENDING_KEY := "new_milestones_brand_manager_airplane_pending"

class _FakeAirplaneApplyAction:
	extends ActionClass

	func _validate_specific(_state: GameState, _command: Command) -> Result:
		return Result.success({
			"board_number": 11,
			"product_a": "burger",
			"product_b": "pizza",
		})

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_validate_specific_reaches_milestone_check_with_valid_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_validate_specific_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	r = _test_apply_changes_updates_instance_and_placement()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_without_partial_mutation()
	if not r.ok:
		return r
	r = _test_apply_changes_fails_fast_on_invalid_pending_type_without_partial_mutation()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.players = [
		{"milestones": []},
		{"milestones": []},
	]
	state.round_state = {}
	state.map = {
		"marketing_placements": {},
	}
	state.turn_order = [0, 1]
	state.current_player_index = 0
	return state

static func _make_command() -> Command:
	var command := Command.create("set_brand_manager_airplane_second_good", 0)
	command.params = {
		"product_b": "burger",
	}
	return command

static func _make_apply_state() -> GameState:
	var state := GameState.new()
	state.players = [{}, {}]
	state.marketing_instances = [{
		"board_number": 11,
		"owner": 0,
		"type": "airplane",
		"employee_type": "brand_manager",
		"product": "burger",
	}]
	state.round_state = {
		PENDING_KEY: {0: {"board_number": 11}},
	}
	state.map = {
		"marketing_placements": {
			"11": {"board_number": 11, "product": "burger"},
		}
	}
	return state

static func _test_validate_specific_reaches_milestone_check_with_valid_placements() -> Result:
	var action = ActionClass.new()
	var result := action._validate_specific(_make_state(), _make_command())
	if result.ok:
		return Result.failure("未获里程碑时应失败")
	var err := str(result.error)
	if err.find("未获得里程碑") < 0:
		return Result.failure("有合法 marketing_placements 时应继续走到里程碑校验，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_missing_marketing_placements() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_validate_specific_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := action._validate_specific(state, _make_command())
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_apply_changes_updates_instance_and_placement() -> Result:
	var action = _FakeAirplaneApplyAction.new()
	var state := _make_apply_state()
	var result := action._apply_changes(state, _make_command())
	if not result.ok:
		return Result.failure("_apply_changes 不应失败: %s" % result.error)
	var inst: Dictionary = state.marketing_instances[0]
	var products_val = inst.get("products", null)
	if not (products_val is Array) or Array(products_val).size() != 2:
		return Result.failure("marketing_instance.products 应写入两种商品，实际: %s" % str(inst))
	var placement: Dictionary = state.map["marketing_placements"]["11"]
	var placement_products_val = placement.get("products", null)
	if not (placement_products_val is Array) or Array(placement_products_val).size() != 2:
		return Result.failure("placement.products 应写入两种商品，实际: %s" % str(placement))
	var pending: Dictionary = state.round_state.get(PENDING_KEY, {})
	if pending.has(0):
		return Result.failure("成功后应清除 actor pending，实际: %s" % str(pending))
	return Result.success()

static func _test_apply_changes_fails_fast_without_partial_mutation() -> Result:
	var action = _FakeAirplaneApplyAction.new()
	var state := _make_apply_state()
	state.map.erase("marketing_placements")
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	var inst: Dictionary = state.marketing_instances[0]
	if inst.has("products"):
		return Result.failure("失败时不应提前改写 marketing_instance.products")
	if str(inst.get("product", "")) != "burger":
		return Result.failure("失败时不应改写 marketing_instance.product，实际: %s" % str(inst))
	return Result.success()


static func _test_apply_changes_fails_fast_on_invalid_pending_type_without_partial_mutation() -> Result:
	var action = _FakeAirplaneApplyAction.new()
	var state := _make_apply_state()
	state.round_state[PENDING_KEY] = []
	var result := action._apply_changes(state, _make_command())
	if result.ok:
		return Result.failure("pending 类型错误时应失败")
	var err := str(result.error)
	if err.find("round_state.%s" % PENDING_KEY) < 0:
		return Result.failure("错误信息应包含 round_state.%s，实际: %s" % [PENDING_KEY, err])
	var inst: Dictionary = state.marketing_instances[0]
	if inst.has("products"):
		return Result.failure("失败时不应提前改写 marketing_instance.products")
	if str(inst.get("product", "")) != "burger":
		return Result.failure("失败时不应改写 marketing_instance.product，实际: %s" % str(inst))
	var placement: Dictionary = state.map["marketing_placements"]["11"]
	if placement.has("products"):
		return Result.failure("失败时不应提前改写 placement.products")
	return Result.success()
