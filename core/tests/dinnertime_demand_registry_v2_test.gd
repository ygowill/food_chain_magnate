# DinnertimeDemandRegistry（V2）provider 返回值契约测试
class_name DinnertimeDemandRegistryV2Test
extends RefCounted

const RegistryClass = preload("res://core/rules/dinnertime_demand_registry.gd")
const RulesetV2Class = preload("res://core/modules/v2/ruleset.gd")

class ProviderHost:
	extends RefCounted

	func result_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary) -> Result:
		return Result.success([
			{"id": "result", "rank": 10, "required": {"burger": 2}},
		]).with_warning("demand_provider_warning")

	func legacy_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary) -> Array:
		return [
			{"id": "legacy", "rank": 20, "required": {"pizza": 1}},
		]

	func bad_return_type(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary):
		return 123

	func fail_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary) -> Result:
		return Result.failure("boom")

static func run(_player_count: int = 0, _seed_val: int = 0) -> Result:
	var r := _test_accept_result_and_legacy_return_types()
	if not r.ok:
		return r

	r = _test_fail_fast_bad_return_type()
	if not r.ok:
		return r

	r = _test_fail_fast_provider_failure()
	if not r.ok:
		return r

	return Result.success({"cases": 3})

static func _test_accept_result_and_legacy_return_types() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_demand_provider("t:result", Callable(host, "result_provider"), 100, "test")
	if not r.ok:
		return r
	r = ruleset.register_dinnertime_demand_provider("t:legacy", Callable(host, "legacy_provider"), 110, "test")
	if not r.ok:
		return r

	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)

	var s := GameState.new()
	var out := RegistryClass.get_variants(s, "h1", {}, {"burger": 1})
	if not out.ok:
		return Result.failure("get_variants 失败: %s" % out.error)
	if out.warnings.find("demand_provider_warning") == -1:
		return Result.failure("预期 warnings 包含 demand_provider_warning，实际: %s" % str(out.warnings))

	if not (out.value is Array):
		return Result.failure("get_variants.value 类型错误（期望 Array）")
	var variants: Array = out.value
	if variants.size() != 2:
		return Result.failure("variants 期望 2 条，实际: %d" % variants.size())
	if not (variants[0] is Dictionary) or not (variants[1] is Dictionary):
		return Result.failure("variants[*] 类型错误（期望 Dictionary）: %s" % str(variants))
	if str(variants[0].get("id", "")) != "result" or str(variants[1].get("id", "")) != "legacy":
		return Result.failure("variants 顺序/内容错误（应按 rank 升序）：%s" % str(variants))

	return Result.success()

static func _test_fail_fast_bad_return_type() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_demand_provider("t:bad", Callable(host, "bad_return_type"), 100, "test")
	if not r.ok:
		return r

	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)

	var s := GameState.new()
	var out := RegistryClass.get_variants(s, "h1", {}, {"burger": 1})
	if out.ok:
		return Result.failure("provider 返回非 Array/Result 时应失败")

	return Result.success()

static func _test_fail_fast_provider_failure() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_demand_provider("t:fail", Callable(host, "fail_provider"), 100, "test")
	if not r.ok:
		return r

	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)

	var s := GameState.new()
	var out := RegistryClass.get_variants(s, "h1", {}, {"burger": 1})
	if out.ok:
		return Result.failure("provider Result.ok=false 时应失败")

	return Result.success()

