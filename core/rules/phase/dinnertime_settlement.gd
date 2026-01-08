# Dinnertime 结算（从 PhaseManager 抽离）
# 目标：聚合 Dinnertime 阶段“选店/售卖/里程碑/银行破产”逻辑，便于测试与复用。
class_name DinnertimeSettlement
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const DinnertimeDemandRegistryClass = preload("res://core/rules/dinnertime_demand_registry.gd")
const DinnertimeRoutePurchaseRegistryClass = preload("res://core/rules/dinnertime_route_purchase_registry.gd")
const DinnertimeEventsClass = preload("res://core/rules/phase/dinnertime/dinnertime_events.gd")
const DinnertimeInventoryClass = preload("res://core/rules/phase/dinnertime/dinnertime_inventory.gd")
const DinnertimeEffectsClass = preload("res://core/rules/phase/dinnertime/dinnertime_effects.gd")
const DinnertimeSelectionClass = preload("res://core/rules/phase/dinnertime/dinnertime_selection.gd")

const EFFECT_SEG_DINNERTIME_TIEBREAK := ":dinnertime:tiebreaker:"
const EFFECT_SEG_DINNERTIME_TIPS := ":dinnertime:tips:"
const EFFECT_SEG_DINNERTIME_INCOME_BONUS := ":dinnertime:income_bonus:"
const EFFECT_SEG_DINNERTIME_DISTANCE_DELTA := ":dinnertime:distance_delta:"
const EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS := ":dinnertime:sale_house_bonus:"

