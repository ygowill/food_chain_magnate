# MarketingSettlement：需求写入 + 房屋排序（从 settlement_helpers_impl.gd 抽离）
extends RefCounted

const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, "MarketingSettlement")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
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
	state.map[MapStateAccessClass.KEY_HOUSES] = houses
	return Result.success(added)

static func sort_house_ids_by_number(state: GameState, house_ids: Array) -> Result:
	if house_ids.is_empty():
		return Result.success([])
	var houses_read := MapStateAccessClass.require_houses(state, "MarketingSettlementHelpers.sort_house_ids_by_number")
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value

	var subset := {}
	var seen := {}
	for hid in house_ids:
		if not (hid is String):
			return Result.failure("MarketingSettlementHelpers.sort_house_ids_by_number: house_id 类型错误（期望 String）")
		var id: String = str(hid)
		if id.is_empty():
			return Result.failure("MarketingSettlementHelpers.sort_house_ids_by_number: house_id 不能为空")
		if seen.has(id):
			return Result.failure("MarketingSettlementHelpers.sort_house_ids_by_number: 重复 house_id: %s" % id)
		seen[id] = true
		if not houses.has(id):
			return Result.failure("MarketingSettlementHelpers.sort_house_ids_by_number: house_id 不存在: %s" % id)
		if not (houses[id] is Dictionary):
			return Result.failure("MarketingSettlementHelpers.sort_house_ids_by_number: houses[%s] 类型错误（期望 Dictionary）" % id)
		subset[id] = houses[id]

	return HouseNumberManagerClass.get_sorted_house_ids(subset)
