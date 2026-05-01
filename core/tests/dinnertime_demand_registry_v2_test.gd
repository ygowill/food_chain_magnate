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

	func array_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary) -> Array:
		return [
			{"id": "array", "rank": 20, "required": {"pizza": 1}},
		]

	func null_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary):
		return null

	func bad_return_type(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary):
		return 123

	func fail_provider(_state: GameState, _house_id: String, _house: Dictionary, _base_required: Dictionary) -> Result:
		return Result.failure("boom")

static func run(_player_count: int = 0, _seed_val: int = 0) -> Result:
	var r := _test_accept_result_return_type()
	if not r.ok:
		return r

	r = _test_reject_legacy_array_and_null_return_types()
	if not r.ok:
		return r

	r = _test_fail_fast_bad_return_type()
	if not r.ok:
		return r

	r = _test_fail_fast_provider_failure()
	if not r.ok:
		return r

	return Result.success({"cases": 4})

static func _test_accept_result_return_type() -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_demand_provider("t:result", Callable(host, "result_provider"), 100, "test")
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
	if variants.size() != 1:
		return Result.failure("variants 期望 1 条，实际: %d" % variants.size())
	if not (variants[0] is Dictionary):
		return Result.failure("variants[*] 类型错误（期望 Dictionary）: %s" % str(variants))
	if str(variants[0].get("id", "")) != "result":
		return Result.failure("variants 内容错误：%s" % str(variants))

	return Result.success()

static func _test_reject_legacy_array_and_null_return_types() -> Result:
	var array_r := _assert_provider_return_fails("t:array", "array_provider", "期望 Result")
	if not array_r.ok:
		return array_r
	var null_r := _assert_provider_return_fails("t:null", "null_provider", "期望 Result")
	if not null_r.ok:
		return null_r
	return Result.success()

static func _test_fail_fast_bad_return_type() -> Result:
	return _assert_provider_return_fails("t:bad", "bad_return_type", "期望 Result")

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

static func _assert_provider_return_fails(provider_id: String, method_name: String, expected_error_fragment: String) -> Result:
	RegistryClass.reset()

	var ruleset := RulesetV2Class.new()
	var host := ProviderHost.new()
	var r := ruleset.register_dinnertime_demand_provider(provider_id, Callable(host, method_name), 100, "test")
	if not r.ok:
		return r

	var cfg := RegistryClass.configure_from_ruleset(ruleset)
	if not cfg.ok:
		return Result.failure("configure_from_ruleset 失败: %s" % cfg.error)

	var s := GameState.new()
	var out := RegistryClass.get_variants(s, "h1", {}, {"burger": 1})
	if out.ok:
		return Result.failure("provider 返回非 Result 时应失败: %s" % method_name)
	if str(out.error).find(expected_error_fragment) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [expected_error_fragment, out.error])

	return Result.success()
