# MarketingSettlement Fail-Fast 测试（M4）
# 覆盖：营销实例结构字段缺失/非法时必须直接失败（不允许静默降级/默认值兜底）。
class_name MarketingSettlementFailFastTest
extends RefCounted

const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")

	var placements: Dictionary = state.map["marketing_placements"]
	var pm := PhaseManagerClass.new()
	pm.set_effect_registry(EffectRegistryClass.new())

	# Case 1: 缺少 board_number -> 直接失败
	state.marketing_instances.clear()
	placements.clear()
	state.marketing_instances.append({
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketer",
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	})
	var r1 := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r1.ok:
		return Result.failure("缺少 board_number 的 marketing_instance 应失败")
	if str(r1.error).find("board_number") < 0:
		return Result.failure("错误信息应包含 board_number，实际: %s" % str(r1.error))

	# Case 2: 使用已移除 board_number -> 直接失败（不允许跳过效果继续结算）
	state.marketing_instances.clear()
	placements.clear()
	state.marketing_instances.append({
		"board_number": 12, # 2 人局被移除
	})
	var r2 := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r2.ok:
		return Result.failure("使用已移除 board_number 的 marketing_instance 应失败")
	if str(r2.error).find("移除") < 0:
		return Result.failure("错误信息应包含'移除'，实际: %s" % str(r2.error))

	# Case 3: 未知 marketing type -> 由 MarketingRangeCalculator 返回失败
	state.marketing_instances.clear()
	placements.clear()
	state.marketing_instances.append({
		"board_number": 1,
		"type": "unknown_type",
		"owner": 0,
		"employee_type": "marketer",
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	})
	placements["1"] = {"board_number": 1}
	var r3 := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r3.ok:
		return Result.failure("未知 marketing type 应失败")
	if str(r3.error).find("未知") < 0:
		return Result.failure("错误信息应包含'未知'，实际: %s" % str(r3.error))

	return Result.success({
		"cases": 3,
	})
