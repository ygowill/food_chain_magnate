class_name BankruptcyRegistry
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
	target.bankruptcy_first_break_handler = Callable()
	target.bankruptcy_first_break_source = "builtin"
	target.bankruptcy_loaded = true

static func is_loaded() -> bool:
	return bool(_get_bundle().bankruptcy_loaded)

static func has_first_break_handler() -> bool:
	return is_loaded() and _get_bundle().bankruptcy_first_break_handler.is_valid()

static func get_first_break_handler() -> Callable:
	if not is_loaded():
		return Callable()
	return _get_bundle().bankruptcy_first_break_handler

static func get_first_break_source() -> String:
	if not is_loaded():
		return ""
	return str(_get_bundle().bankruptcy_first_break_source)

static func configure_from_ruleset(ruleset, bundle = null) -> Result:
	if not is_loaded() and bundle == null:
		return Result.failure("BankruptcyRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.bankruptcy_handlers is Array):
		return Result.failure("BankruptcyRegistry.configure_from_ruleset: ruleset.bankruptcy_handlers 类型错误（期望 Array）")

	var target = _resolve_bundle(bundle)
	target.bankruptcy_first_break_handler = Callable()
	target.bankruptcy_first_break_source = "builtin"
	target.bankruptcy_loaded = true

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

		if target.bankruptcy_first_break_handler.is_valid():
			return Result.failure("BankruptcyRegistry: first_break handler 重复注册（existing:%s）" % str(target.bankruptcy_first_break_source))

		target.bankruptcy_first_break_handler = cb
		target.bankruptcy_first_break_source = str(item.get("source", ""))

	return Result.success()
