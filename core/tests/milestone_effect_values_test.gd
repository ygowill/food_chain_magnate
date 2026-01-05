# 里程碑 effects.value 驱动回归测试
# 目标：确保关键规则不再依赖硬编码 milestone_id / GameConfig 常量，而是以里程碑 JSON 的 effects.value 为准。
class_name MilestoneEffectValuesTest
extends RefCounted

const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductDefClass = preload("res://core/data/product_def.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const PricingPipelineClass = preload("res://core/rules/pricing_pipeline.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	ProductRegistryClass.reset()
	var cfg := _configure_custom_milestones()
	if not cfg.ok:
		return cfg

	var r1 := _test_base_price_delta()
	if not r1.ok:
		return r1

	var r2 := _test_sell_bonus()
	if not r2.ok:
		return r2

	var r3 := _test_turnorder_empty_slots()
	if not r3.ok:
		return r3

	return Result.success({
		"cases": 3,
	})

static func _configure_custom_milestones() -> Result:
	var catalog = ContentCatalogClass.new()

	var p1_read := ProductDefClass.from_dict({"id": "burger", "name": "Burger", "tags": ["food"]})
	if not p1_read.ok:
		return Result.failure("创建 burger 失败: %s" % p1_read.error)
	catalog.products["burger"] = p1_read.value

	var p2_read := ProductDefClass.from_dict({"id": "pizza", "name": "Pizza", "tags": ["food"]})
	if not p2_read.ok:
		return Result.failure("创建 pizza 失败: %s" % p2_read.error)
	catalog.products["pizza"] = p2_read.value

	var p3_read := ProductDefClass.from_dict({"id": "soda", "name": "Soda", "tags": ["drink"]})
	if not p3_read.ok:
		return Result.failure("创建 soda 失败: %s" % p3_read.error)
	catalog.products["soda"] = p3_read.value

	var ms1_read := MilestoneDefClass.from_dict({
		"id": "ms_base_price",
		"name": "Base Price Delta",
		"trigger": {"event": "Dummy", "filter": {}},
		"effects": [{"type": "base_price_delta", "value": -2}],
		"exclusive_type": "ms_base_price",
		"expires_at": null,
		"pool": {"enabled": true}
	})
	if not ms1_read.ok:
		return Result.failure("创建 ms_base_price 失败: %s" % ms1_read.error)
	catalog.milestones["ms_base_price"] = ms1_read.value

	var ms2_read := MilestoneDefClass.from_dict({
		"id": "ms_burger_bonus",
		"name": "Burger Sell Bonus",
		"trigger": {"event": "Dummy", "filter": {}},
		"effects": [{"type": "sell_bonus", "product": "burger", "value": 7}],
		"exclusive_type": "ms_burger_bonus",
		"expires_at": null,
		"pool": {"enabled": true}
	})
	if not ms2_read.ok:
		return Result.failure("创建 ms_burger_bonus 失败: %s" % ms2_read.error)
	catalog.milestones["ms_burger_bonus"] = ms2_read.value

	var ms3_read := MilestoneDefClass.from_dict({
		"id": "ms_drink_bonus",
		"name": "Drink Sell Bonus",
		"trigger": {"event": "Dummy", "filter": {}},
		"effects": [{"type": "sell_bonus", "product": "drink", "value": 2}],
		"exclusive_type": "ms_drink_bonus",
		"expires_at": null,
		"pool": {"enabled": true}
	})
	if not ms3_read.ok:
		return Result.failure("创建 ms_drink_bonus 失败: %s" % ms3_read.error)
	catalog.milestones["ms_drink_bonus"] = ms3_read.value

	var ms4_read := MilestoneDefClass.from_dict({
		"id": "ms_oob_bonus",
		"name": "Order Of Business Empty Slots Bonus",
		"trigger": {"event": "Dummy", "filter": {}},
		"effects": [{"type": "turnorder_empty_slots", "value": 3}],
		"exclusive_type": "ms_oob_bonus",
		"expires_at": null,
		"pool": {"enabled": true}
	})
	if not ms4_read.ok:
		return Result.failure("创建 ms_oob_bonus 失败: %s" % ms4_read.error)
	catalog.milestones["ms_oob_bonus"] = ms4_read.value

	var rr := MilestoneRegistryClass.configure_from_catalog(catalog)
	if not rr.ok:
		return Result.failure("配置 MilestoneRegistry 失败: %s" % rr.error)

	var pr := ProductRegistryClass.configure_from_catalog(catalog)
	if not pr.ok:
		return Result.failure("配置 ProductRegistry 失败: %s" % pr.error)

	return Result.success()

static func _test_base_price_delta() -> Result:
	var state := GameStateClass.new()
	state.rules = {"base_unit_price": 10}
	state.players = [
		{
			"milestones": ["ms_base_price"],
		}
	]

	var p1 := PricingPipelineClass.calculate_unit_price(state, 0)
	if not p1.ok:
		return Result.failure("calculate_unit_price 失败: %s" % p1.error)
	if int(p1.value) != 8:
		return Result.failure("base_price_delta=-2 应使单价=8，实际: %d" % int(p1.value))

	state.round_state["price_modifiers"] = {0: {"test": 1}}
	var p2 := PricingPipelineClass.calculate_unit_price(state, 0)
	if not p2.ok:
		return Result.failure("calculate_unit_price(含 price_modifiers) 失败: %s" % p2.error)
	if int(p2.value) != 9:
		return Result.failure("单价应叠加 price_modifiers(+1) => 9，实际: %d" % int(p2.value))

	return Result.success()

static func _test_sell_bonus() -> Result:
	var state := GameStateClass.new()
	state.players = [
		{
			"milestones": ["ms_burger_bonus", "ms_drink_bonus"],
		}
	]

	var required := {
		"burger": 2,
		"pizza": 1,
		"soda": 3,
	}

	var b := PricingPipelineClass.calculate_marketing_bonus(state, 0, required)
	if not b.ok:
		return Result.failure("calculate_marketing_bonus 失败: %s" % b.error)
	var expected := 2 * 7 + 3 * 2
	if int(b.value) != expected:
		return Result.failure("sell_bonus 应按 effects.value 计算: 期望 %d，实际: %d" % [expected, int(b.value)])

	return Result.success()

static func _test_turnorder_empty_slots() -> Result:
	var state := GameStateClass.new()
	state.players = [
		{
			"employees": ["ceo"],
			"company_structure": {"ceo_slots": 3, "structure": []},
			"milestones": ["ms_oob_bonus"],
		},
		{
			"employees": ["ceo"],
			"company_structure": {"ceo_slots": 3, "structure": []},
			"milestones": [],
		},
	]
	state.turn_order = [1, 0]
	state.current_player_index = 0

	WorkingFlowClass.start_order_of_business(state)
	if state.selection_order != [0, 1]:
		return Result.failure("ms_oob_bonus(value=3) 应使玩家0优先选择，实际 selection_order: %s" % str(state.selection_order))

	return Result.success()
