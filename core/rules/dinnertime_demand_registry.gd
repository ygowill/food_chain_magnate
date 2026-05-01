class_name DinnertimeDemandRegistry
extends RefCounted

# DinnertimeDemandRegistry：模块可插拔地为“每个房屋”提供替代需求方案（例如：寿司/面条/泡菜）。
#
# provider 签名（推荐）：
#   func (state: GameState, house_id: String, house: Dictionary, base_required: Dictionary) -> Result
#
# provider 输出（Result.value）：
#   - null：不提供额外方案
#   - Array[Dictionary]：variant 列表
#
# variant 结构：
#   {
#     "id": String,
#     "rank": int,            # 越小越优先
#     "required": Dictionary, # product_id -> count（int）
#   }

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
	target.dinnertime_demand_providers = []
	target.dinnertime_demand_loaded = true

static func is_loaded() -> bool:
	return bool(_get_bundle().dinnertime_demand_loaded)

static func get_provider_ids() -> Array[String]:
	if not is_loaded():
		return []
	var ids: Array[String] = []
	for item_val in _get_bundle().dinnertime_demand_providers:
		if item_val is Dictionary:
			var provider_id := str((item_val as Dictionary).get("id", "")).strip_edges()
			if not provider_id.is_empty():
				ids.append(provider_id)
	return ids

static func configure_from_ruleset(ruleset, bundle = null) -> Result:
	if not is_loaded() and bundle == null:
		return Result.failure("DinnertimeDemandRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.dinnertime_demand_providers is Array):
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset.dinnertime_demand_providers 类型错误（期望 Array）")

	var seen := {}
	var target = _resolve_bundle(bundle)
	target.dinnertime_demand_providers = []
	target.dinnertime_demand_loaded = true
	var seq: int = 0

	for i in range(ruleset.dinnertime_demand_providers.size()):
		var item_val = ruleset.dinnertime_demand_providers[i]
		if not (item_val is Dictionary):
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val)
		if provider_id.is_empty():
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d].id 不能为空" % i)
		if seen.has(provider_id):
			return Result.failure("DinnertimeDemandRegistry: provider 重复注册: %s" % provider_id)
		seen[provider_id] = true

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d].callback 无效" % i)

		var prio_val = item.get("priority", 100)
		if not (prio_val is int):
			return Result.failure("DinnertimeDemandRegistry: dinnertime_demand_providers[%d].priority 类型错误（期望 int）" % i)
		var priority: int = int(prio_val)

		target.dinnertime_demand_providers.append({
			"id": provider_id,
			"priority": priority,
			"callback": cb,
			"source": str(item.get("source", "")),
			"seq": seq,
		})
		seq += 1

	target.dinnertime_demand_providers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: int = int(a.get("priority", 100))
		var bp: int = int(b.get("priority", 100))
		if ap != bp:
			return ap < bp
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)

	return Result.success(target.dinnertime_demand_providers.size())

static func get_variants(state: GameState, house_id: String, house: Dictionary, base_required: Dictionary) -> Result:
	if not is_loaded():
		return Result.failure("DinnertimeDemandRegistry 未初始化：请先调用 reset()")
	if state == null:
		return Result.failure("DinnertimeDemandRegistry.get_variants: state 为空")
	if house_id.is_empty():
		return Result.failure("DinnertimeDemandRegistry.get_variants: house_id 不能为空")
	if house == null or not (house is Dictionary):
		return Result.failure("DinnertimeDemandRegistry.get_variants: house 类型错误（期望 Dictionary）")
	if base_required == null or not (base_required is Dictionary):
		return Result.failure("DinnertimeDemandRegistry.get_variants: base_required 类型错误（期望 Dictionary）")

	var all_warnings: Array[String] = []
	var out: Array[Dictionary] = []
	var seq_local := 0

	for i in range(_get_bundle().dinnertime_demand_providers.size()):
		var p_val = _get_bundle().dinnertime_demand_providers[i]
		if not (p_val is Dictionary):
			return Result.failure("DinnertimeDemandRegistry: provider 类型错误（期望 Dictionary）")
		var p: Dictionary = p_val
		var provider_id: String = str(p.get("id", ""))

		var cb_val = p.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("DinnertimeDemandRegistry: provider.callback 类型错误（期望 Callable）")
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("DinnertimeDemandRegistry: provider.callback 无效")

		var r = cb.call(state, house_id, house, base_required)
		if not (r is Result):
			return Result.failure("DinnertimeDemandRegistry: provider 返回类型错误（期望 Result）: %s" % provider_id)

		var variants_any: Array = []
		var rr: Result = r
		if not rr.ok:
			return Result.failure("DinnertimeDemandRegistry: provider 失败: %s: %s" % [provider_id, rr.error])
		all_warnings.append_array(rr.warnings)
		if rr.value == null:
			continue
		if not (rr.value is Array):
			return Result.failure("DinnertimeDemandRegistry: provider Result.value 类型错误（期望 Array）: %s" % provider_id)
		variants_any = rr.value

		for j in range(variants_any.size()):
			var v_val = variants_any[j]
			if not (v_val is Dictionary):
				return Result.failure("DinnertimeDemandRegistry: provider variants[%d] 类型错误（期望 Dictionary）: %s" % [j, provider_id])
			var v: Dictionary = v_val

			var vid_val = v.get("id", null)
			if not (vid_val is String):
				return Result.failure("DinnertimeDemandRegistry: variant.id 缺失或类型错误（期望 String）: %s" % provider_id)
			var vid: String = str(vid_val)
			if vid.is_empty():
				return Result.failure("DinnertimeDemandRegistry: variant.id 不能为空: %s" % provider_id)

			var rank_val = v.get("rank", null)
			if not (rank_val is int):
				return Result.failure("DinnertimeDemandRegistry: variant.rank 缺失或类型错误（期望 int）: %s (%s)" % [vid, provider_id])
			var rank: int = int(rank_val)

			var req_val = v.get("required", null)
			if not (req_val is Dictionary):
				return Result.failure("DinnertimeDemandRegistry: variant.required 缺失或类型错误（期望 Dictionary）: %s (%s)" % [vid, provider_id])
			var req: Dictionary = req_val

			out.append({
				"id": vid,
				"rank": rank,
				"required": req.duplicate(true),
				"seq": seq_local,
			})
			seq_local += 1

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar: int = int(a.get("rank", 0))
		var br: int = int(b.get("rank", 0))
		if ar != br:
			return ar < br
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)

	return Result.success(out).with_warnings(all_warnings)
