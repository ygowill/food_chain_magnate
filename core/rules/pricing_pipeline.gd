# 定价管道（M4）
# 目标：将“单价/奖励/倍增/下限”等从晚餐结算中解耦出来，便于后续模块化扩展。
class_name PricingPipeline
extends RefCounted

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

static func calculate_unit_price(state: GameState, player_id: int) -> Result:
	var unit_price: int = state.get_rule_int("base_unit_price")

	var player := state.get_player(player_id)
	if not player.is_empty():
		if not player.has("milestones") or not (player["milestones"] is Array):
			return Result.failure("PricingPipeline: player[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
		var milestones: Array = player["milestones"]
		var delta_read := _get_base_price_delta_from_milestones(milestones)
		if not delta_read.ok:
			return delta_read
		unit_price += int(delta_read.value)

	# Working 阶段强制动作写入的价格修正（按玩家独立）
	assert(state.round_state is Dictionary, "PricingPipeline: state.round_state 类型错误（期望 Dictionary）")
	var round_state: Dictionary = state.round_state

	var pm_val = round_state.get("price_modifiers", null)
	if pm_val == null:
		return Result.success(unit_price)
	assert(pm_val is Dictionary, "PricingPipeline: round_state.price_modifiers 类型错误（期望 Dictionary）")
	var price_modifiers: Dictionary = pm_val
	assert(not price_modifiers.has(str(player_id)), "round_state.price_modifiers 不应包含字符串玩家 key: %s" % str(player_id))

	var mods_val = price_modifiers.get(player_id, null)
	if mods_val == null:
		return Result.success(unit_price)
	assert(mods_val is Dictionary, "PricingPipeline: round_state.price_modifiers[%d] 类型错误（期望 Dictionary）" % player_id)
	var mods: Dictionary = mods_val

	for k in mods.keys():
		assert(k is String, "PricingPipeline: round_state.price_modifiers[%d] key 类型错误（期望 String）" % player_id)
		var delta_val = mods.get(k, null)
		assert(delta_val is int, "PricingPipeline: round_state.price_modifiers[%d].%s 类型错误（期望 int）" % [player_id, str(k)])
		unit_price += int(delta_val)

	return Result.success(unit_price)

static func calculate_marketing_bonus(state: GameState, player_id: int, required: Dictionary) -> Result:
	if not (required is Dictionary):
		return Result.failure("PricingPipeline: required 类型错误（期望 Dictionary）")

	var player := state.get_player(player_id)
	var milestones: Array = []
	if not player.is_empty():
		if not player.has("milestones") or not (player["milestones"] is Array):
			return Result.failure("PricingPipeline: player[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
		milestones = player["milestones"]

	var bonuses_read := _get_sell_bonus_by_category_from_milestones(milestones)
	if not bonuses_read.ok:
		return bonuses_read
	var bonuses: Dictionary = bonuses_read.value

	var bonus: int = 0
	for product in required.keys():
		var count := int(required.get(product, 0))
		if count <= 0:
			continue

		var p := str(product)
		if not ProductRegistryClass.is_loaded():
			return Result.failure("PricingPipeline: ProductRegistry 未初始化")
		if ProductRegistryClass.get_def(p) == null:
			return Result.failure("PricingPipeline: 未知产品: %s" % p)
		var category := "drink" if ProductRegistryClass.is_drink(p) else p
		if bonuses.has(category):
			var per_val = bonuses.get(category, null)
			if not (per_val is int):
				return Result.failure("PricingPipeline: sell_bonus[%s] 类型错误（期望 int）" % category)
			bonus += count * int(per_val)

	return Result.success(bonus)

static func calculate_sale_breakdown(state: GameState, player_id: int, house: Dictionary, required: Dictionary) -> Result:
	var quantity := 0
	for product in required.keys():
		quantity += int(required.get(product, 0))

	var unit_price_read := calculate_unit_price(state, player_id)
	if not unit_price_read.ok:
		return unit_price_read
	var unit_price: int = int(unit_price_read.value)
	var has_garden := bool(house.get("has_garden", false))

	# “单价 + 距离”用于胜负判定；花园仅影响收入（docs/rules.md Phase 4）
	var decision_unit_price := unit_price

	# 收入计算（docs/rules.md）：(单价 * 数量) + 奖励；花园翻倍“单价部分”；最终收入下限 0
	var price_part := unit_price * quantity
	if has_garden:
		price_part *= 2
	var bonus_read := calculate_marketing_bonus(state, player_id, required)
	if not bonus_read.ok:
		return bonus_read
	var bonus: int = int(bonus_read.value)
	var revenue := price_part + bonus
	if revenue < 0:
		revenue = 0

	return Result.success({
		"unit_price": unit_price,
		"decision_unit_price": decision_unit_price,
		"quantity": quantity,
		"has_garden": has_garden,
		"price_part": price_part,
		"bonus": bonus,
		"revenue": revenue,
	})

static func _get_base_price_delta_from_milestones(milestones: Array) -> Result:
	if not MilestoneRegistryClass.is_loaded():
		return Result.failure("PricingPipeline: MilestoneRegistry 未初始化")

	var delta := 0
	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("PricingPipeline: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("PricingPipeline: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("PricingPipeline: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDefClass):
			return Result.failure("PricingPipeline: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("PricingPipeline: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("PricingPipeline: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "base_price_delta":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("PricingPipeline: %s" % v_read.error)
			delta += int(v_read.value)

	return Result.success(delta)

static func _get_sell_bonus_by_category_from_milestones(milestones: Array) -> Result:
	if not MilestoneRegistryClass.is_loaded():
		return Result.failure("PricingPipeline: MilestoneRegistry 未初始化")

	var out: Dictionary = {}

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("PricingPipeline: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("PricingPipeline: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("PricingPipeline: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDefClass):
			return Result.failure("PricingPipeline: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("PricingPipeline: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("PricingPipeline: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "sell_bonus":
				continue

			var product_val = eff.get("product", null)
			if not (product_val is String):
				return Result.failure("PricingPipeline: %s.effects[%d].product 类型错误（期望 String）" % [mid, e_i])
			var product: String = str(product_val)
			if product.is_empty():
				return Result.failure("PricingPipeline: %s.effects[%d].product 不能为空" % [mid, e_i])

			var value_val = eff.get("value", null)
			var v_read := _parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("PricingPipeline: %s" % v_read.error)

			out[product] = int(out.get(product, 0)) + int(v_read.value)

	return Result.success(out)

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			return Result.success(int(f))
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为整数" % path)

static func _parse_non_negative_int_value(value, path: String) -> Result:
	var r := _parse_int_value(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r
