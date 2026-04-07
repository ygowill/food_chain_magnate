class_name MarketingTypeRegistry
extends RefCounted

const RulesRegistryBundleClass = preload("res://core/engine/game_engine/rules_registry_bundle.gd")

static var _current_bundle = RulesRegistryBundleClass.new()

static func _get_bundle():
	if _current_bundle == null:
		_current_bundle = RulesRegistryBundleClass.new()
	return _current_bundle

static func _resolve_bundle(bundle = null):
	if bundle != null:
		return bundle
	return _get_bundle()

static func set_current_bundle(bundle) -> void:
	_current_bundle = bundle if bundle != null else RulesRegistryBundleClass.new()

static func reset_current_bundle() -> void:
	_current_bundle = null

static func reset() -> void:
	var target = _get_bundle()
	target.marketing_types.clear()
	target.marketing_type_loaded = true

static func is_loaded() -> bool:
	return bool(_get_bundle().marketing_type_loaded)

static func has_type(type_id: String) -> bool:
	if not is_loaded():
		return false
	return _get_bundle().marketing_types.has(type_id)

static func requires_edge(type_id: String) -> bool:
	if not is_loaded():
		return false
	if not _get_bundle().marketing_types.has(type_id):
		return false
	var item: Dictionary = _get_bundle().marketing_types[type_id]
	var v = item.get("requires_edge", false)
	return v is bool and bool(v)

static func get_range_handler(type_id: String) -> Callable:
	if not is_loaded():
		return Callable()
	if not _get_bundle().marketing_types.has(type_id):
		return Callable()
	var item: Dictionary = _get_bundle().marketing_types[type_id]
	var cb = item.get("range_handler", Callable())
	if cb is Callable:
		return cb
	return Callable()

static func configure_from_ruleset(ruleset, bundle = null) -> Result:
	if not is_loaded() and bundle == null:
		return Result.failure("MarketingTypeRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.marketing_type_registrations is Array):
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset.marketing_type_registrations 缺失或类型错误（期望 Array）")

	var target = _resolve_bundle(bundle)
	target.marketing_types.clear()
	target.marketing_type_loaded = true

	for i in range(ruleset.marketing_type_registrations.size()):
		var item_val = ruleset.marketing_type_registrations[i]
		if not (item_val is Dictionary):
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var type_val = item.get("type_id", null)
		if not (type_val is String):
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d].type_id 类型错误（期望 String）" % i)
		var type_id: String = str(type_val)
		if type_id.is_empty():
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d].type_id 不能为空" % i)
		if target.marketing_types.has(type_id):
			var existing: Dictionary = target.marketing_types[type_id]
			return Result.failure("MarketingTypeRegistry: marketing type 重复注册: %s (existing:%s)" % [type_id, str(existing.get("source", ""))])

		var requires_edge_val = item.get("requires_edge", false)
		if not (requires_edge_val is bool):
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d].requires_edge 类型错误（期望 bool）" % i)
		var requires_edge: bool = bool(requires_edge_val)

		var cb_val = item.get("range_handler", Callable())
		if not (cb_val is Callable):
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d].range_handler 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("MarketingTypeRegistry: marketing_type_registrations[%d].range_handler 无效: %s" % [i, type_id])

		var src: String = str(item.get("source", ""))
		target.marketing_types[type_id] = {
			"requires_edge": requires_edge,
			"range_handler": cb,
			"source": src,
		}

	return Result.success(target.marketing_types.size())
