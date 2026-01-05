class_name DinnertimeDemandRegistry
extends RefCounted

# DinnertimeDemandRegistry：模块可插拔地为“每个房屋”提供替代需求方案（例如：寿司/面条/泡菜）。
#
# provider 签名：
#   func (state: GameState, house_id: String, house: Dictionary, base_required: Dictionary) -> Array[Dictionary]
#
# variant 结构：
#   {
#     "id": String,
#     "rank": int,            # 越小越优先
#     "required": Dictionary, # product_id -> count（int）
#   }

static var _providers: Array[Dictionary] = [] # [{id, priority, callback, source, seq}]
static var _loaded: bool = false
static var _seq: int = 0

static func reset() -> void:
	_providers = []
	_loaded = true
	_seq = 0

static func is_loaded() -> bool:
	return _loaded

static func configure_from_ruleset(ruleset) -> Result:
	if not _loaded:
		return Result.failure("DinnertimeDemandRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.dinnertime_demand_providers is Array):
		return Result.failure("DinnertimeDemandRegistry.configure_from_ruleset: ruleset.dinnertime_demand_providers 类型错误（期望 Array）")

	var seen := {}
	_providers = []
	_seq = 0

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

		_providers.append({
			"id": provider_id,
			"priority": priority,
			"callback": cb,
			"source": str(item.get("source", "")),
			"seq": _seq,
		})
		_seq += 1

	_providers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: int = int(a.get("priority", 100))
		var bp: int = int(b.get("priority", 100))
		if ap != bp:
			return ap < bp
		return int(a.get("seq", 0)) < int(b.get("seq", 0))
	)

	return Result.success()

static func get_variants(state: GameState, house_id: String, house: Dictionary, base_required: Dictionary) -> Result:
	if not _loaded:
		return Result.failure("DinnertimeDemandRegistry 未初始化：请先调用 reset()")
	if state == null:
		return Result.failure("DinnertimeDemandRegistry.get_variants: state 为空")
	if house_id.is_empty():
		return Result.failure("DinnertimeDemandRegistry.get_variants: house_id 不能为空")
	if house == null or not (house is Dictionary):
		return Result.failure("DinnertimeDemandRegistry.get_variants: house 类型错误（期望 Dictionary）")
	if base_required == null or not (base_required is Dictionary):
		return Result.failure("DinnertimeDemandRegistry.get_variants: base_required 类型错误（期望 Dictionary）")

	var out: Array[Dictionary] = []
	var seq_local := 0

	for i in range(_providers.size()):
		var p_val = _providers[i]
		if not (p_val is Dictionary):
			return Result.failure("DinnertimeDemandRegistry: provider 类型错误（期望 Dictionary）")
		var p: Dictionary = p_val

		var cb_val = p.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("DinnertimeDemandRegistry: provider.callback 类型错误（期望 Callable）")
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("DinnertimeDemandRegistry: provider.callback 无效")

		var variants_val = cb.call(state, house_id, house, base_required)
		if variants_val == null:
			continue
		if not (variants_val is Array):
			return Result.failure("DinnertimeDemandRegistry: provider 返回类型错误（期望 Array）")
		var variants_any: Array = variants_val
		for j in range(variants_any.size()):
			var v_val = variants_any[j]
			if not (v_val is Dictionary):
				return Result.failure("DinnertimeDemandRegistry: provider variants[%d] 类型错误（期望 Dictionary）" % j)
			var v: Dictionary = v_val

			var vid_val = v.get("id", null)
			if not (vid_val is String):
				return Result.failure("DinnertimeDemandRegistry: variant.id 缺失或类型错误（期望 String）")
			var vid: String = str(vid_val)
			if vid.is_empty():
				return Result.failure("DinnertimeDemandRegistry: variant.id 不能为空")

			var rank_val = v.get("rank", null)
			if not (rank_val is int):
				return Result.failure("DinnertimeDemandRegistry: variant.rank 缺失或类型错误（期望 int）: %s" % vid)
			var rank: int = int(rank_val)

			var req_val = v.get("required", null)
			if not (req_val is Dictionary):
				return Result.failure("DinnertimeDemandRegistry: variant.required 缺失或类型错误（期望 Dictionary）: %s" % vid)
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

	return Result.success(out)

