# 模块11：夜班经理（Night Shift Managers）
# - 在岗夜班经理：无薪员工工作两次（CEO 排除，不叠加）
class_name NightShiftManagersV2Test
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const MarketingSettlementClass = preload("res://modules/base_rules/rules/phase/marketing_settlement.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const BaseRulesEffectsScript = preload("res://modules/base_rules/rules/effects.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_recruit_limit_doubled(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_nsm_entry_level_and_pool(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_marketing_trainee_can_initiate_twice(seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_waitress_effects_doubled_by_working_multiplier(seed_val)
	if not r4.ok:
		return r4

	var r5 := _test_nsm_cannot_be_subordinate(seed_val)
	if not r5.ok:
		return r5

	return Result.success()

static func _test_recruit_limit_doubled(seed_val: int) -> Result:
	# 对照组：未启用 night_shift_managers -> limit = ceo(1) + recruiting_girl(1) = 2
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var s0 := e0.get_state()
	_force_player0_ready_for_working(s0)
	_take_to_active(s0, 0, "recruiting_girl")

	var base_limit := EmployeeRulesClass.get_recruit_limit_for_working(s0, 0)
	if base_limit != 2:
		return Result.failure("未启用 night_shift_managers 时招聘上限应为 2，实际: %d" % base_limit)

	# 实验组：启用 night_shift_managers -> limit = ceo(1) + recruiting_girl(1*2) = 3（CEO 排除夜班）
	var e1 := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"night_shift_managers",
	]
	var init1 := e1.initialize(2, seed_val, enabled_modules)
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var s1 := e1.get_state()
	_force_player0_ready_for_working(s1)
	_take_to_active(s1, 0, "night_shift_manager")
	_take_to_active(s1, 0, "recruiting_girl")

	# 触发进入 Working（执行 phase hooks）
	var adv := e1.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("推进到 Working 失败: %s" % adv.error)

	s1 = e1.get_state()
	if s1.phase != DefsClass.PHASE_WORKING:
		return Result.failure("当前应为 Working，实际: %s" % s1.phase)

	var limit := EmployeeRulesClass.get_recruit_limit_for_working(s1, 0)
	if limit != 3:
		return Result.failure("启用 night_shift_managers 时招聘上限应为 3，实际: %d" % limit)

	# 校验 multipliers：recruiting_girl=2，ceo 不应被设置
	var wem_val = s1.round_state.get("working_employee_multipliers", null)
	if not (wem_val is Dictionary):
		return Result.failure("working_employee_multipliers 缺失或类型错误（期望 Dictionary）")
	var wem: Dictionary = wem_val
	if not wem.has(0):
		return Result.failure("working_employee_multipliers 缺少 player 0")
	var per_val = wem.get(0, null)
	if not (per_val is Dictionary):
		return Result.failure("working_employee_multipliers[0] 类型错误（期望 Dictionary）")
	var per: Dictionary = per_val
	if int(per.get("recruiting_girl", 0)) != 2:
		return Result.failure("recruiting_girl multiplier 应为 2，实际: %s" % str(per.get("recruiting_girl", null)))
	if per.has("ceo"):
		return Result.failure("CEO 不参与夜班，working_employee_multipliers 不应包含 ceo")

	return Result.success()

