# MarketingSettlement Fail-Fast 测试（M4）
# 覆盖：营销实例结构字段缺失/非法时必须直接失败（不允许静默降级/默认值兜底）。
class_name MarketingSettlementFailFastTest
extends RefCounted

const MarketingSettlementClass = preload("res://modules/base_rules/rules/phase/marketing_settlement.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"
const ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY := "online_marketing_confirmed_players"

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
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
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

	# Case 3: 未知 board_number -> 直接失败
	state.marketing_instances.clear()
	placements.clear()
	state.marketing_instances.append({
		"board_number": 9999,
	})
	var r4 := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r4.ok:
		return Result.failure("使用未知 board_number 的 marketing_instance 应失败")
	if str(r4.error).find("未知") < 0:
		return Result.failure("错误信息应包含'未知'，实际: %s" % str(r4.error))

	# Case 4: 未知 marketing type -> 由 MarketingRangeCalculator 返回失败
	state.marketing_instances.clear()
	placements.clear()
	state.marketing_instances.append({
		"board_number": 1,
		"type": "unknown_type",
		"owner": 0,
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	})
	placements["1"] = {
		"board_number": 1,
		"type": "unknown_type",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}
	var r3 := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r3.ok:
		return Result.failure("未知 marketing type 应失败")
	if str(r3.error).find("未知") < 0:
		return Result.failure("错误信息应包含'未知'，实际: %s" % str(r3.error))

	var online_confirm_r := _test_online_confirmed_players_fail_fast(player_count, seed_val)
	if not online_confirm_r.ok:
		return online_confirm_r

	var milestone_r := _test_milestone_failure_is_fatal(player_count, seed_val)
	if not milestone_r.ok:
		return milestone_r

	return Result.success({
		"cases": 6,
	})

static func _test_milestone_failure_is_fatal(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化 milestone fail-fast 测试失败: %s" % init.error)
	var state := engine.get_state()
	state.map = _build_single_house_radio_map()
	state.marketing_instances.clear()
	state.marketing_instances.append({
		"board_number": 1,
		"type": "radio",
		"owner": 0,
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(2, 2),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	})
	var placements: Dictionary = state.map["marketing_placements"]
	placements["1"] = {
		"board_number": 1,
		"type": "radio",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(2, 2),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}

	var pm := PhaseManagerClass.new()
	pm.set_effect_registry(EffectRegistryClass.new())
	MilestoneEffectRegistryClass.reset_current()
	var r := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	engine.activate_registry_bundles()

	if r.ok:
		return Result.failure("DemandMarked 里程碑触发失败时不应降级为 warning")
	if str(r.error).find("DemandMarked") < 0:
		return Result.failure("错误信息应包含 DemandMarked，实际: %s" % r.error)
	if state.round_state.has("marketing"):
		return Result.failure("里程碑触发失败时不应写入 round_state.marketing")

	return Result.success()

static func _build_single_house_radio_map() -> Dictionary:
	var grid_size := Vector2i(5, 5)
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		cells.append(row)

	var house_pos := Vector2i(0, 0)
	cells[house_pos.y][house_pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": "h0",
		"house_number": 1,
		"has_garden": false,
		"dynamic": true,
	}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h0": {
				"house_id": "h0",
				"house_number": 1,
				"anchor_pos": house_pos,
				"cells": [house_pos],
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": [],
			},
		},
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {},
	}

static func _test_online_confirmed_players_fail_fast(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化 online confirmed_players 测试失败: %s" % init.error)
	var state := engine.get_state()
	if not (state.map is Dictionary):
		return Result.failure("online confirmed_players 测试 state.map 类型错误")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("online confirmed_players 测试缺少 marketing_placements")
	if not (state.rules is Dictionary):
		state.rules = {}
	state.rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
	state.round_state[ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY] = [false, {}]
	state.marketing_instances.clear()
	state.marketing_instances.append({
		"board_number": 1,
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	})
	var placements: Dictionary = state.map["marketing_placements"]
	placements.clear()
	placements["1"] = {
		"board_number": 1,
		"type": "billboard",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(0, 0),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}
	var confirmed_before := str(state.round_state.get(ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, null))

	var pm := PhaseManagerClass.new()
	pm.set_effect_registry(EffectRegistryClass.new())
	var r := MarketingSettlementClass.apply(state, pm.get_marketing_range_calculator(), 1, pm)
	if r.ok:
		return Result.failure("非法 online_marketing_confirmed_players 应导致营销结算失败")
	if str(r.error).find(ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, r.error])
	if str(state.round_state.get(ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, null)) != confirmed_before:
		return Result.failure("失败时不应重建或覆盖 online_marketing_confirmed_players")

	return Result.success()
