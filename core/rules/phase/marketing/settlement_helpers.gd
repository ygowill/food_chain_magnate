# MarketingSettlement：内部 helper 下沉（到期/产品序列/需求写入/effects/排序）
class_name MarketingSettlementHelpers
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")

const EFFECT_SEG_MARKETING_DEMAND_AMOUNT := ":marketing:demand_amount:"
const EFFECT_SEG_MARKETING_DEMAND_CASH := ":marketing:demand_cash:"

static func expire_marketing_instance(state: GameState, inst: Dictionary) -> void:
	assert(inst.has("board_number") and (inst["board_number"] is int), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 board_number（期望 int）")
	assert(inst.has("owner") and (inst["owner"] is int), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 owner（期望 int）")
	assert(inst.has("employee_type") and (inst["employee_type"] is String), "MarketingSettlementHelpers.expire_marketing_instance: 缺少/错误 employee_type（期望 String）")
	var board_number: int = inst["board_number"]
	var owner: int = inst["owner"]
	var employee_type: String = inst["employee_type"]
	var link_id := ""
	if inst.has("link_id") and (inst["link_id"] is String):
		link_id = str(inst["link_id"])

	# 收回营销板件
	assert(state.map.has("marketing_placements") and state.map["marketing_placements"] is Dictionary, "MarketingSettlementHelpers.expire_marketing_instance: state.map.marketing_placements 缺失或类型错误（期望 Dictionary）")
	state.map["marketing_placements"].erase(str(board_number))

	# 释放忙碌营销员：仅当该员工仍处于忙碌区（可能在 Payday 被解雇）
	assert(owner >= 0 and owner < state.players.size(), "MarketingSettlementHelpers.expire_marketing_instance: owner 越界: %d" % owner)
	assert(not employee_type.is_empty(), "MarketingSettlementHelpers.expire_marketing_instance: employee_type 不能为空")

	# 扩展点：某些营销员（例如品牌总监）可被标记为“永不释放”
	if inst.has("no_release"):
		var nr = inst.get("no_release", false)
		if nr is bool and bool(nr):
			return

	# 若该员工链接到多个营销实例（例如 campaign manager 的第二张板件），只在最后一个实例到期时释放。
	if not link_id.is_empty():
		for other_val in state.marketing_instances:
			if not (other_val is Dictionary):
				continue
			var other: Dictionary = other_val
			if int(other.get("board_number", -1)) == board_number:
				continue
			if not (other.get("link_id", "") is String):
				continue
			if str(other.get("link_id", "")) != link_id:
				continue
			var rem = other.get("remaining_duration", null)
			# rem==1：本轮也会到期，因此不应阻止释放
			if rem is int and int(rem) > 1:
				return
			if rem is int and int(rem) == -1:
				return

	var removed := StateUpdaterClass.remove_from_array(state.players[owner], "busy_marketers", employee_type)
	if removed:
		StateUpdaterClass.append_to_array(state.players[owner], "reserve_employees", employee_type)

static func get_products_in_order(inst: Dictionary) -> Result:
	if inst == null or not (inst is Dictionary):
		return Result.failure("MarketingSettlement: inst 类型错误（期望 Dictionary）")
	if not inst.has("product") or not (inst["product"] is String):
		return Result.failure("MarketingSettlement: inst.product 缺失或类型错误（期望 String）")
	var primary: String = str(inst["product"])
	if primary.is_empty():
		return Result.failure("MarketingSettlement: inst.product 不能为空")

	if not inst.has("products"):
		return Result.success([primary])

	var products_val = inst.get("products", null)
	if products_val == null:
		return Result.success([primary])
	if not (products_val is Array):
		return Result.failure("MarketingSettlement: inst.products 类型错误（期望 Array）")
	var products: Array = products_val
	if products.is_empty():
		return Result.success([primary])

	var out: Array[String] = []
	for i in range(products.size()):
		var v = products[i]
		if not (v is String):
			return Result.failure("MarketingSettlement: inst.products[%d] 类型错误（期望 String）" % i)
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("MarketingSettlement: inst.products[%d] 不能为空" % i)
		out.append(s)

	return Result.success(out)

static func add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("MarketingSettlement: state.map.houses 类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	if not houses.has(house_id):
		return Result.failure("MarketingSettlement: houses 缺少 house_id: %s" % house_id)
	var house_val = houses[house_id]
	if not (house_val is Dictionary):
		return Result.failure("MarketingSettlement: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	var cap = state.get_rule_int("demand_cap_normal")
	if not house.has("has_garden") or not (house["has_garden"] is bool):
		return Result.failure("MarketingSettlement: houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	if bool(house["has_garden"]):
		cap = state.get_rule_int("demand_cap_with_garden")

	if house.has("no_demand_cap"):
		var v = house.get("no_demand_cap", false)
		if not (v is bool):
			return Result.failure("MarketingSettlement: houses[%s].no_demand_cap 类型错误（期望 bool）" % house_id)
		if bool(v):
			cap = 2147483647

	if not house.has("demands") or not (house["demands"] is Array):
		return Result.failure("MarketingSettlement: houses[%s].demands 缺失或类型错误（期望 Array）" % house_id)
	var demands: Array = house["demands"]

	# 扩展点：允许房屋声明“营销需求倍增”（例如公寓：每次营销放 2 个 token）
	var demand_multiplier := 1
	if house.has("marketing_demand_multiplier"):
		var m_val = house.get("marketing_demand_multiplier", null)
		if m_val is int:
			demand_multiplier = int(m_val)
		elif m_val is float:
			var f: float = float(m_val)
			if f != floor(f):
				return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 必须为整数，实际: %s" % [house_id, str(m_val)])
			demand_multiplier = int(f)
		else:
			return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 类型错误（期望 int/float）" % house_id)
		if demand_multiplier <= 0:
			return Result.failure("MarketingSettlement: houses[%s].marketing_demand_multiplier 必须 > 0，实际: %d" % [house_id, demand_multiplier])

	var effective_amount := amount * demand_multiplier
	if effective_amount < 0:
		return Result.failure("MarketingSettlement: effective_amount 不能为负数: %d" % effective_amount)

	var added := 0
	while added < effective_amount and demands.size() < cap:
		demands.append({
			"product": product,
			"from_player": from_player,
			"board_number": board_number,
			"type": marketing_type
		})
		added += 1

	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
	return Result.success(added)

static func get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	assert(state != null, "MarketingSettlementHelpers.get_demand_amount_for_instance: state 为空")
	assert(inst != null, "MarketingSettlementHelpers.get_demand_amount_for_instance: inst 为空")

	if not inst.has("type") or not (inst["type"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.type 缺失或类型错误（期望 String）")
	if not inst.has("owner") or not (inst["owner"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.owner 缺失或类型错误（期望 int）")
	var marketing_type: String = str(inst["type"])
	var owner: int = int(inst["owner"])

	if effect_registry == null:
		return Result.failure("MarketingSettlement: EffectRegistry 未设置")

	var warnings: Array[String] = []
	var ctx := {
		"marketing_type": marketing_type,
		"demand_amount": 1,
	}
	if inst.has("demand_amount"):
		var base_val = inst.get("demand_amount", null)
		if not (base_val is int):
			return Result.failure("MarketingSettlement: inst.demand_amount 类型错误（期望 int）")
		var base_amount: int = int(base_val)
		if base_amount < 0:
			return Result.failure("MarketingSettlement: inst.demand_amount 不能为负数: %d" % base_amount)
		ctx["demand_amount"] = base_amount

	if owner < 0 or owner >= state.players.size():
		return Result.failure("MarketingSettlement: owner 越界: %d" % owner)
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("MarketingSettlement: players[%d] 类型错误（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("MarketingSettlement: player[%d].milestones 缺失或类型错误（期望 Array）" % owner)
	var milestones: Array = player["milestones"]

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("MarketingSettlement: player[%d].milestones[%d] 类型错误（期望 String）" % [owner, i])
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("MarketingSettlement: player[%d].milestones 不应包含空字符串" % owner)

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("MarketingSettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("MarketingSettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_MARKETING_DEMAND_AMOUNT) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, owner, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var v = ctx.get("demand_amount", null)
	if not (v is int):
		return Result.failure("MarketingSettlement: ctx.demand_amount 类型错误（期望 int）")
	var amount: int = int(v)
	if amount < 0:
		return Result.failure("MarketingSettlement: demand_amount 不能为负数: %d" % amount)
	return Result.success(amount).with_warnings(warnings)

static func apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	assert(state != null, "MarketingSettlementHelpers.apply_marketing_demand_cash_effects: state 为空")
	assert(inst != null, "MarketingSettlementHelpers.apply_marketing_demand_cash_effects: inst 为空")

	if demands_added <= 0:
		return Result.success()
	if effect_registry == null:
		return Result.failure("MarketingSettlement: EffectRegistry 未设置")

	if not inst.has("owner") or not (inst["owner"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.owner 缺失或类型错误（期望 int）")
	if not inst.has("type") or not (inst["type"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.type 缺失或类型错误（期望 String）")
	if not inst.has("board_number") or not (inst["board_number"] is int):
		return Result.failure("MarketingSettlement: marketing_instances.board_number 缺失或类型错误（期望 int）")
	if not inst.has("product") or not (inst["product"] is String):
		return Result.failure("MarketingSettlement: marketing_instances.product 缺失或类型错误（期望 String）")

	var owner: int = int(inst["owner"])
	var marketing_type: String = str(inst["type"])
	var board_number: int = int(inst["board_number"])
	var product: String = str(inst["product"])

	if owner < 0 or owner >= state.players.size():
		return Result.failure("MarketingSettlement: owner 越界: %d" % owner)
	var player_val = state.players[owner]
	if not (player_val is Dictionary):
		return Result.failure("MarketingSettlement: players[%d] 类型错误（期望 Dictionary）" % owner)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("MarketingSettlement: player[%d].milestones 缺失或类型错误（期望 Array）" % owner)
	var milestones: Array = player["milestones"]

	var warnings: Array[String] = []
	var ctx := {
		"marketing_type": marketing_type,
		"board_number": board_number,
		"product": product,
		"demands_added": demands_added,
		"cash_bonus": 0,
		"marketing_instance": inst,
	}

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("MarketingSettlement: player[%d].milestones[%d] 类型错误（期望 String）" % [owner, i])
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("MarketingSettlement: player[%d].milestones 不应包含空字符串" % owner)

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("MarketingSettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("MarketingSettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_MARKETING_DEMAND_CASH) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, owner, ctx])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var cash_val = ctx.get("cash_bonus", null)
	if not (cash_val is int):
		return Result.failure("MarketingSettlement: ctx.cash_bonus 类型错误（期望 int）")
	var cash_bonus: int = int(cash_val)
	if cash_bonus < 0:
		return Result.failure("MarketingSettlement: ctx.cash_bonus 不能为负数: %d" % cash_bonus)
	if cash_bonus <= 0:
		return Result.success().with_warnings(warnings)

	var pay := BankruptcyRulesClass.pay_bank_to_player(state, owner, cash_bonus, "营销需求奖金")
	if not pay.ok:
		return pay
	warnings.append_array(pay.warnings)
	return Result.success().with_warnings(warnings)

static func sort_house_ids_by_number(state: GameState, house_ids: Array[String]) -> Array[String]:
	if house_ids.is_empty():
		return []
	assert(state != null, "MarketingSettlementHelpers.sort_house_ids_by_number: state 为空")
	assert(state.map is Dictionary, "MarketingSettlementHelpers.sort_house_ids_by_number: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "MarketingSettlementHelpers.sort_house_ids_by_number: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]

	var subset := {}
	var seen := {}
	for hid in house_ids:
		assert(hid is String and not str(hid).is_empty(), "MarketingSettlementHelpers.sort_house_ids_by_number: house_id 不能为空")
		var id: String = str(hid)
		assert(not seen.has(id), "MarketingSettlementHelpers.sort_house_ids_by_number: 重复 house_id: %s" % id)
		seen[id] = true
		assert(houses.has(id), "MarketingSettlementHelpers.sort_house_ids_by_number: house_id 不存在: %s" % id)
		assert(houses[id] is Dictionary, "MarketingSettlementHelpers.sort_house_ids_by_number: houses[%s] 类型错误（期望 Dictionary）" % id)
		subset[id] = houses[id]

	return HouseNumberManagerClass.get_sorted_house_ids(subset)

