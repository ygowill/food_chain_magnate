# 发起营销扩展注册表（模块化，Fail Fast）
# 用于在 initiate_marketing 动作完成基础放置后，由模块进行额外处理：
# - campaign manager：同类型第二张营销板件
# - brand manager：飞机双商品等
class_name MarketingInitiationRegistry
extends RefCounted

static var _providers: Array = [] # Array[{id, callback, priority, source}]
static var _loaded: bool = false

static func reset() -> void:
	_providers = []
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("MarketingInitiationRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("MarketingInitiationRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("MarketingInitiationRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.marketing_initiation_providers is Array):
		return Result.failure("MarketingInitiationRegistry.configure_from_ruleset: ruleset.marketing_initiation_providers 缺失或类型错误（期望 Array）")

	for i in range(ruleset.marketing_initiation_providers.size()):
		var item_val = ruleset.marketing_initiation_providers[i]
		if not (item_val is Dictionary):
			return Result.failure("MarketingInitiationRegistry: marketing_initiation_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("MarketingInitiationRegistry: marketing_initiation_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val)
		if provider_id.is_empty():
			return Result.failure("MarketingInitiationRegistry: marketing_initiation_providers[%d].id 不能为空" % i)

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("MarketingInitiationRegistry: marketing_initiation_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("MarketingInitiationRegistry: marketing_initiation_providers[%d].callback 无效: %s" % [i, provider_id])

		var prio: int = int(item.get("priority", 100))
		var src: String = str(item.get("source", ""))

		for prev_val in _providers:
			if prev_val is Dictionary and str((prev_val as Dictionary).get("id", "")) == provider_id:
				return Result.failure("MarketingInitiationRegistry: provider 重复注册: %s" % provider_id)

		_providers.append({
			"id": provider_id,
			"callback": cb,
			"priority": prio,
			"source": src,
		})

	_providers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)

	return Result.success(_providers.size())

static func apply(state: GameState, command: Command, marketing_instance: Dictionary) -> Result:
	if not _loaded:
		return Result.failure("MarketingInitiationRegistry 未初始化")
	if _providers.is_empty():
		return Result.success()
	if state == null:
		return Result.failure("MarketingInitiationRegistry.apply: state 为空")
	if command == null:
		return Result.failure("MarketingInitiationRegistry.apply: command 为空")
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("MarketingInitiationRegistry.apply: marketing_instance 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	for i in range(_providers.size()):
		var item_val = _providers[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var cb: Callable = item.get("callback", Callable())
		if not cb.is_valid():
			return Result.failure("MarketingInitiationRegistry: provider callback 无效: %s" % str(item.get("id", "")))

		var r = cb.call(state, command, marketing_instance)
		if not (r is Result):
			return Result.failure("MarketingInitiationRegistry: provider 必须返回 Result: %s" % str(item.get("id", "")))
		var rr: Result = r
		if not rr.ok:
			return rr
		warnings.append_array(rr.warnings)

	return Result.success().with_warnings(warnings)

