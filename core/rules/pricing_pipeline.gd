# 定价管道（M4）
# 目标：将“单价/奖励/倍增/下限”等从晚餐结算中解耦出来，便于后续模块化扩展。
class_name PricingPipeline
extends RefCounted

const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func calculate_unit_price(state: GameState, player_id: int) -> Result:
	var unit_price: int = state.get_rule_int("base_unit_price")

	var player := state.get_player(player_id)
	if not player.is_empty():
		var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % player_id, "PricingPipeline")
		if not milestones_read.ok:
			return milestones_read
		var milestones: Array = milestones_read.value
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
		var milestones_read := PlayerStateAccessClass.require_milestones(player, "player[%d]" % player_id, "PricingPipeline")
		if not milestones_read.ok:
			return milestones_read
		milestones = milestones_read.value

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
	return MilestoneEffectQueriesClass.sum_int_values(
		milestones,
		"base_price_delta",
		"PricingPipeline: ",
		"milestones"
	)

static func _get_sell_bonus_by_category_from_milestones(milestones: Array) -> Result:
	var out: Dictionary = {}

	var entries_read := MilestoneEffectQueriesClass.collect_effect_entries(
		milestones,
		"sell_bonus",
		"PricingPipeline: ",
		"milestones"
	)
	if not entries_read.ok:
		return entries_read
	var entries: Array = entries_read.value

	for entry_val in entries:
		var entry: Dictionary = entry_val
		var mid: String = str(entry.get("milestone_id", ""))
		var e_i: int = int(entry.get("effect_index", -1))
		var eff_val = entry.get("effect", null)
		var eff: Dictionary = eff_val

		var product_val = eff.get("product", null)
		if not (product_val is String):
			return Result.failure("PricingPipeline: %s.effects[%d].product 类型错误（期望 String）" % [mid, e_i])
		var product: String = str(product_val)
		if product.is_empty():
			return Result.failure("PricingPipeline: %s.effects[%d].product 不能为空" % [mid, e_i])

		var value_val = eff.get("value", null)
		var v_read := IntValueParseHelpersClass.parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
		if not v_read.ok:
			return Result.failure("PricingPipeline: %s" % v_read.error)

		out[product] = int(out.get(product, 0)) + int(v_read.value)

	return Result.success(out)
