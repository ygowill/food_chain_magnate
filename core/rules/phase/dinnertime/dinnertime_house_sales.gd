extends RefCounted

const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const DinnertimeDemandRegistryClass = preload("res://core/rules/dinnertime_demand_registry.gd")
const DinnertimeRoutePurchaseRegistryClass = preload("res://core/rules/dinnertime_route_purchase_registry.gd")
const DinnertimeEventsClass = preload("res://core/rules/phase/dinnertime/dinnertime_events.gd")
const DinnertimeInventoryClass = preload("res://core/rules/phase/dinnertime/dinnertime_inventory.gd")
const DinnertimeEffectsClass = preload("res://core/rules/phase/dinnertime/dinnertime_effects.gd")
const DinnertimeSelectionClass = preload("res://core/rules/phase/dinnertime/dinnertime_selection.gd")

static func apply(
	state: GameState,
	effect_registry,
	road_graph,
	grid_size: Vector2i,
	houses: Dictionary,
	restaurants: Dictionary,
	distance_delta_segment: String,
	tiebreak_segment: String,
	sale_house_bonus_segment: String
) -> Result:
	if state == null:
		return Result.failure("晚餐结算失败：state 为空")
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if road_graph == null:
		return Result.failure("晚餐结算失败：RoadGraph 未初始化")
	if houses == null or not (houses is Dictionary):
		return Result.failure("晚餐结算失败：houses 类型错误（期望 Dictionary）")
	if restaurants == null or not (restaurants is Dictionary):
		return Result.failure("晚餐结算失败：restaurants 类型错误（期望 Dictionary）")
	if distance_delta_segment.is_empty() or tiebreak_segment.is_empty() or sale_house_bonus_segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")

	var player_count: int = state.players.size()
	var income_sales: Array[int] = []
	var income_sale_house_bonus: Array[int] = []
	var total_income_before_cfo: Array[int] = []
	for _i in range(player_count):
		income_sales.append(0)
		income_sale_house_bonus.append(0)
		total_income_before_cfo.append(0)

	var sales: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var sold_marketed_demand_events: Array[Dictionary] = []

	var warnings: Array[String] = []

	var ordered_read := StructuresClass.get_sorted_house_ids(state)
	if not ordered_read.ok:
		return Result.failure("晚餐结算失败：%s" % str(ordered_read.error))
	var ordered_house_ids: Array[String] = ordered_read.value
	for house_id in ordered_house_ids:
		if not houses.has(house_id):
			continue
		var house_val = houses[house_id]
		if not (house_val is Dictionary):
			return Result.failure("晚餐结算失败：house 类型错误: houses[%s]（期望 Dictionary）" % str(house_id))
		var house: Dictionary = house_val

		var demands_val = house.get("demands", null)
		if demands_val == null:
			continue
		if not (demands_val is Array):
			return Result.failure("晚餐结算失败：house.demands 类型错误（期望 Array）")
		var demands: Array = demands_val
		if demands.is_empty():
			continue

		var required_read := DinnertimeInventoryClass.build_demand_requirements(demands)
		if not required_read.ok:
			return required_read
		var base_required: Dictionary = required_read.value
		if base_required.is_empty():
			continue

		if not DinnertimeDemandRegistryClass.is_loaded():
			return Result.failure("晚餐结算失败：DinnertimeDemandRegistry 未初始化")

		var variants_read := DinnertimeDemandRegistryClass.get_variants(state, house_id, house, base_required)
		if not variants_read.ok:
			return Result.failure("晚餐结算失败：%s" % variants_read.error)
		warnings.append_array(variants_read.warnings)
		var variants: Array[Dictionary] = variants_read.value
		variants.append({
			"id": "base",
			"rank": 50,
			"required": base_required.duplicate(true),
			"seq": 1000000,
		})
		variants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ar: int = int(a.get("rank", 0))
			var br: int = int(b.get("rank", 0))
			if ar != br:
				return ar < br
			return int(a.get("seq", 0)) < int(b.get("seq", 0))
		)

		var winner: Dictionary = {}
		var selected_variant_id := ""
		var required: Dictionary = {}
		for v_val in variants:
			if not (v_val is Dictionary):
				return Result.failure("晚餐结算失败：demand variant 类型错误（期望 Dictionary）")
			var v: Dictionary = v_val
			var vid_val = v.get("id", null)
			var req_val = v.get("required", null)
			if not (vid_val is String) or not (req_val is Dictionary):
				return Result.failure("晚餐结算失败：demand variant 结构错误")
			var vid: String = str(vid_val)
			var req: Dictionary = Dictionary(req_val)
			if req.is_empty():
				continue

			var pick := DinnertimeSelectionClass.pick_winner_for_required(
				state,
				effect_registry,
				road_graph,
				grid_size,
				restaurants,
				house_id,
				house,
				req,
				warnings,
				distance_delta_segment,
				tiebreak_segment
			)
			if not pick.ok:
				return pick
			var w_val = pick.value
			if not (w_val is Dictionary):
				return Result.failure("晚餐结算失败：内部错误（winner 类型错误）")
			var w: Dictionary = w_val
			if w.is_empty():
				continue
			winner = w
			selected_variant_id = vid
			required = req
			break

		if winner.is_empty():
			if not house.has("house_number"):
				return Result.failure("晚餐结算失败：houses[%s].house_number 缺失" % house_id)
			var house_number = house["house_number"]
			if not (house_number is int or house_number is float or house_number is String):
				return Result.failure("晚餐结算失败：houses[%s].house_number 类型错误（期望 int/float/String）" % house_id)
			skipped.append({
				"house_id": house_id,
				"house_number": house_number,
				"demands": demands.size(),
			})
			continue

		if not (winner.has("owner") and winner["owner"] is int):
			return Result.failure("晚餐结算失败：内部错误（winner.owner 缺失或类型错误（期望 int））")
		if not (winner.has("breakdown") and winner["breakdown"] is Dictionary):
			return Result.failure("晚餐结算失败：内部错误（winner.breakdown 缺失或类型错误（期望 Dictionary））")
		var owner_id: int = int(winner["owner"])
		var breakdown: Dictionary = winner["breakdown"]
		var revenue: int = int(breakdown["revenue"])

		# 可插拔：路上购买/结算（例如 Coffee：沿路路过餐厅/咖啡店买咖啡）
		var route_purchases: Array = []
		var route_income_by_player: Dictionary = {}
		if not DinnertimeRoutePurchaseRegistryClass.is_loaded():
			return Result.failure("晚餐结算失败：DinnertimeRoutePurchaseRegistry 未初始化")
		var route_apply := DinnertimeRoutePurchaseRegistryClass.apply_for_house(state, {
			"house_id": house_id,
			"house": house.duplicate(true),
			"required": required.duplicate(true),
			"winner_restaurant_id": str(winner.get("restaurant_id", "")),
			"winner_owner": owner_id,
			"road_graph": road_graph,
		})
		if not route_apply.ok:
			return Result.failure("晚餐结算失败：route purchase 失败: %s" % route_apply.error)
		warnings.append_array(route_apply.warnings)
		if route_apply.value is Dictionary:
			var route_result: Dictionary = route_apply.value as Dictionary
			var purchases_val = route_result.get("purchases", [])
			if purchases_val is Array:
				route_purchases = purchases_val as Array
			var income_val = route_result.get("income_by_player", {})
			if income_val is Dictionary:
				route_income_by_player = income_val as Dictionary

		for pid_val in route_income_by_player.keys():
			var pid: int = int(pid_val)
			var amt_val = route_income_by_player.get(pid_val, 0)
			if amt_val is int:
				var amt: int = int(amt_val)
				if amt > 0 and pid >= 0 and pid < state.players.size():
					income_sales[pid] += amt
					total_income_before_cfo[pid] += amt

		# 记录“他人卖出你营销产生的需求”事件（供模块扩展在晚餐结算后处理）
		var evt_append := DinnertimeEventsClass.append_sold_marketed_demand_events(
			sold_marketed_demand_events,
			demands,
			house_id,
			house,
			owner_id
		)
		if not evt_append.ok:
			return evt_append

		var inv_apply := DinnertimeInventoryClass.apply_inventory_delta(state, owner_id, required)
		if not inv_apply.ok:
			return inv_apply

		# 可插拔：每次“成功向一个房屋售卖”后的额外奖金（例如薯条厨师：每个在岗薯条厨师 +$10）
		var has_food_read := DinnertimeInventoryClass.required_has_non_drink_food(required)
		if not has_food_read.ok:
			return has_food_read
		var house_bonus_ctx := {
			"bonus": 0,
			"bonus_breakdown": {},
			"house_id": house_id,
			"restaurant_id": str(winner["restaurant_id"]),
			"has_non_drink_food": bool(has_food_read.value),
			"unit_price": int(breakdown.get("unit_price", 0)),
			"quantity": int(breakdown.get("quantity", 0)),
		}
		var bonus_eff := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, owner_id, effect_registry, sale_house_bonus_segment, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		bonus_eff = DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, owner_id, effect_registry, sale_house_bonus_segment, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		bonus_eff = DinnertimeEffectsClass.apply_global_effects_by_segment(state, owner_id, effect_registry, sale_house_bonus_segment, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		var house_bonus_val = house_bonus_ctx.get("bonus", 0)
		if not (house_bonus_val is int):
			return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus 类型错误（期望 int）")
		var house_bonus: int = int(house_bonus_val)
		if house_bonus < 0:
			return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus 不能为负数: %d" % house_bonus)

		var house_bonus_breakdown: Dictionary = {}
		var breakdown_val = house_bonus_ctx.get("bonus_breakdown", null)
		if breakdown_val != null:
			if not (breakdown_val is Dictionary):
				return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus_breakdown 类型错误（期望 Dictionary）")
			for k in (breakdown_val as Dictionary).keys():
				if not (k is String):
					return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus_breakdown key 类型错误（期望 String）")
				var key: String = str(k).strip_edges()
				if key.is_empty():
					continue
				var v = (breakdown_val as Dictionary).get(k, 0)
				if not (v is int):
					return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus_breakdown[%s] 类型错误（期望 int）" % key)
				var amt: int = int(v)
				if amt != 0:
					house_bonus_breakdown[key] = int(house_bonus_breakdown.get(key, 0)) + amt

		if revenue > 0:
			var pay_result := BankruptcyRulesClass.pay_bank_to_player(state, owner_id, revenue, "晚餐收入")
			if not pay_result.ok:
				return Result.failure("晚餐收入支付失败：玩家 %d：%s" % [owner_id, pay_result.error])
			warnings.append_array(pay_result.warnings)
			income_sales[owner_id] += revenue
			total_income_before_cfo[owner_id] += revenue

		if house_bonus > 0:
			var bonus_result := BankruptcyRulesClass.pay_bank_to_player(state, owner_id, house_bonus, "晚餐额外奖金")
			if not bonus_result.ok:
				return Result.failure("晚餐额外奖金支付失败：玩家 %d：%s" % [owner_id, bonus_result.error])
			warnings.append_array(bonus_result.warnings)
			income_sale_house_bonus[owner_id] += house_bonus
			total_income_before_cfo[owner_id] += house_bonus

		# 清空需求（已被完整满足）
		house["demands"] = []
		houses[house_id] = house

		sales.append({
			"house_id": house_id,
			"house_number": house["house_number"],
			"winner_owner": owner_id,
			"winner_restaurant_id": str(winner["restaurant_id"]),
			"demand_variant_id": selected_variant_id,
			"required": required.duplicate(true),
			"route_purchases": route_purchases.duplicate(true),
			"score": int(winner["score"]),
			"distance": int(winner["distance"]),
			"unit_price": int(winner["unit_price"]),
			"decision_unit_price": int(winner["decision_unit_price"]),
			"quantity": int(breakdown["quantity"]),
			"has_garden": bool(breakdown["has_garden"]),
			"price_part": int(breakdown["price_part"]),
			"bonus": int(breakdown["bonus"]),
			"house_bonus": house_bonus,
			"house_bonus_breakdown": house_bonus_breakdown.duplicate(true),
			"revenue": revenue,
		})

	# 写回 houses（需求清理）
	state.map["houses"] = houses

	return Result.success({
		"income_sales": income_sales,
		"income_sale_house_bonus": income_sale_house_bonus,
		"total_income_before_cfo": total_income_before_cfo,
		"sales": sales,
		"skipped": skipped,
		"sold_marketed_demand_events": sold_marketed_demand_events,
	}).with_warnings(warnings)
