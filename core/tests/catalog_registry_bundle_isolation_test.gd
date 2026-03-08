# Catalog registry bundle 隔离回归测试
class_name CatalogRegistryBundleIsolationTest
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const BankruptcyRegistryClass = preload("res://core/rules/bankruptcy_registry.gd")
const MarketingInitiationRegistryClass = preload("res://core/rules/marketing_initiation_registry.gd")
const PlacementConflictRegistryClass = preload("res://core/rules/placement_conflict_registry.gd")
const RangeOriginRegistryClass = preload("res://core/rules/range_origin_registry.gd")
const EmployeePoolPatchRegistryClass = preload("res://core/rules/employee_pool_patch_registry.gd")
const DinnertimeRoutePurchaseRegistryClass = preload("res://core/rules/dinnertime_route_purchase_registry.gd")
const DinnertimeDemandRegistryClass = preload("res://core/rules/dinnertime_demand_registry.gd")
const StateSchemaRegistryClass = preload("res://core/state/state_schema_registry.gd")

static func run(seed_val: int = 12345) -> Result:
	var base_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"base_milestones",
	]
	var optional_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"lobbyists",
		"new_milestones",
		"gourmet_food_critics",
		"reserve_prices",
		"rural_marketeers",
		"coffee",
		"sushi",
	]

	var engine_a := GameEngine.new()
	var init_a := engine_a.initialize(2, seed_val, base_modules)
	if not init_a.ok:
		return Result.failure("engine_a 初始化失败: %s" % init_a.error)

	engine_a.activate_registry_bundles()
	if PieceRegistryClass.has("lobbyists_road_straight"):
		return Result.failure("engine_a 不应看到 lobbyists piece")
	if EmployeeRegistryClass.has("lobbyist"):
		return Result.failure("engine_a 不应看到 lobbyists employee")
	if MilestoneRegistryClass.has("first_marketeer_used"):
		return Result.failure("engine_a 不应看到 new_milestones milestone")
	if MilestoneEffectRegistryClass.get_current() != engine_a.ruleset_v2.milestone_effect_registry:
		return Result.failure("engine_a 激活后应切换 milestone effect registry")
	if MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("engine_a 不应看到 gourmet_guide marketing type")
	if BankruptcyRegistryClass.has_first_break_handler():
		return Result.failure("engine_a 不应看到 reserve_prices bankruptcy handler")
	if BankruptcyRegistryClass.get_first_break_source() != "builtin":
		return Result.failure("engine_a bankruptcy source 应保持 builtin")
	if not MarketingInitiationRegistryClass.get_provider_ids().is_empty():
		return Result.failure("engine_a 不应看到 new_milestones marketing initiation providers")
	if not PlacementConflictRegistryClass.get_provider_ids().is_empty():
		return Result.failure("engine_a 不应看到 rural_marketeers placement conflict providers")
	if not RangeOriginRegistryClass.get_provider_ids().is_empty():
		return Result.failure("engine_a 不应看到 coffee range origin providers")
	if not EmployeePoolPatchRegistryClass.get_patch_ids().is_empty():
		return Result.failure("engine_a 不应看到 employee pool patches")
	if not DinnertimeRoutePurchaseRegistryClass.get_provider_ids().is_empty():
		return Result.failure("engine_a 不应看到 dinnertime route purchase providers")
	if not DinnertimeDemandRegistryClass.get_provider_ids().is_empty():
		return Result.failure("engine_a 不应看到 dinnertime demand providers")
	if StateSchemaRegistryClass.get_schema_ids() != ["base_rules:round_state_int_keys:restructuring.submitted"]:
		return Result.failure("engine_a state schema ids 不符合预期: %s" % str(StateSchemaRegistryClass.get_schema_ids()))

	var engine_b := GameEngine.new()
	var init_b := engine_b.initialize(2, seed_val, optional_modules)
	if not init_b.ok:
		return Result.failure("engine_b 初始化失败: %s" % init_b.error)

	if engine_a.get_catalog_registry_bundle() == engine_b.get_catalog_registry_bundle():
		return Result.failure("不同 GameEngine 不应共享 catalog_registry_bundle 实例")

	engine_b.activate_registry_bundles()
	if not PieceRegistryClass.has("lobbyists_road_straight"):
		return Result.failure("engine_b 应看到 lobbyists piece")
	if not EmployeeRegistryClass.has("lobbyist"):
		return Result.failure("engine_b 应看到 lobbyists employee")
	if not MilestoneRegistryClass.has("first_marketeer_used"):
		return Result.failure("engine_b 应看到 new_milestones milestone")
	if not ProductRegistryClass.has("soda"):
		return Result.failure("engine_b 应保持 base product 可见（soda）")
	if not MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("engine_b 应看到 gourmet_guide marketing type")
	if not BankruptcyRegistryClass.has_first_break_handler():
		return Result.failure("engine_b 应看到 reserve_prices bankruptcy handler")
	if BankruptcyRegistryClass.get_first_break_source() != "reserve_prices":
		return Result.failure("engine_b bankruptcy source 应切换到 reserve_prices")
	var init_provider_ids := MarketingInitiationRegistryClass.get_provider_ids()
	if init_provider_ids != [
		"new_milestones:campaign_manager:pending_second_tile",
		"new_milestones:brand_manager:pending_airplane_second_good",
		"new_milestones:brand_director:radio_permanent_and_busy_forever",
	]:
		return Result.failure("engine_b marketing initiation providers 不符合预期: %s" % str(init_provider_ids))
	if PlacementConflictRegistryClass.get_provider_ids() != ["rural_marketeers:placement_conflicts"]:
		return Result.failure("engine_b placement conflict providers 不符合预期: %s" % str(PlacementConflictRegistryClass.get_provider_ids()))
	if RangeOriginRegistryClass.get_provider_ids() != ["coffee:range_origins:coffee_shops"]:
		return Result.failure("engine_b range origin providers 不符合预期: %s" % str(RangeOriginRegistryClass.get_provider_ids()))
	if EmployeePoolPatchRegistryClass.get_patch_ids() != ["extra_luxury_manager"]:
		return Result.failure("engine_b employee pool patches 不符合预期: %s" % str(EmployeePoolPatchRegistryClass.get_patch_ids()))
	if DinnertimeRoutePurchaseRegistryClass.get_provider_ids() != ["coffee:route:coffee"]:
		return Result.failure("engine_b dinnertime route purchase providers 不符合预期: %s" % str(DinnertimeRoutePurchaseRegistryClass.get_provider_ids()))
	if DinnertimeDemandRegistryClass.get_provider_ids() != ["sushi:demand_variants"]:
		return Result.failure("engine_b dinnertime demand providers 不符合预期: %s" % str(DinnertimeDemandRegistryClass.get_provider_ids()))
	if StateSchemaRegistryClass.get_schema_ids() != [
		"base_rules:round_state_int_keys:restructuring.submitted",
		"coffee:round_state_int_keys:coffee_shop_triggers_used",
		"lobbyists:round_state_int_keys:lobbyists_extra_tile_pending",
		"new_milestones:round_state_int_keys:new_milestones_brand_manager_airplane_pending",
		"new_milestones:round_state_int_keys:new_milestones_brand_manager_airplane_used_this_turn",
		"new_milestones:round_state_int_keys:new_milestones_campaign_manager_pending",
		"new_milestones:round_state_int_keys:new_milestones_campaign_manager_used_this_turn",
		"rural_marketeers:round_state_int_keys:rural_marketeers_offramp_pending",
	]:
		return Result.failure("engine_b state schema ids 不符合预期: %s" % str(StateSchemaRegistryClass.get_schema_ids()))
	if MilestoneEffectRegistryClass.get_current() != engine_b.ruleset_v2.milestone_effect_registry:
		return Result.failure("engine_b 激活后应切换 milestone effect registry")

	engine_a.activate_registry_bundles()
	if PieceRegistryClass.has("lobbyists_road_straight"):
		return Result.failure("切回 engine_a 后不应残留 lobbyists piece")
	if EmployeeRegistryClass.has("lobbyist"):
		return Result.failure("切回 engine_a 后不应残留 lobbyists employee")
	if MilestoneRegistryClass.has("first_marketeer_used"):
		return Result.failure("切回 engine_a 后不应残留 new_milestones milestone")
	if not ProductRegistryClass.has("soda"):
		return Result.failure("切回 engine_a 后 base product 仍应可见")
	if MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("切回 engine_a 后不应残留 gourmet_guide marketing type")
	if BankruptcyRegistryClass.has_first_break_handler():
		return Result.failure("切回 engine_a 后不应残留 reserve_prices bankruptcy handler")
	if BankruptcyRegistryClass.get_first_break_source() != "builtin":
		return Result.failure("切回 engine_a 后 bankruptcy source 应恢复 builtin")
	if not MarketingInitiationRegistryClass.get_provider_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 new_milestones marketing initiation providers")
	if not PlacementConflictRegistryClass.get_provider_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 rural_marketeers placement conflict providers")
	if not RangeOriginRegistryClass.get_provider_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 coffee range origin providers")
	if not EmployeePoolPatchRegistryClass.get_patch_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 employee pool patches")
	if not DinnertimeRoutePurchaseRegistryClass.get_provider_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 dinnertime route purchase providers")
	if not DinnertimeDemandRegistryClass.get_provider_ids().is_empty():
		return Result.failure("切回 engine_a 后不应残留 dinnertime demand providers")
	if StateSchemaRegistryClass.get_schema_ids() != ["base_rules:round_state_int_keys:restructuring.submitted"]:
		return Result.failure("切回 engine_a 后 state schema ids 不符合预期: %s" % str(StateSchemaRegistryClass.get_schema_ids()))
	if MilestoneEffectRegistryClass.get_current() != engine_a.ruleset_v2.milestone_effect_registry:
		return Result.failure("切回 engine_a 后应恢复其 milestone effect registry")

	engine_a.dispose()
	engine_b.activate_registry_bundles()
	if not PieceRegistryClass.has("lobbyists_road_straight"):
		return Result.failure("engine_a dispose 后，engine_b bundle 不应被清空")
	if not MarketingTypeRegistryClass.has_type("gourmet_guide"):
		return Result.failure("engine_a dispose 后，engine_b marketing type bundle 不应被清空")
	if not BankruptcyRegistryClass.has_first_break_handler() or BankruptcyRegistryClass.get_first_break_source() != "reserve_prices":
		return Result.failure("engine_a dispose 后，engine_b bankruptcy bundle 不应被清空")
	if MarketingInitiationRegistryClass.get_provider_ids().size() != 3:
		return Result.failure("engine_a dispose 后，engine_b marketing initiation bundle 不应被清空")
	if PlacementConflictRegistryClass.get_provider_ids() != ["rural_marketeers:placement_conflicts"]:
		return Result.failure("engine_a dispose 后，engine_b placement conflict bundle 不应被清空")
	if RangeOriginRegistryClass.get_provider_ids() != ["coffee:range_origins:coffee_shops"]:
		return Result.failure("engine_a dispose 后，engine_b range origin bundle 不应被清空")
	if EmployeePoolPatchRegistryClass.get_patch_ids() != ["extra_luxury_manager"]:
		return Result.failure("engine_a dispose 后，engine_b employee pool patch bundle 不应被清空")
	if DinnertimeRoutePurchaseRegistryClass.get_provider_ids() != ["coffee:route:coffee"]:
		return Result.failure("engine_a dispose 后，engine_b dinnertime route purchase bundle 不应被清空")
	if DinnertimeDemandRegistryClass.get_provider_ids() != ["sushi:demand_variants"]:
		return Result.failure("engine_a dispose 后，engine_b dinnertime demand bundle 不应被清空")
	if StateSchemaRegistryClass.get_schema_ids() != [
		"base_rules:round_state_int_keys:restructuring.submitted",
		"coffee:round_state_int_keys:coffee_shop_triggers_used",
		"lobbyists:round_state_int_keys:lobbyists_extra_tile_pending",
		"new_milestones:round_state_int_keys:new_milestones_brand_manager_airplane_pending",
		"new_milestones:round_state_int_keys:new_milestones_brand_manager_airplane_used_this_turn",
		"new_milestones:round_state_int_keys:new_milestones_campaign_manager_pending",
		"new_milestones:round_state_int_keys:new_milestones_campaign_manager_used_this_turn",
		"rural_marketeers:round_state_int_keys:rural_marketeers_offramp_pending",
	]:
		return Result.failure("engine_a dispose 后，engine_b state schema bundle 不应被清空: %s" % str(StateSchemaRegistryClass.get_schema_ids()))
	if MilestoneEffectRegistryClass.get_current() != engine_b.ruleset_v2.milestone_effect_registry:
		return Result.failure("engine_a dispose 后，engine_b 重新激活应恢复其 milestone effect registry")
	var engine_b_piece_count := PieceRegistryClass.get_count()

	engine_b.dispose()
	return Result.success({
		"engine_b_pieces": engine_b_piece_count,
		"engine_b_has_lobbyists": true,
		"engine_b_has_gourmet_guide": true,
		"engine_b_has_reserve_prices_bankruptcy": true,
		"engine_b_marketing_initiation_providers": 3,
		"engine_b_placement_conflict_providers": 1,
		"engine_b_range_origin_providers": 1,
		"engine_b_employee_pool_patches": 1,
		"engine_b_dinnertime_route_purchase_providers": 1,
		"engine_b_dinnertime_demand_providers": 1,
		"engine_b_state_schema_ids": 8,
		"milestone_effect_registry_switched": true,
	})
