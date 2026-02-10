# 模块系统 V2：EffectUiTextRegistry（模块可注册 UI 文案，避免核心 UI 写死 optional 模块字符串）
class_name EffectUiTextRegistryTest
extends RefCounted

const EffectUiTextRegistryClass = preload("res://core/rules/effect_ui_text_registry.gd")

static func run(seed_val: int = 12345) -> Result:
	var r1 := _test_base_milestones_bundle(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_new_milestones_bundle(seed_val)
	if not r2.ok:
		return r2

	return Result.success()

static func _test_base_milestones_bundle(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
		"lobbyists",
		"rural_marketeers",
	])
	if not init.ok:
		return Result.failure("初始化失败（base_milestones bundle）: %s" % init.error)

	var t1 := EffectUiTextRegistryClass.get_effect_id_text("ketchup_mechanism:dinnertime:distance_delta:ketchup")
	if t1.is_empty():
		return Result.failure("ketchup_mechanism effect_id UI 文案未注册")

	var t2 := EffectUiTextRegistryClass.get_milestone_effect_type_text("ketchup_active")
	if t2.is_empty():
		return Result.failure("ketchup_active milestone effect UI 文案未注册")

	var t3 := EffectUiTextRegistryClass.get_milestone_effect_type_text("lobbyists_grant_extra_map_tile")
	if t3.is_empty():
		return Result.failure("lobbyists_grant_extra_map_tile milestone effect UI 文案未注册")

	var t4 := EffectUiTextRegistryClass.get_milestone_effect_type_text("rural_marketeers:grant_offramp_placement")
	if t4.is_empty():
		return Result.failure("rural_marketeers:grant_offramp_placement milestone effect UI 文案未注册")

	return Result.success()

static func _test_new_milestones_bundle(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"new_milestones",
	])
	if not init.ok:
		return Result.failure("初始化失败（new_milestones bundle）: %s" % init.error)

	var t1 := EffectUiTextRegistryClass.get_effect_id_text("new_milestones:dinnertime:distance_delta:first_marketeer_used")
	if t1.is_empty():
		return Result.failure("new_milestones effect_id 文案未注册: distance_delta:first_marketeer_used")

	var t2 := EffectUiTextRegistryClass.get_effect_id_text("new_milestones:marketing:demand_cash:first_marketeer_used")
	if t2.is_empty():
		return Result.failure("new_milestones effect_id 文案未注册: demand_cash:first_marketeer_used")

	return Result.success()
