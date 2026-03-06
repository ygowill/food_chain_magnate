# mandatory actions rules 状态访问回归测试
class_name MandatoryActionsRulesStateAccessTest
extends RefCounted

const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_find_provider_employee_id_reads_employees(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_get_required_mandatory_actions_reads_employees(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 2})

static func _make_player(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return init
	var state := engine.get_state()
	var player: Dictionary = state.players[0]
	player["employees"] = ["pricing_manager", "discount_manager", "pricing_manager"]
	return Result.success(player)

static func _test_find_provider_employee_id_reads_employees(player_count: int, seed_val: int) -> Result:
	var player_r := _make_player(player_count, seed_val)
	if not player_r.ok:
		return Result.failure("初始化失败: %s" % player_r.error)
	var player: Dictionary = player_r.value
	var pricing := MandatoryActionsRulesClass.find_provider_employee_id(player, ActionIdsClass.SET_PRICE)
	if pricing != "pricing_manager":
		return Result.failure("set_price 应由 pricing_manager 提供，实际: %s" % pricing)
	var discount := MandatoryActionsRulesClass.find_provider_employee_id(player, ActionIdsClass.SET_DISCOUNT)
	if discount != "discount_manager":
		return Result.failure("set_discount 应由 discount_manager 提供，实际: %s" % discount)
	return Result.success()

static func _test_get_required_mandatory_actions_reads_employees(player_count: int, seed_val: int) -> Result:
	var player_r := _make_player(player_count, seed_val)
	if not player_r.ok:
		return Result.failure("初始化失败(case2): %s" % player_r.error)
	var player: Dictionary = player_r.value
	var required := MandatoryActionsRulesClass.get_required_mandatory_actions(player)
	if required.size() != 2:
		return Result.failure("应只返回两个去重后的强制动作，实际: %s" % str(required))
	if not required.has(ActionIdsClass.SET_PRICE):
		return Result.failure("required 应包含 set_price，实际: %s" % str(required))
	if not required.has(ActionIdsClass.SET_DISCOUNT):
		return Result.failure("required 应包含 set_discount，实际: %s" % str(required))
	return Result.success()
