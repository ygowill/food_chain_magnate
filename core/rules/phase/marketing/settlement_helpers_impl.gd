# MarketingSettlementHelpers：实现（分模块抽离）
extends RefCounted

const InstanceExpirationClass = preload("res://core/rules/phase/marketing/settlement_instance_expiration.gd")
const ProductsClass = preload("res://core/rules/phase/marketing/settlement_products.gd")
const HouseDemandClass = preload("res://core/rules/phase/marketing/settlement_house_demand.gd")
const DemandEffectsClass = preload("res://core/rules/phase/marketing/settlement_demand_effects.gd")

static func expire_marketing_instance(state: GameState, inst: Dictionary) -> void:
	InstanceExpirationClass.expire_marketing_instance(state, inst)

static func get_products_in_order(inst: Dictionary) -> Result:
	return ProductsClass.get_products_in_order(inst)

static func add_house_demand(
	state: GameState,
	house_id: String,
	product: String,
	from_player: int,
	board_number: int,
	marketing_type: String,
	amount: int
) -> Result:
	return HouseDemandClass.add_house_demand(state, house_id, product, from_player, board_number, marketing_type, amount)

static func get_demand_amount_for_instance(state: GameState, inst: Dictionary, effect_registry) -> Result:
	return DemandEffectsClass.get_demand_amount_for_instance(state, inst, effect_registry)

static func apply_marketing_demand_cash_effects(state: GameState, effect_registry, inst: Dictionary, demands_added: int) -> Result:
	return DemandEffectsClass.apply_marketing_demand_cash_effects(state, effect_registry, inst, demands_added)

static func sort_house_ids_by_number(state: GameState, house_ids: Array[String]) -> Array[String]:
	return HouseDemandClass.sort_house_ids_by_number(state, house_ids)
