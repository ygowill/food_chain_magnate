# DinnertimeRoutePurchaseRegistry（V2）严格校验测试
class_name DinnertimeRoutePurchaseRegistryV2Test
extends RefCounted

const RegistryClass = preload("res://core/rules/dinnertime_route_purchase_registry.gd")
const RulesetV2Class = preload("res://core/modules/v2/ruleset.gd")

class ProviderHost:
	extends RefCounted

	func ok_a(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({
			"purchases": [{"id": "a"}],
			"income_by_player": {0: 3},
		})

	func ok_b(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({
			"purchases": [{"id": "b"}],
			"income_by_player": {1: 7},
		})

	func bad_return_type(_state: GameState, _ctx: Dictionary):
		return {"ok": true}

	func bad_value_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success(123)

	func bad_purchases_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"purchases": 1})

	func bad_purchases_item_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"purchases": ["x"]})

	func bad_income_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"income_by_player": 1})

	func bad_income_key_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"income_by_player": {"0": 1}})

	func bad_income_value_type(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"income_by_player": {0: "x"}})

	func bad_income_negative(_state: GameState, _ctx: Dictionary) -> Result:
		return Result.success({"income_by_player": {0: -1}})

static func run(_player_count: int = 0, _seed_val: int = 0) -> Result:
	var r := _test_configure_validations()
	if not r.ok:
		return r

	r = _test_provider_order_and_merge()
	if not r.ok:
		return r

	r = _test_fail_fast_provider_outputs()
	if not r.ok:
		return r

	return Result.success({"cases": 3})

static func _test_configure_validations() -> Result:
	RegistryClass.reset()

	var cfg := RegistryClass.configure_from_ruleset(null)
	if cfg.ok:
		return Result.failure("configure_from_ruleset(ruleset=null) 不应成功")

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	ruleset.dinnertime_route_purchase_providers = [
		{"id": "t:dup", "callback": Callable(host, "ok_a"), "priority": 100, "source": "test"},
		{"id": "t:dup", "callback": Callable(host, "ok_b"), "priority": 100, "source": "test"},
	]
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if cfg.ok:
		return Result.failure("configure_from_ruleset(duplicate id) 不应成功")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	ruleset.dinnertime_route_purchase_providers = [
		{"id": "t:bad_cb", "callback": Callable(), "priority": 100, "source": "test"},
	]
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if cfg.ok:
		return Result.failure("configure_from_ruleset(invalid callback) 不应成功")

	return Result.success()

static func _test_provider_order_and_merge() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_route_purchase_provider("t:a", Callable(host, "ok_a"), 200, "test")
	if not r.ok:
		return r
	r = ruleset.register_dinnertime_route_purchase_provider("t:b", Callable(host, "ok_b"), 100, "test")
	if not r.ok:
		return r

	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)

	var s := GameState.new()
	s.players = [{}, {}]
	var out := RegistryClass.apply_for_house(s, {})
	if not out.ok:
		return Result.failure("apply_for_house 失败: %s" % out.error)
	if not (out.value is Dictionary):
		return Result.failure("apply_for_house.value 类型错误（期望 Dictionary）")
	var v: Dictionary = out.value

	var purchases_val = v.get("purchases", null)
	if not (purchases_val is Array):
		return Result.failure("purchases 类型错误（期望 Array）")
	var purchases: Array = purchases_val
	if purchases.size() != 2:
		return Result.failure("purchases 期望 2 条，实际: %d" % purchases.size())
	if str(purchases[0].get("id", "")) != "b":
		return Result.failure("优先级更高（priority 更小）的 provider 应先执行：期望 b 在前，实际: %s" % str(purchases))
	if str(purchases[1].get("id", "")) != "a":
		return Result.failure("purchases 顺序错误：期望 a 在后，实际: %s" % str(purchases))

	var income_val = v.get("income_by_player", null)
	if not (income_val is Dictionary):
		return Result.failure("income_by_player 类型错误（期望 Dictionary）")
	var income: Dictionary = income_val
	if int(income.get(0, 0)) != 3 or int(income.get(1, 0)) != 7:
		return Result.failure("income_by_player 汇总错误: %s" % str(income))

	return Result.success()

static func _test_fail_fast_provider_outputs() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()

	var r := ruleset.register_dinnertime_route_purchase_provider("t:bad_return", Callable(host, "bad_return_type"), 100, "test")
	if not r.ok:
		return r
	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	var s := GameState.new()
	s.players = [{}, {}]
	var out := RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("provider 返回非 Result 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_value", Callable(host, "bad_value_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("provider Result.value 非 Dictionary 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_purchases_type", Callable(host, "bad_purchases_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("purchases 非 Array 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_purchases_item", Callable(host, "bad_purchases_item_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("purchases[*] 非 Dictionary 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_income_type", Callable(host, "bad_income_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("income_by_player 非 Dictionary 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_income_key", Callable(host, "bad_income_key_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("income_by_player key 非 int 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_income_val", Callable(host, "bad_income_value_type"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("income_by_player value 非 int 时应失败")

	RegistryClass.reset()
	ruleset = RulesetV2Class.new()
	r = ruleset.register_dinnertime_route_purchase_provider("t:bad_income_neg", Callable(host, "bad_income_negative"), 100, "test")
	if not r.ok:
		return r
	cfg = RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)
	s = GameState.new()
	s.players = [{}, {}]
	out = RegistryClass.apply_for_house(s, {})
	if out.ok:
		return Result.failure("income_by_player 为负数时应失败")

	return Result.success()
