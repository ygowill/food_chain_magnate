class_name DinnertimeRoutePurchaseRegistry
extends RefCounted

# DinnertimeRoutePurchaseRegistry：模块可插拔地为“每个房屋去往赢家餐厅的路上”增加额外购买/结算逻辑（例如：Coffee）。
#
# provider 签名：
#   func (state: GameState, ctx: Dictionary) -> Result
#
# ctx 输入（由 DinnertimeSettlement 组装）：
#   {
#     "house_id": String,
#     "house": Dictionary,
#     "required": Dictionary,            # 本次房屋需求（赢家餐厅满足的那一套）
#     "winner_restaurant_id": String,
#     "winner_owner": int,
#     "road_graph": RoadGraph,
#   }
#
# provider 输出（Result.value，建议结构；非强制但必须是 Dictionary）：
#   {
#     "purchases": Array[Dictionary],    # 可选：用于 round_state 记录（每项必须是 Dictionary）
#     "income_by_player": Dictionary,    # 可选：int player_id -> int income_from_bank（player_id 必须是 int 且在玩家范围内；income 必须是 int 且 >= 0）
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
		return Result.failure("DinnertimeRoutePurchaseRegistry 未初始化：请先调用 reset()")
	if ruleset == null:
		return Result.failure("DinnertimeRoutePurchaseRegistry.configure_from_ruleset: ruleset 为空")
	if not (ruleset is RulesetV2):
		return Result.failure("DinnertimeRoutePurchaseRegistry.configure_from_ruleset: ruleset 类型错误（期望 RulesetV2）")
	if not (ruleset.dinnertime_route_purchase_providers is Array):
		return Result.failure("DinnertimeRoutePurchaseRegistry.configure_from_ruleset: ruleset.dinnertime_route_purchase_providers 类型错误（期望 Array）")

	var seen := {}
	_providers = []
	_seq = 0

	for i in range(ruleset.dinnertime_route_purchase_providers.size()):
		var item_val = ruleset.dinnertime_route_purchase_providers[i]
		if not (item_val is Dictionary):
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val

		var id_val = item.get("id", null)
		if not (id_val is String):
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d].id 类型错误（期望 String）" % i)
		var provider_id: String = str(id_val)
		if provider_id.is_empty():
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d].id 不能为空" % i)
		if seen.has(provider_id):
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider 重复注册: %s" % provider_id)
		seen[provider_id] = true

		var cb_val = item.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d].callback 类型错误（期望 Callable）" % i)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d].callback 无效" % i)

		var prio_val = item.get("priority", 100)
		if not (prio_val is int):
			return Result.failure("DinnertimeRoutePurchaseRegistry: dinnertime_route_purchase_providers[%d].priority 类型错误（期望 int）" % i)
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

static func apply_for_house(state: GameState, ctx: Dictionary) -> Result:
	if not _loaded:
		return Result.failure("DinnertimeRoutePurchaseRegistry 未初始化：请先调用 reset()")
	if state == null:
		return Result.failure("DinnertimeRoutePurchaseRegistry.apply_for_house: state 为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("DinnertimeRoutePurchaseRegistry.apply_for_house: ctx 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("DinnertimeRoutePurchaseRegistry.apply_for_house: state.players 类型错误（期望 Array）")

	var all_warnings: Array[String] = []
	var merged_purchases: Array[Dictionary] = []
	var income_by_player: Dictionary = {}

	for i in range(_providers.size()):
		var p_val = _providers[i]
		if not (p_val is Dictionary):
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider 类型错误（期望 Dictionary）")
		var p: Dictionary = p_val
		var provider_id: String = str(p.get("id", ""))

		var cb_val = p.get("callback", Callable())
		if not (cb_val is Callable):
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider.callback 类型错误（期望 Callable）: %s" % provider_id)
		var cb: Callable = cb_val
		if not cb.is_valid():
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider.callback 无效: %s" % provider_id)

		var r = cb.call(state, ctx.duplicate(true))
		if r == null or not (r is Result):
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider 返回值类型错误（期望 Result）: %s" % provider_id)
		var rr: Result = r
		if not rr.ok:
			return rr
		all_warnings.append_array(rr.warnings)

		var out_val = rr.value
		if out_val == null:
			continue
		if not (out_val is Dictionary):
			return Result.failure("DinnertimeRoutePurchaseRegistry: provider Result.value 类型错误（期望 Dictionary）: %s" % provider_id)
		var out: Dictionary = out_val

		var purchases_val = out.get("purchases", null)
		if purchases_val != null:
			if not (purchases_val is Array):
				return Result.failure("DinnertimeRoutePurchaseRegistry: purchases 类型错误（期望 Array）: %s" % provider_id)
			var purchases_any: Array = purchases_val
			for j in range(purchases_any.size()):
				var item = purchases_any[j]
				if not (item is Dictionary):
					return Result.failure("DinnertimeRoutePurchaseRegistry: purchases[%d] 类型错误（期望 Dictionary）: %s" % [j, provider_id])
				merged_purchases.append(item)

		var income_val = out.get("income_by_player", null)
		if income_val != null:
			if not (income_val is Dictionary):
				return Result.failure("DinnertimeRoutePurchaseRegistry: income_by_player 类型错误（期望 Dictionary）: %s" % provider_id)
			for k in income_val.keys():
				if not (k is int):
					return Result.failure("DinnertimeRoutePurchaseRegistry: income_by_player key 类型错误（期望 int）: %s: %s" % [provider_id, str(k)])
				var pid: int = int(k)
				if pid < 0 or pid >= state.players.size():
					return Result.failure("DinnertimeRoutePurchaseRegistry: income_by_player player_id 越界: %s: %d" % [provider_id, pid])
				var amt_val = income_val.get(pid, 0)
				if not (amt_val is int):
					return Result.failure("DinnertimeRoutePurchaseRegistry: income_by_player[%d] 类型错误（期望 int）: %s" % [pid, provider_id])
				var amt: int = int(amt_val)
				if amt < 0:
					return Result.failure("DinnertimeRoutePurchaseRegistry: income_by_player[%d] 不能为负数: %s: %d" % [pid, provider_id, amt])
				income_by_player[pid] = int(income_by_player.get(pid, 0)) + amt

	return Result.success({
		"purchases": merged_purchases,
		"income_by_player": income_by_player,
	}).with_warnings(all_warnings)