static func apply(state: GameState, phase_manager = null) -> Result:
	# 对齐 docs/rules.md：
	# 1) 按房屋编号升序处理有需求的房屋
	# 2) 候选餐厅：道路连通 + 库存满足全部需求
	# 3) 选择：最小（单价 + 距离），平局：女服务员数量多者胜，再平：回合顺序靠前者胜
	# 4) 结算：扣库存 + 入账；花园翻倍“单价部分”；奖励不翻倍；最终收入下限 0
	# 5) 女服务员：所有房屋处理完后，每位在岗女服务员赚取 3/5（里程碑）
	# 6) CFO：拥有在岗 CFO（或“拥有$100”里程碑）者，本回合收入（含女服务员）+50% 向上取整
	if state == null:
		return Result.failure("DinnertimeSettlement: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("DinnertimeSettlement: state.map 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("DinnertimeSettlement: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("DinnertimeSettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.bank is Dictionary):
		return Result.failure("DinnertimeSettlement: state.bank 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	var effect_registry = null
	if phase_manager != null and phase_manager.has_method("get_effect_registry"):
		effect_registry = phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")

	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("晚餐结算失败：RoadGraph 未初始化")

	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("晚餐结算失败：state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]

	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("晚餐结算失败：state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]

	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("晚餐结算失败：state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]

	var income_sales: Array[int] = []
	var income_tips: Array[int] = []
	var income_cfo: Array[int] = []
	var income_sale_house_bonus: Array[int] = []
	var total_income_before_cfo: Array[int] = []
	var total_income: Array[int] = []
	for _i in range(state.players.size()):
		income_sales.append(0)
		income_tips.append(0)
		income_cfo.append(0)
		income_sale_house_bonus.append(0)
		total_income_before_cfo.append(0)
		total_income.append(0)

	var sales: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var sold_marketed_demand_events: Array[Dictionary] = []

	var ordered_house_ids: Array[String] = MapRuntimeClass.get_sorted_house_ids(state)
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

		var required_read := _build_demand_requirements(demands)
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

			var pick := _pick_winner_for_required(
				state,
				effect_registry,
				road_graph,
				grid_size,
				restaurants,
				house_id,
				house,
				req,
				warnings
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

		assert(winner.has("owner") and winner["owner"] is int, "内部错误: winner.owner 缺失或类型错误（期望 int）")
		assert(winner.has("breakdown") and winner["breakdown"] is Dictionary, "内部错误: winner.breakdown 缺失或类型错误（期望 Dictionary）")
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
		_append_sold_marketed_demand_events(sold_marketed_demand_events, demands, house_id, house, owner_id)

		var inv_apply := _apply_inventory_delta(state, owner_id, required)
		if not inv_apply.ok:
			return inv_apply

		# 可插拔：每次“成功向一个房屋售卖”后的额外奖金（例如薯条厨师：每个在岗薯条厨师 +$10）
		var has_food_read := _required_has_non_drink_food(required)
		if not has_food_read.ok:
			return has_food_read
		var house_bonus_ctx := {
			"bonus": 0,
			"house_id": house_id,
			"restaurant_id": str(winner["restaurant_id"]),
			"has_non_drink_food": bool(has_food_read.value),
			"unit_price": int(breakdown.get("unit_price", 0)),
			"quantity": int(breakdown.get("quantity", 0)),
		}
		var bonus_eff := _apply_employee_effects_by_segment(state, owner_id, effect_registry, EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		bonus_eff = _apply_milestone_effects_by_segment(state, owner_id, effect_registry, EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		bonus_eff = _apply_global_effects_by_segment(state, owner_id, effect_registry, EFFECT_SEG_DINNERTIME_SALE_HOUSE_BONUS, house_bonus_ctx)
		if not bonus_eff.ok:
			return bonus_eff
		warnings.append_array(bonus_eff.warnings)
		var house_bonus_val = house_bonus_ctx.get("bonus", 0)
		if not (house_bonus_val is int):
			return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus 类型错误（期望 int）")
		var house_bonus: int = int(house_bonus_val)
		if house_bonus < 0:
			return Result.failure("晚餐结算失败：sale_house_bonus ctx.bonus 不能为负数: %d" % house_bonus)

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
			"revenue": revenue,
		})

	# 写回 houses（需求清理）
	state.map["houses"] = houses

	# 4) tips（可插拔）
	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)

		var tips_amount := 0
		var ctx := {
			"tips": 0,
			"use_employee_triggered": false,
		}
		var eff := _apply_employee_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_TIPS, ctx)
		if not eff.ok:
			return eff
		warnings.append_array(eff.warnings)
		var tips_val = ctx.get("tips", 0)
		if not (tips_val is int):
			return Result.failure("晚餐结算失败：tips ctx.tips 类型错误（期望 int）")
		tips_amount = int(tips_val)
		if tips_amount <= 0:
			continue

		var tips_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, tips_amount, "女服务员收入")
		if not tips_result.ok:
			return Result.failure("女服务员收入支付失败：玩家 %d：%s" % [player_id, tips_result.error])
		warnings.append_array(tips_result.warnings)

		income_tips[player_id] += tips_amount
		total_income_before_cfo[player_id] += tips_amount

	# 5) income bonus（可插拔；默认 CFO 加成 +50% 向上取整）
	for player_id in range(state.players.size()):
		var base_gain: int = total_income_before_cfo[player_id]
		if base_gain <= 0:
			continue

		var extra := 0
		var ctx := {
			"base_gain": base_gain,
			"extra": 0,
			"once": {},
		}
		var eff_emp := _apply_employee_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_INCOME_BONUS, ctx)
		if not eff_emp.ok:
			return eff_emp
		warnings.append_array(eff_emp.warnings)
		var eff_ms := _apply_milestone_effects_by_segment(state, player_id, effect_registry, EFFECT_SEG_DINNERTIME_INCOME_BONUS, ctx)
		if not eff_ms.ok:
			return eff_ms
		warnings.append_array(eff_ms.warnings)

		var extra_val = ctx.get("extra", 0)
		if not (extra_val is int):
			return Result.failure("晚餐结算失败：income_bonus ctx.extra 类型错误（期望 int）")
		extra = int(extra_val)
		if extra <= 0:
			continue

		var cfo_result := BankruptcyRulesClass.pay_bank_to_player(state, player_id, extra, "CFO 加成")
		if not cfo_result.ok:
			return Result.failure("CFO 加成支付失败：玩家 %d：%s" % [player_id, cfo_result.error])
		warnings.append_array(cfo_result.warnings)
		income_cfo[player_id] += extra

	for player_id in range(state.players.size()):
		total_income[player_id] = total_income_before_cfo[player_id] + income_cfo[player_id]

		state.round_state["dinnertime"] = {
			"sales": sales,
			"skipped": skipped,
			"income_sales": income_sales,
			"income_sale_house_bonus": income_sale_house_bonus,
			"income_tips": income_tips,
			"income_cfo_bonus": income_cfo,
			"total_income": total_income,
			"sold_marketed_demand_events": sold_marketed_demand_events,
		}

	return Result.success().with_warnings(warnings)

static func _pick_winner_for_required(
	state: GameState,
	effect_registry,
	road_graph,
	grid_size: Vector2i,
	restaurants: Dictionary,
	house_id: String,
	house: Dictionary,
	required: Dictionary,
	warnings: Array[String]
) -> Result:
	return DinnertimeSelectionClass.pick_winner_for_required(
		state,
		effect_registry,
		road_graph,
		grid_size,
		restaurants,
		house_id,
		house,
		required,
		warnings,
		EFFECT_SEG_DINNERTIME_DISTANCE_DELTA,
		EFFECT_SEG_DINNERTIME_TIEBREAK
	)

static func _append_sold_marketed_demand_events(
	out_events: Array[Dictionary],
	demands: Array,
	house_id: String,
	house: Dictionary,
	winner_owner: int
) -> void:
	DinnertimeEventsClass.append_sold_marketed_demand_events(out_events, demands, house_id, house, winner_owner)

static func _build_demand_requirements(demands: Array) -> Result:
	return DinnertimeInventoryClass.build_demand_requirements(demands)

static func _required_has_non_drink_food(required: Dictionary) -> Result:
	return DinnertimeInventoryClass.required_has_non_drink_food(required)

static func _apply_inventory_delta(state: GameState, player_id: int, required: Dictionary) -> Result:
	return DinnertimeInventoryClass.apply_inventory_delta(state, player_id, required)

static func _apply_employee_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_employee_effects_by_segment(state, player_id, effect_registry, segment, ctx)

static func _apply_milestone_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, player_id, effect_registry, segment, ctx)

static func _apply_global_effects_by_segment(
	state: GameState,
	player_id_for_ctx: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	return DinnertimeEffectsClass.apply_global_effects_by_segment(state, player_id_for_ctx, effect_registry, segment, ctx)

static func _get_waitress_tips_override_from_milestones(milestones: Array) -> Result:
	var found := false
	var best := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("晚餐结算失败：milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("晚餐结算失败：milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("晚餐结算失败：里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("晚餐结算失败：%s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("晚餐结算失败：%s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "waitress_tips":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("晚餐结算失败：%s" % v_read.error)
			found = true
			best = maxi(best, int(v_read.value))

	return Result.success({
		"found": found,
		"value": best,
	})

static func _parse_non_negative_int_value(value, path: String) -> Result:
	if value is int:
		if int(value) < 0:
			return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			var i: int = int(f)
			if i < 0:
				return Result.failure("%s 必须 >= 0，实际: %d" % [path, i])
			return Result.success(i)
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为非负整数" % path)
