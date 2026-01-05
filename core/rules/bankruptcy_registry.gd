class_name BankruptcyRegistry
extends RefCounted

static var _first_break_handler: Callable = Callable()
static var _first_break_source: String = ""
static var _loaded: bool = false

static func reset() -> void:
	_first_break_handler = Callable()
	_first_break_source = "builtin"
	_loaded = true

static func is_loaded() -> bool:
	return _loaded

static func has_first_break_handler() -> bool:
	return _loaded and _first_break_handler.is_valid()

static func get_first_break_handler() -> Callable:
	if not _loaded:
		return Callable()
	return _first_break_handler

static func get_first_break_source() -> String:
	if not _loaded:
		return ""
	return _first_break_source

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("BankruptcyRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.bankruptcy_handlers is Array):
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset.bankruptcy_handlers 类型错误（期望 Array）")

	for i in range(ruleset.bankruptcy_handlers.size()):
		var item_val = ruleset.bankruptcy_handlers[i]
		if not (item_val is Dictionary):
			return Result.failure("BankruptcyRegistry: bankruptcy_handlers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var kind_val = item.get("kind", null)
		if not (kind_val is String):
			return Result.failure("BankruptcyRegistry: bankruptcy_handlers[%d].kind 类型错误（期望 String）" % i)
		var kind: String = str(kind_val)
		if kind.is_empty():
			return Result.failure("BankruptcyRegistry: bankruptcy_handlers[%d].kind 不能为空" % i)
		if kind != "first_break":
			return Result.failure("BankruptcyRegistry: 未知 handler kind: %s" % kind)

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("BankruptcyRegistry: bankruptcy_handlers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("BankruptcyRegistry: bankruptcy_handlers[%d].callback 无效" % i)

		if _first_break_handler.is_valid():
			return Result.failure("BankruptcyRegistry: first_break handler 重复注册（existing:%s）" % _first_break_source)

		_first_break_handler = cb
		_first_break_source = str(item.get("source", ""))

	return Result.success()

