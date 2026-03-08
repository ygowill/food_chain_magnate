# Catalog registry bundle 隔离回归测试
class_name CatalogRegistryBundleIsolationTest
extends RefCounted

const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")

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
	if MilestoneEffectRegistryClass.get_current() != engine_a.ruleset_v2.milestone_effect_registry:
		return Result.failure("切回 engine_a 后应恢复其 milestone effect registry")

	engine_a.dispose()
	engine_b.activate_registry_bundles()
	if not PieceRegistryClass.has("lobbyists_road_straight"):
		return Result.failure("engine_a dispose 后，engine_b bundle 不应被清空")
	if MilestoneEffectRegistryClass.get_current() != engine_b.ruleset_v2.milestone_effect_registry:
		return Result.failure("engine_a dispose 后，engine_b 重新激活应恢复其 milestone effect registry")
	var engine_b_piece_count := PieceRegistryClass.get_count()

	engine_b.dispose()
	return Result.success({
		"engine_b_pieces": engine_b_piece_count,
		"engine_b_has_lobbyists": true,
		"milestone_effect_registry_switched": true,
	})
