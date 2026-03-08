# RangeOriginRegistry：模块可插拔地扩展“range 起点”集合（例如 Coffee 的 coffee_shop）。
# 用途：避免 core/utils/range_utils_* 直接读取模块私有 state（state.map.coffee_shops 等）。
#
# provider 签名：
#   func (state: GameState, ctx: Dictionary) -> Result
#
# ctx（由 RangeUtils 组装）：
#   {
#     "actor": int,
#     "restaurant_ids": Array[String], # 调用方传入的餐厅列表（可能为空）
#     "kind": String,                 # "road" | "air" | ""（可选）
#   }
#
# provider 输出：
#   Result.value = Array[Vector2i]    # 额外起点（world_pos/anchor_pos）
class_name RangeOriginRegistry
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
	_current_bundle = RulesRegistryBundleClass.new()

static func reset() -> void:
	var target = _get_bundle()
	target.range_origin_providers = []
	target.range_origin_loaded = true

static func is_loaded() -> bool:
	return bool(_get_bundle().range_origin_loaded)

static func get_provider_ids() -> Array[String]:
	if not is_loaded():
		return []
	var ids: Array[String] = []
	for item_val in _get_bundle().range_origin_providers:
		if item_val is Dictionary:
			var provider_id := str((item_val as Dictionary).get("id", "")).strip_edges()
			if not provider_id.is_empty():
				ids.append(provider_id)
	return ids

static func configure_from_ruleset(ruleset, bundle = null) -> Result:
	if not is_loaded() and bundle == null:
		return Result.failure("RangeOriginRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("RangeOriginRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("RangeOriginRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.range_origin_providers is Array):
		return Result.failure("RangeOriginRegistry.configure_from_ruleset: ruleset.range_origin_providers 缺失或类型错误（期望 Array）")

	var seen := {}
	var target = _resolve_bundle(bundle)
	target.range_origin_providers = []
	target.range_origin_loaded = true
	var seq: int = 0

	for i in range(ruleset.range_origin_providers.size()):
		var item_val = ruleset.range_origin_providers[i]
		if not (item_val is Dictionary):
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val)
		if provider_id.is_empty():
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d].id 不能为空" % i)
		if seen.has(provider_id):
			return Result.failure("RangeOriginRegistry: provider 重复注册: %s" % provider_id)
		seen[provider_id] = true

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d].callback 无效: %s" % [i, provider_id])

		var prio_val = item.get("priority", 100)
		if not (prio_val is int):
			return Result.failure("RangeOriginRegistry: range_origin_providers[%d].priority 类型错误（期望 int）" % i)
		var priority: int = int(prio_val)

		target.range_origin_providers.append({
			"id": provider_id,
			"priority": priority,
			"callback": cb,
			"source": str(item.get("source", "")),
			"seq": seq,
		})
		seq += 1

	target.range_origin_providers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: int = int(a.get("priority", 100))
		var bp: int = int(b.get("priority", 100))
		if ap != bp:
			return ap < bp
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)

	return Result.success(target.range_origin_providers.size())

static func get_extra_origin_positions(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String] = [],
	kind: String = ""
) -> Result:
	# 允许 RangeUtils 在 registry 未初始化时退化为“无额外起点”，避免无关场景硬失败。
	if not is_loaded():
		return Result.success([] as Array[Vector2i])
	if _get_bundle().range_origin_providers.is_empty():
		return Result.success([] as Array[Vector2i])
	if state == null:
		return Result.failure("RangeOriginRegistry.get_extra_origin_positions: state 为空")
	if restaurant_ids == null:
		return Result.failure("RangeOriginRegistry.get_extra_origin_positions: restaurant_ids 为空")

	var ctx := {
		"actor": actor,
		"restaurant_ids": restaurant_ids,
		"kind": kind,
	}

	var warnings: Array[String] = []
	var out_set := {}
	var out: Array[Vector2i] = []

	for i in range(_get_bundle().range_origin_providers.size()):
		var item_val = _get_bundle().range_origin_providers[i]
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var provider_id: String = str(item.get("id", ""))

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("RangeOriginRegistry: provider.callback 类型错误（期望 Callable）: %s" % provider_id)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("RangeOriginRegistry: provider.callback 无效: %s" % provider_id)

		var r = cb.call(state, ctx.duplicate(true))
		if r == null or not (r is Result):
			return Result.failure("RangeOriginRegistry: provider 必须返回 Result: %s" % provider_id)
		var rr: Result = r
		if not rr.ok:
			return Result.failure("RangeOriginRegistry: provider 失败: %s: %s" % [provider_id, rr.error])
		warnings.append_array(rr.warnings)

		var list_val = rr.value
		if list_val == null:
			continue
		if not (list_val is Array):
			return Result.failure("RangeOriginRegistry: provider 返回值类型错误（期望 Array[Vector2i]）: %s" % provider_id)
		var list: Array = list_val
		for j in range(list.size()):
			var v = list[j]
			if not (v is Vector2i):
				return Result.failure("RangeOriginRegistry: provider[%s] positions[%d] 类型错误（期望 Vector2i）" % [provider_id, j])
			var pos: Vector2i = v
			if out_set.has(pos):
				continue
			out_set[pos] = true
			out.append(pos)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	return Result.success(out).with_warnings(warnings)

