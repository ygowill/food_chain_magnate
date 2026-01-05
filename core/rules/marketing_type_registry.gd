class_name MarketingTypeRegistry
extends RefCounted

static var _types: Dictionary = {} # type_id -> {requires_edge: bool, range_handler: Callable, source: String}
static var _loaded: bool = false

static func reset() -> void:
	_types.clear()
	_loaded = true
	_register_builtin("billboard", false)
	_register_builtin("mailbox", false)
	_register_builtin("radio", false)
	_register_builtin("airplane", true)

static func _register_builtin(type_id: String, requires_edge: bool) -> void:
	_types[type_id] = {
		"requires_edge": requires_edge,
		"range_handler": Callable(),
		"source": "builtin",
	}

static func is_loaded() -> bool:
	return _loaded

static func has_type(type_id: String) -> bool:
	if not _loaded:
		return false
	return _types.has(type_id)

static func requires_edge(type_id: String) -> bool:
	if not _loaded:
		return false
	if not _types.has(type_id):
		return false
	var item: Dictionary = _types[type_id]
	var v = item.get("requires_edge", false)
	return v is bool and bool(v)

static func get_range_handler(type_id: String) -> Callable:
	if not _loaded:
		return Callable()
	if not _types.has(type_id):
		return Callable()
	var item: Dictionary = _types[type_id]
	var cb = item.get("range_handler", Callable())
	if cb is Callable:
		return cb
	return Callable()

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("MarketingTypeRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.marketing_type_registrations is Array):
		return Result.failure("MarketingTypeRegistry.configure_from_ruleset: ruleset.marketing_type_registrations 缺失或类型错误（期望 Array）")

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
		if _types.has(type_id):
			var existing: Dictionary = _types[type_id]
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
		_types[type_id] = {
			"requires_edge": requires_edge,
			"range_handler": cb,
			"source": src,
		}

	return Result.success(_types.size())
