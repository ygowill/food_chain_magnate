# RulesetV2：各类 provider/handler 注册下沉（marketing/bankruptcy/dinnertime）
class_name RulesetV2ProviderRegistration
extends RefCounted

static func register_marketing_initiation_provider(
	ruleset,
	provider_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: marketing initiation provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: marketing initiation provider callback 无效: %s" % provider_id)
	for item_val in ruleset.marketing_initiation_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: marketing initiation provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	ruleset.marketing_initiation_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.marketing_initiation_providers.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.id) != str(b.id):
			return str(a.id) < str(b.id)
		return str(a.source) < str(b.source)
	)
	return Result.success()

static func register_bankruptcy_handler(ruleset, kind: String, callback: Callable, source_module_id: String = "") -> Result:
	if kind.is_empty():
		return Result.failure("RulesetV2: bankruptcy kind 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: bankruptcy handler callback 无效: %s" % kind)
	for item_val in ruleset.bankruptcy_handlers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")) == kind:
			return Result.failure("RulesetV2: bankruptcy handler 重复注册: %s (module:%s)" % [kind, source_module_id])
	ruleset.bankruptcy_handlers.append({
		"kind": kind,
		"callback": callback,
		"source": source_module_id,
	})
	return Result.success()

static func register_dinnertime_demand_provider(
	ruleset,
	provider_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: dinnertime demand provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: dinnertime demand provider callback 无效: %s" % provider_id)
	for item_val in ruleset.dinnertime_demand_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: dinnertime demand provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	ruleset.dinnertime_demand_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

static func register_dinnertime_route_purchase_provider(
	ruleset,
	provider_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if provider_id.is_empty():
		return Result.failure("RulesetV2: dinnertime route provider_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: dinnertime route provider callback 无效: %s" % provider_id)
	for item_val in ruleset.dinnertime_route_purchase_providers:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("id", "")) == provider_id:
			return Result.failure("RulesetV2: dinnertime route provider 重复注册: %s (module:%s)" % [provider_id, source_module_id])
	ruleset.dinnertime_route_purchase_providers.append({
		"id": provider_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

