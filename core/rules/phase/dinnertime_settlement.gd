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
	var winner: Dictionary = {}
	var tiebreak_cache: Dictionary = {}

	for rest_key in restaurants.keys():
		if not (rest_key is String):
			return Result.failure("晚餐结算失败：restaurants key 类型错误（期望 String）")
		var rest_id: String = str(rest_key)
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			return Result.failure("晚餐结算失败：restaurant 类型错误: restaurants[%s]（期望 Dictionary）" % rest_id)
		var rest: Dictionary = rest_val
		if rest.is_empty():
			continue

		if not rest.has("owner") or not (rest["owner"] is int):
			return Result.failure("晚餐结算失败：restaurants[%s].owner 缺失或类型错误（期望 int）" % rest_id)
		var owner: int = rest["owner"]
		if owner < 0 or owner >= state.players.size():
			return Result.failure("晚餐结算失败：restaurants[%s].owner 越界: %d" % [rest_id, owner])

		var player_val = state.players[owner]
		if not (player_val is Dictionary):
			return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % owner)
		var player: Dictionary = player_val

		var has_inv := _player_has_inventory(player, required)
		if not has_inv.ok:
			return has_inv
		if not bool(has_inv.value):
			continue

		var distance_read := _get_restaurant_to_house_distance(road_graph, state, grid_size, rest_id, rest, house_id, house)
		if not distance_read.ok:
			return distance_read
		var distance_info: Dictionary = distance_read.value
		if distance_info.is_empty():
			continue

		var breakdown_read := PricingPipelineClass.calculate_sale_breakdown(state, owner, house, required)
		if not breakdown_read.ok:
			return Result.failure("晚餐结算失败：PricingPipeline 失败: %s" % breakdown_read.error)
		var breakdown: Dictionary = breakdown_read.value

		assert(breakdown.has("decision_unit_price") and breakdown["decision_unit_price"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 decision_unit_price（期望 int）")
		assert(breakdown.has("unit_price") and breakdown["unit_price"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 unit_price（期望 int）")
		assert(breakdown.has("revenue") and breakdown["revenue"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 revenue（期望 int）")
		assert(breakdown.has("quantity") and breakdown["quantity"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 quantity（期望 int）")
		assert(breakdown.has("has_garden") and breakdown["has_garden"] is bool, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 has_garden（期望 bool）")
		assert(breakdown.has("price_part") and breakdown["price_part"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 price_part（期望 int）")
		assert(breakdown.has("bonus") and breakdown["bonus"] is int, "PricingPipeline.calculate_sale_breakdown: 缺少/错误 bonus（期望 int）")

		assert(distance_info.has("distance") and distance_info["distance"] is int, "内部错误: distance_info.distance 缺失或类型错误（期望 int）")
		assert(distance_info.has("steps") and distance_info["steps"] is int, "内部错误: distance_info.steps 缺失或类型错误（期望 int）")
		assert(distance_info.has("path") and distance_info["path"] is Array, "内部错误: distance_info.path 缺失或类型错误（期望 Array[Vector2i]）")

		var decision_unit_price: int = breakdown["decision_unit_price"]
		var dist: int = distance_info["distance"]

		var dist_ctx := {
			"distance": dist,
			"steps": int(distance_info["steps"]),
			"path": distance_info["path"],
			"house_id": house_id,
			"restaurant_id": rest_id,
			"allow_negative": false,
		}
		var dist_eff := _apply_employee_effects_by_segment(state, owner, effect_registry, EFFECT_SEG_DINNERTIME_DISTANCE_DELTA, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		dist_eff = _apply_milestone_effects_by_segment(state, owner, effect_registry, EFFECT_SEG_DINNERTIME_DISTANCE_DELTA, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		dist_eff = _apply_global_effects_by_segment(state, owner, effect_registry, EFFECT_SEG_DINNERTIME_DISTANCE_DELTA, dist_ctx)
		if not dist_eff.ok:
			return dist_eff
		warnings.append_array(dist_eff.warnings)
		var dist_val = dist_ctx.get("distance", null)
		if not (dist_val is int):
			return Result.failure("晚餐结算失败：distance ctx.distance 类型错误（期望 int）")
		var allow_neg_val = dist_ctx.get("allow_negative", false)
		if not (allow_neg_val is bool):
			return Result.failure("晚餐结算失败：distance ctx.allow_negative 类型错误（期望 bool）")
		var allow_negative: bool = bool(allow_neg_val)
		dist = int(dist_val)
		if dist < 0 and not allow_negative:
			return Result.failure("晚餐结算失败：distance ctx.distance 不能为负数: %d" % dist)

		var score: int = decision_unit_price + dist
		var tiebreak_score := 0
		if tiebreak_cache.has(owner):
			var cached = tiebreak_cache.get(owner, 0)
			if not (cached is int):
				return Result.failure("晚餐结算失败：tiebreak_cache[%d] 类型错误（期望 int）" % owner)
			tiebreak_score = int(cached)
		else:
			var ctx := {
				"score": 0,
				"house_id": house_id,
				"restaurant_id": rest_id,
			}
			var eff := _apply_employee_effects_by_segment(state, owner, effect_registry, EFFECT_SEG_DINNERTIME_TIEBREAK, ctx)
			if not eff.ok:
				return eff
			warnings.append_array(eff.warnings)
			var sc_val = ctx.get("score", 0)
			if not (sc_val is int):
				return Result.failure("晚餐结算失败：tiebreak ctx.score 类型错误（期望 int）")
			tiebreak_score = int(sc_val)
			tiebreak_cache[owner] = tiebreak_score

		var candidate := {
			"restaurant_id": rest_id,
			"owner": owner,
			"score": score,
			"distance": dist,
			"steps": int(distance_info["steps"]),
			"tiebreak_score": int(tiebreak_score),
			"unit_price": int(breakdown["unit_price"]),
			"decision_unit_price": decision_unit_price,
			"breakdown": breakdown,
		}

		if winner.is_empty() or _is_candidate_better(state, candidate, winner):
			winner = candidate

	return Result.success(winner)

static func _append_sold_marketed_demand_events(
	out_events: Array[Dictionary],
	demands: Array,
	house_id: String,
	house: Dictionary,
	winner_owner: int
) -> void:
	assert(out_events != null, "_append_sold_marketed_demand_events: out_events 为空")
	assert(demands != null, "_append_sold_marketed_demand_events: demands 为空")
	assert(not house_id.is_empty(), "_append_sold_marketed_demand_events: house_id 不能为空")
	assert(house != null, "_append_sold_marketed_demand_events: house 为空")
	assert(house.has("house_number"), "_append_sold_marketed_demand_events: house.house_number 缺失")
	var house_number_val = house.get("house_number", null)
	assert(
		house_number_val is int or house_number_val is float or house_number_val is String,
		"_append_sold_marketed_demand_events: house.house_number 类型错误（期望 int/float/String）"
	)
	var house_number = house_number_val

	for i in range(demands.size()):
		var d_val = demands[i]
		if not (d_val is Dictionary):
			continue
		var d: Dictionary = d_val
		if not d.has("from_player"):
			continue
		var fp = d.get("from_player", null)
		if not (fp is int):
			continue
		var from_player: int = int(fp)
		if from_player < 0:
			continue
		if from_player == winner_owner:
			continue
		out_events.append({
			"from_player": from_player,
			"sold_by": winner_owner,
			"house_id": house_id,
			"house_number": house_number,
			"demand_index": i,
		})

static func _build_demand_requirements(demands: Array) -> Result:
	var required: Dictionary = {}
	for i in range(demands.size()):
		var d = demands[i]
		if not (d is Dictionary):
			return Result.failure("晚餐结算失败：demands[%d] 类型错误（期望 Dictionary）" % i)
		var product_val = d.get("product", null)
		if not (product_val is String):
			return Result.failure("晚餐结算失败：demands[%d].product 类型错误（期望 String）" % i)
		var product := str(product_val)
		if product.is_empty():
			return Result.failure("晚餐结算失败：demands[%d].product 不能为空" % i)
		required[product] = int(required.get(product, 0)) + 1
	return Result.success(required)

static func _required_has_non_drink_food(required: Dictionary) -> Result:
	if required == null or not (required is Dictionary):
		return Result.failure("晚餐结算失败：required 类型错误（期望 Dictionary）")
	for product_id_val in required.keys():
		if not (product_id_val is String):
			return Result.failure("晚餐结算失败：required key 类型错误（期望 String）")
		var product_id: String = str(product_id_val)
		if product_id.is_empty():
			return Result.failure("晚餐结算失败：required key 不能为空")
		var def_val = ProductRegistryClass.get_def(product_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知产品定义: %s" % product_id)
		if not (def_val is ProductDef):
			return Result.failure("晚餐结算失败：产品定义类型错误（期望 ProductDef）: %s" % product_id)
		var def: ProductDef = def_val
		if def.has_tag("food") and not def.is_drink():
			return Result.success(true)
	return Result.success(false)

static func _player_has_inventory(player: Dictionary, required: Dictionary) -> Result:
	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("晚餐结算失败：player.inventory 类型错误（期望 Dictionary）")
	var inv: Dictionary = inv_val

	for product in required.keys():
		var need := int(required.get(product, 0))
		if need <= 0:
			continue
		var have := int(inv.get(product, 0))
		if have < need:
			return Result.success(false)
	return Result.success(true)

static func _apply_inventory_delta(state: GameState, player_id: int, required: Dictionary) -> Result:
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("晚餐结算失败：player[%d].inventory 类型错误（期望 Dictionary）" % player_id)
	var inv: Dictionary = inv_val

	for product in required.keys():
		var need := int(required.get(product, 0))
		if need <= 0:
			continue
		var before := int(inv.get(product, 0))
		var after := before - need
		if after < 0:
			return Result.failure("晚餐结算失败：库存扣减为负数: player=%d product=%s before=%d need=%d" % [player_id, str(product), before, need])
		inv[product] = after
	player["inventory"] = inv
	state.players[player_id] = player
	return Result.success()

static func _apply_employee_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return Result.failure("晚餐结算失败：player[%d].employees 类型错误（期望 Array）" % player_id)
	var employees: Array = employees_val

	var warnings: Array[String] = []
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 类型错误（期望 String）" % [player_id, i])
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].employees[%d] 不能为空" % [player_id, i])

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知员工定义: %s" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("晚餐结算失败：员工定义类型错误（期望 EmployeeDef）: %s" % emp_id)
		var def: EmployeeDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func _apply_milestone_effects_by_segment(
	state: GameState,
	player_id: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("晚餐结算失败：player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var milestones_val = player.get("milestones", null)
	if not (milestones_val is Array):
		return Result.failure("晚餐结算失败：player[%d].milestones 类型错误（期望 Array）" % player_id)
	var milestones: Array = milestones_val

	var warnings: Array[String] = []
	for i in range(milestones.size()):
		var ms_val = milestones[i]
		if not (ms_val is String):
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 类型错误（期望 String）" % [player_id, i])
		var ms_id: String = str(ms_val)
		if ms_id.is_empty():
			return Result.failure("晚餐结算失败：player[%d].milestones[%d] 不能为空" % [player_id, i])

		var def_val = MilestoneRegistryClass.get_def(ms_id)
		if def_val == null:
			return Result.failure("晚餐结算失败：未知里程碑定义: %s" % ms_id)
		if not (def_val is MilestoneDef):
			return Result.failure("晚餐结算失败：里程碑定义类型错误（期望 MilestoneDef）: %s" % ms_id)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func _apply_global_effects_by_segment(
	state: GameState,
	player_id_for_ctx: int,
	effect_registry,
	segment: String,
	ctx: Dictionary
) -> Result:
	if effect_registry == null:
		return Result.failure("晚餐结算失败：EffectRegistry 未设置")
	if segment.is_empty():
		return Result.failure("晚餐结算失败：effect segment 不能为空")
	if ctx == null or not (ctx is Dictionary):
		return Result.failure("晚餐结算失败：effect ctx 类型错误（期望 Dictionary）")
	if not (state.round_state is Dictionary):
		return Result.failure("晚餐结算失败：state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("晚餐结算失败：state.map 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []

	var sources: Array = []
	sources.append(state.round_state.get("global_effect_ids", null))
	sources.append(state.map.get("global_effect_ids", null))
	for src in sources:
		if src == null:
			continue
		if not (src is Array):
			return Result.failure("晚餐结算失败：global_effect_ids 类型错误（期望 Array[String]）")
		var ids: Array = src
		for i in range(ids.size()):
			var v = ids[i]
			if not (v is String):
				return Result.failure("晚餐结算失败：global_effect_ids[%d] 类型错误（期望 String）" % i)
			var effect_id: String = str(v)
			if effect_id.is_empty():
				return Result.failure("晚餐结算失败：global_effect_ids[%d] 不能为空" % i)
			if effect_id.find(segment) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id_for_ctx, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)

static func _is_candidate_better(state: GameState, a: Dictionary, b: Dictionary) -> bool:
	assert(a.has("score") and a["score"] is int, "内部错误: candidate.score 缺失或类型错误（期望 int）")
	assert(b.has("score") and b["score"] is int, "内部错误: candidate.score 缺失或类型错误（期望 int）")
	assert(a.has("tiebreak_score") and a["tiebreak_score"] is int, "内部错误: candidate.tiebreak_score 缺失或类型错误（期望 int）")
	assert(b.has("tiebreak_score") and b["tiebreak_score"] is int, "内部错误: candidate.tiebreak_score 缺失或类型错误（期望 int）")
	assert(a.has("owner") and a["owner"] is int, "内部错误: candidate.owner 缺失或类型错误（期望 int）")
	assert(b.has("owner") and b["owner"] is int, "内部错误: candidate.owner 缺失或类型错误（期望 int）")
	assert(a.has("distance") and a["distance"] is int, "内部错误: candidate.distance 缺失或类型错误（期望 int）")
	assert(b.has("distance") and b["distance"] is int, "内部错误: candidate.distance 缺失或类型错误（期望 int）")
	assert(a.has("steps") and a["steps"] is int, "内部错误: candidate.steps 缺失或类型错误（期望 int）")
	assert(b.has("steps") and b["steps"] is int, "内部错误: candidate.steps 缺失或类型错误（期望 int）")
	assert(a.has("restaurant_id") and a["restaurant_id"] is String, "内部错误: candidate.restaurant_id 缺失或类型错误（期望 String）")
	assert(b.has("restaurant_id") and b["restaurant_id"] is String, "内部错误: candidate.restaurant_id 缺失或类型错误（期望 String）")

	# 1) score 更小者优先（单价 + 距离）
	var a_score: int = int(a["score"])
	var b_score: int = int(b["score"])
	if a_score != b_score:
		return a_score < b_score

	# 2) tiebreak_score 更大者优先（默认=女服务员数量）
	var a_tb: int = int(a["tiebreak_score"])
	var b_tb: int = int(b["tiebreak_score"])
	if a_tb != b_tb:
		return a_tb > b_tb

	# 3) 回合顺序靠前者优先
	var a_owner: int = int(a["owner"])
	var b_owner: int = int(b["owner"])
	var a_rank := _turn_order_rank(state, a_owner)
	var b_rank := _turn_order_rank(state, b_owner)
	if a_rank != b_rank:
		return a_rank < b_rank

	# 4) 同一玩家多个餐厅：选距离更短（更稳定）
	var a_dist: int = int(a["distance"])
	var b_dist: int = int(b["distance"])
	if a_dist != b_dist:
		return a_dist < b_dist

	var a_steps: int = int(a["steps"])
	var b_steps: int = int(b["steps"])
	if a_steps != b_steps:
		return a_steps < b_steps

	return str(a["restaurant_id"]) < str(b["restaurant_id"])

static func _turn_order_rank(state: GameState, player_id: int) -> int:
	var idx := state.turn_order.find(player_id)
	return idx if idx >= 0 else 999999

static func _get_restaurant_to_house_distance(
	road_graph,
	state: GameState,
	grid_size: Vector2i,
	restaurant_id: String,
	rest: Dictionary,
	house_id: String,
	house: Dictionary
) -> Result:
	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("晚餐结算失败：houses[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % house_id)
	var house_cells_any: Array = house["cells"]
	var house_cells: Array[Vector2i] = []
	for i in range(house_cells_any.size()):
		var v = house_cells_any[i]
		if not (v is Vector2i):
			return Result.failure("晚餐结算失败：houses[%s].cells[%d] 类型错误（期望 Vector2i）" % [house_id, i])
		house_cells.append(v)

	var house_roads := _get_structure_adjacent_roads(state, grid_size, house_cells)
	if house_roads.is_empty():
		return Result.success({})

	var entrance_points_read := _get_restaurant_entrance_points(state, restaurant_id, rest)
	if not entrance_points_read.ok:
		return entrance_points_read
	var entrance_points_any: Array = entrance_points_read.value
	var entrance_points: Array[Vector2i] = []
	for i in range(entrance_points_any.size()):
		var p = entrance_points_any[i]
		if not (p is Vector2i):
			return Result.failure("晚餐结算失败：restaurants[%s] entrance_points[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		entrance_points.append(p)

	var rest_roads := _get_structure_adjacent_roads(state, grid_size, entrance_points)
	if rest_roads.is_empty():
		return Result.success({})

	var best_distance := INF
	var best_steps := INF
	var best_path: Array[Vector2i] = []
	for s in rest_roads:
		for t in house_roads:
			var sp = road_graph.find_shortest_path(s, t)
			if not sp.ok:
				continue
			assert(sp.value is Dictionary, "RoadGraph.find_shortest_path: value 类型错误（期望 Dictionary）")
			var sp_val: Dictionary = sp.value
			assert(sp_val.has("distance") and sp_val["distance"] is int, "RoadGraph.find_shortest_path: 缺少/错误 distance（期望 int）")
			assert(sp_val.has("steps") and sp_val["steps"] is int, "RoadGraph.find_shortest_path: 缺少/错误 steps（期望 int）")
			assert(sp_val.has("path") and sp_val["path"] is Array, "RoadGraph.find_shortest_path: 缺少/错误 path（期望 Array）")
			var d: int = int(sp_val["distance"])
			var steps: int = int(sp_val["steps"])
			var path_any: Array = sp_val["path"]
			var path: Array[Vector2i] = []
			for i in range(path_any.size()):
				var p = path_any[i]
				if not (p is Vector2i):
					return Result.failure("RoadGraph.find_shortest_path: path[%d] 类型错误（期望 Vector2i）" % i)
				path.append(p)
			if d < best_distance or (d == best_distance and steps < best_steps):
				best_distance = d
				best_steps = steps
				best_path = path

	if best_distance == INF:
		return Result.success({})
	return Result.success({
		"distance": int(best_distance),
		"steps": int(best_steps),
		"path": best_path,
	})

static func _get_restaurant_entrance_points(state: GameState, restaurant_id: String, rest: Dictionary) -> Result:
	if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
		return Result.failure("晚餐结算失败：restaurants[%s].entrance_pos 缺失或类型错误（期望 Vector2i）" % restaurant_id)
	var entrance: Vector2i = rest["entrance_pos"]

	if not rest.has("owner") or not (rest["owner"] is int):
		return Result.failure("晚餐结算失败：restaurants[%s].owner 缺失或类型错误（期望 int）" % restaurant_id)
	var owner: int = int(rest["owner"])
	if owner < 0 or owner >= state.players.size():
		return Result.success([entrance])

	# 免下车：四角都视为入口（本回合）
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("晚餐结算失败：player 类型错误: players[%d]（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	var drive_thru_active := false
	if player.has("drive_thru_active"):
		var v = player["drive_thru_active"]
		if not (v is bool):
			return Result.failure("晚餐结算失败：player[%d].drive_thru_active 类型错误（期望 bool）" % owner)
		drive_thru_active = bool(v)
	if not drive_thru_active:
		return Result.success([entrance])

	if not rest.has("cells") or not (rest["cells"] is Array):
		return Result.failure("晚餐结算失败：restaurants[%s].cells 缺失或类型错误（期望 Array[Vector2i]）" % restaurant_id)
	var cells_any: Array = rest["cells"]
	if cells_any.is_empty():
		return Result.success([entrance])
	var cells: Array[Vector2i] = []
	for i in range(cells_any.size()):
		var c = cells_any[i]
		if not (c is Vector2i):
			return Result.failure("晚餐结算失败：restaurants[%s].cells[%d] 类型错误（期望 Vector2i）" % [restaurant_id, i])
		cells.append(c)

	var bounds := MapUtils.get_footprint_bounds(cells)
	assert(bounds.has("min") and bounds["min"] is Vector2i, "MapUtils.get_footprint_bounds: 缺少/错误 min（期望 Vector2i）")
	assert(bounds.has("max") and bounds["max"] is Vector2i, "MapUtils.get_footprint_bounds: 缺少/错误 max（期望 Vector2i）")
	var min_pos: Vector2i = bounds["min"]
	var max_pos: Vector2i = bounds["max"]
	return Result.success([
		Vector2i(min_pos.x, min_pos.y),
		Vector2i(max_pos.x, min_pos.y),
		Vector2i(min_pos.x, max_pos.y),
		Vector2i(max_pos.x, max_pos.y),
	])

static func _get_structure_adjacent_roads(state: GameState, grid_size: Vector2i, structure_cells: Array[Vector2i]) -> Array[Vector2i]:
	var set := {}
	for cell in structure_cells:
		# 若结构自身在道路格上（例如棋盘外道路入口），也应视为入口道路。
		if MapRuntimeClass.has_cell_any(state, cell) and MapRuntimeClass.has_road_at_any(state, cell):
			set[cell] = true
		for dir in MapUtils.DIRECTIONS:
			var n := MapUtils.get_neighbor_pos(cell, dir)
			if not MapRuntimeClass.has_cell_any(state, n):
				continue
			if MapRuntimeClass.has_road_at_any(state, n):
				set[n] = true

	var result: Array[Vector2i] = []
	for k in set.keys():
		if k is Vector2i:
			result.append(k)
	return result

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