static func _test_nsm_entry_level_and_pool(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"night_shift_managers",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()

	if not EmployeeRulesClass.is_entry_level("night_shift_manager"):
		return Result.failure("night_shift_manager 应为可直接招聘的入门级员工（tags.entry_level 缺失？）")

	var one_x := int(state.rules.get("one_x_employee_copies", -1))
	if one_x <= 0:
		return Result.failure("state.rules.one_x_employee_copies 无效: %d" % one_x)
	var pool_val = state.employee_pool.get("night_shift_manager", null)
	if not (pool_val is int):
		return Result.failure("employee_pool.night_shift_manager 缺失或类型错误（期望 int）")
	var pool_count: int = int(pool_val)
	if pool_count != one_x:
		return Result.failure("night_shift_manager 为 1x 员工：2p 下应为 %d，实际: %d" % [one_x, pool_count])

	return Result.success()

static func _test_marketing_trainee_can_initiate_twice(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"night_shift_managers",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_player0_ready_for_working(state)
	_apply_marketing_test_map(state)

	# 玩家0 在岗：night_shift_manager + marketing_trainee
	_take_to_active(state, 0, "night_shift_manager")
	_take_to_active(state, 0, "marketing_trainee")

	# 触发进入 Working（执行 phase hooks 写入 multipliers）
	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("推进到 Working 失败: %s" % adv.error)
	state = engine.get_state()
	if state.phase != DefsClass.PHASE_WORKING:
		return Result.failure("当前应为 Working，实际: %s" % state.phase)

	# 直接进入 Marketing 子阶段（本测试关注营销动作本身）
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING

	# 第一次：发起 billboard #13（duration=1）
	var cmd1 := Command.create("initiate_marketing", 0, {
		"employee_type": "marketing_trainee",
		"board_number": 13,
		"product": "burger",
		"duration": 1,
		"position": [1, 0],
		"rotation": 90,
	})
	var r1 := engine.execute_command(cmd1)
	if not r1.ok:
		return Result.failure("initiate_marketing(1) 失败: %s" % r1.error)

	# 第二次（夜班）：应仍可用同一名营销实习生发起 billboard #14（duration=2）
	var cmd2 := Command.create("initiate_marketing", 0, {
		"employee_type": "marketing_trainee",
		"board_number": 14,
		"product": "burger",
		"duration": 2,
		"position": [3, 1],
		"rotation": 0,
	})
	var r2 := engine.execute_command(cmd2)
	if not r2.ok:
		return Result.failure("initiate_marketing(2) 失败: %s" % r2.error)

	state = engine.get_state()
	var busy_val = state.players[0].get("busy_marketers", null)
	if not (busy_val is Array):
		return Result.failure("player[0].busy_marketers 类型错误（期望 Array）")
	var busy: Array = busy_val
	var busy_count := 0
	for b in busy:
		if b is String and str(b) == "marketing_trainee":
			busy_count += 1
	if busy_count != 1:
		return Result.failure("营销实习生应仅有 1 张卡处于忙碌（双 busy marker），实际 busy_marketers 中数量: %d (%s)" % [busy_count, str(busy)])

	if Array(state.players[0].get("employees", [])).has("marketing_trainee"):
		return Result.failure("营销实习生发起营销后应离开在岗区（已进入忙碌区）")

	# 两个实例应共享 link_id（避免第一张到期后提前释放忙碌营销员）
	var link := ""
	var link2 := ""
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		var bn := int(inst.get("board_number", -1))
		if bn == 13:
			link = str(inst.get("link_id", "")).strip_edges()
		if bn == 14:
			link2 = str(inst.get("link_id", "")).strip_edges()
	if link.is_empty() or link2.is_empty() or link2 != link:
		return Result.failure("营销实习生的两次 billboard 应共享同一 link_id（用于延迟释放），实际: #%d=%s #%d=%s" % [13, link, 14, link2])

	# Marketing 结算：#13 到期但 #14 仍在，忙碌营销员不应释放
	var mk1 := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk1.ok:
		return Result.failure("MarketingSettlement(1) 失败: %s" % mk1.error)
	if not Array(state.players[0].get("busy_marketers", [])).has("marketing_trainee"):
		return Result.failure("仅一张 billboard 到期时不应释放营销实习生（仍有活动在运行）")

	# 再结算一轮：#14 到期后应释放回 reserve_employees
	var mk2 := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk2.ok:
		return Result.failure("MarketingSettlement(2) 失败: %s" % mk2.error)
	if Array(state.players[0].get("busy_marketers", [])).has("marketing_trainee"):
		return Result.failure("两张 billboard 到期后，营销实习生不应仍在 busy_marketers")
	if not Array(state.players[0].get("reserve_employees", [])).has("marketing_trainee"):
		return Result.failure("两张 billboard 到期后，营销实习生应回到 reserve_employees")

	return Result.success()

static func _test_waitress_effects_doubled_by_working_multiplier(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()

	# 在岗 1 张 waitress，并手动注入“工作乘数=2”（模拟夜班效果）。
	_take_to_active(state, 0, "waitress")
	state.round_state["working_employee_multipliers"] = {0: {"waitress": 2}}

	var reg := EffectRegistryClass.new()
	var effects = BaseRulesEffectsScript.new()
	var rr := effects.register(reg)
	if not rr.ok:
		return Result.failure("注册 base_rules effects 失败: %s" % rr.error)

	var ctx_tips := {"tips": 0, "use_employee_triggered": true}
	var tips_r := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, 0, reg, "dinnertime:tips", ctx_tips)
	if not tips_r.ok:
		return Result.failure("DinnertimeEffects.tips 失败: %s" % tips_r.error)
	if int(ctx_tips.get("tips", -1)) != 6:
		return Result.failure("女服务员应按乘数 2 结算小费：期望 6(3*2)，实际: %s" % str(ctx_tips.get("tips", null)))

	var ctx_tb := {"score": 0}
	var tb_r := DinnertimeEffectsClass.apply_employee_effects_by_segment(state, 0, reg, "dinnertime:tiebreaker", ctx_tb)
	if not tb_r.ok:
		return Result.failure("DinnertimeEffects.tiebreaker 失败: %s" % tb_r.error)
	if int(ctx_tb.get("score", -1)) != 2:
		return Result.failure("女服务员应按乘数 2 参与平局：期望 2(1*2)，实际: %s" % str(ctx_tb.get("score", null)))

	return Result.success()

static func _test_nsm_cannot_be_subordinate(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"night_shift_managers",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()

	# 进入 Restructuring，准备 company_structure.structure
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""
	state.round_state["restructuring"] = {"submitted": {0: false, 1: false}}
	state.turn_order = [0, 1]
	state.current_player_index = 0

	# 玩家0：在岗 management_trainee（作为目标经理）；待命 night_shift_manager（试图作为下属）
	state.players[0]["company_structure"]["ceo_slots"] = 3
	state.players[0]["company_structure"]["structure"] = [
		{"employee_id": "management_trainee", "reports": []},
		{"employee_id": "", "reports": []},
		{"employee_id": "", "reports": []},
	]
	_take_to_active(state, 0, "management_trainee")
	_take_to_reserve(state, 0, "night_shift_manager")

	var cmd := Command.create("set_company_structure_report", 0, {
		"manager_slot_index": 0,
		"employee_id": "night_shift_manager",
	})
	var r := engine.execute_command(cmd)
	if r.ok:
		return Result.failure("夜班经理为经理卡（role=manager），不应允许作为下属分配到经理 reports 下")

	return Result.success()

static func _force_player0_ready_for_working(state: GameState) -> void:
	state.phase = DefsClass.PHASE_ORDER_OF_BUSINESS
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_state["order_of_business"] = {
		"previous_turn_order": [0, 1],
		"selection_order": [0, 1],
		"picks": [-1, -1],
		"finalized": true
	}
	state.players[0]["company_structure"]["ceo_slots"] = 20

static func _take_to_active(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	state.players[player_id]["employees"].append(employee_id)

static func _take_to_reserve(state: GameState, player_id: int, employee_id: String) -> void:
	if not state.employee_pool.has(employee_id):
		state.employee_pool[employee_id] = 0
	state.employee_pool[employee_id] = int(state.employee_pool.get(employee_id, 0)) - 1
	state.players[player_id]["reserve_employees"].append(employee_id)

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)
	return cells

static func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_marketing_test_map(state: GameState) -> void:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# x=2 为纵向道路（给左右两侧提供“邻接道路”的空地）
	_set_road_segment(cells, Vector2i(2, 0), ["S"])
	_set_road_segment(cells, Vector2i(2, 1), ["N", "S"])
	_set_road_segment(cells, Vector2i(2, 2), ["N", "S"])
	_set_road_segment(cells, Vector2i(2, 3), ["N", "S"])
	_set_road_segment(cells, Vector2i(2, 4), ["N"])

	# 餐厅在底部 2x2，并有入口邻接道路
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(1, 3),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	RoadGraphCacheClass.invalidate_road_graph(state)
