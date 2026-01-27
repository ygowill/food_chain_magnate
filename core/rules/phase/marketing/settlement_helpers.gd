# MarketingSettlement：内部 helper 下沉（到期/产品序列/需求写入/effects/排序）
class_name MarketingSettlementHelpers
extends RefCounted

const Impl = preload("res://core/rules/phase/marketing/settlement_helpers_impl.gd")

static func expire_marketing_instance(state: GameState, inst: Dictionary) -> void:
	Impl.expire_marketing_instance(state, inst)

static func get_products_in_order(inst: Dictionary) -> Result:
	return Impl.get_products_in_order(inst)

static func add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	return Impl.add_house_demand(state, house_id, product, from_player, board_number, marketing_type, amount)

static func get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	return Impl.get_demand_amount_for_instance(state, inst, effect_registry)

static func apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	return Impl.apply_marketing_demand_cash_effects(state, effect_registry, inst, demands_added)

static func sort_house_ids_by_number(state: GameState, house_ids: Array) -> Result:
	return Impl.sort_house_ids_by_number(state, house_ids)
