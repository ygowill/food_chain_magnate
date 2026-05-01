# 晚餐结算测试（M4）
# 覆盖：距离/库存候选过滤/平局链路（女服务员/回合顺序）/花园翻倍与营销奖励/女服务员与 CFO 加成
class_name DinnertimeSettlementTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const BaseRulesEffectsClass = preload("res://modules/base_rules/rules/effects.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const REQUIRE_DINNERTIME_CONFIRM_KEY := "require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	EmployeeRegistryClass.reset()

	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_distance_winner(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_inventory_filter(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_waitress_tiebreak(seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_garden_does_not_affect_decision(seed_val)
	if not r4.ok:
		return r4

	var r5 := _test_turn_order_tiebreak(seed_val)
	if not r5.ok:
		return r5

	var r6 := _test_garden_bonus_tips_cfo(seed_val)
	if not r6.ok:
		return r6

	var r7 := _test_online_confirmed_players_fail_fast(seed_val)
	if not r7.ok:
		return r7

	var r8 := _test_waitress_milestone_failure_is_fatal(seed_val)
	if not r8.ok:
		return r8

	var r9 := _test_local_confirm_marker_injects_explicit_pending(seed_val)
	if not r9.ok:
		return r9

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"cases": 9,
	})

static func _test_local_confirm_marker_injects_explicit_pending(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化本地确认 marker 测试失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 1
	state.rules[REQUIRE_DINNERTIME_CONFIRM_KEY] = true

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv
	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("显式本地晚餐确认 marker 应阻塞在 Dinnertime，实际: %s" % str(state.phase))
	var ppa: Dictionary = state.round_state.get("pending_phase_actions", {})
	var pending_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (pending_val is Array):
		return Result.failure("本地晚餐确认 pending 缺失")
	var pending: Array = pending_val
	if pending.size() != 1 or not (pending[0] is Dictionary):
		return Result.failure("本地晚餐确认 pending 应为单个 Dictionary，实际: %s" % str(pending))
	var item: Dictionary = pending[0]
	if str(item.get("kind", "")) != "confirm_dinnertime" or int(item.get("player_id", -1)) != 0:
		return Result.failure("本地晚餐确认 pending 内容错误: %s" % str(item))
	return Result.success()

static func _test_waitress_milestone_failure_is_fatal(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	var effects = BaseRulesEffectsClass.new()
	var ctx := {
		"tips": 0,
		"use_employee_triggered": false,
	}

	MilestoneEffectRegistryClass.reset_current()
	var r: Result = effects._effect_dinnertime_tips_waitress(state, 0, ctx)
	engine.activate_registry_bundles()

	if r.ok:
		return Result.failure("UseEmployee/waitress 里程碑触发失败时不应降级为 warning")
	if str(r.error).find("UseEmployee/waitress") < 0:
		return Result.failure("错误信息应包含 UseEmployee/waitress，实际: %s" % r.error)
	if bool(ctx.get("use_employee_triggered", false)):
		return Result.failure("里程碑触发失败时不应标记 use_employee_triggered")

	return Result.success()

static func _test_distance_winner(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 两个房屋分别需求不同产品，且双方库存充足：由距离决定赢家
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [{"product": "pizza"}])

	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["pizza"] = 1
	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["pizza"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != DefsClass.PHASE_PAYDAY:
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	if int(state.players[0].get("cash", 0)) != 10:
		return Result.failure("玩家0 现金应为 10（赢左侧房屋），实际: %d" % int(state.players[0].get("cash", 0)))
	if int(state.players[1].get("cash", 0)) != 10:
		return Result.failure("玩家1 现金应为 10（赢右侧房屋），实际: %d" % int(state.players[1].get("cash", 0)))

	var left: Dictionary = state.map.get("houses", {}).get("house_left", {})
	var right: Dictionary = state.map.get("houses", {}).get("house_right", {})
	if not (left.get("demands", []) is Array) or left.get("demands", []).size() != 0:
		return Result.failure("左侧房屋需求应被清空，实际: %s" % str(left.get("demands", null)))
	if not (right.get("demands", []) is Array) or right.get("demands", []).size() != 0:
		return Result.failure("右侧房屋需求应被清空，实际: %s" % str(right.get("demands", null)))

	return Result.success()

static func _test_online_confirmed_players_fail_fast(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 1
	if not (state.rules is Dictionary):
		state.rules = {}
	state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
	state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = [false, {}]
	var confirmed_before := str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null))

	var adv := _advance_to_dinnertime(engine)
	if adv.ok:
		return Result.failure("非法 online_dinnertime_confirmed_players 应导致晚餐结算失败")
	if str(adv.error).find(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY) < 0:
		return Result.failure("错误信息应包含 %s，实际: %s" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, adv.error])
	if str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)) != confirmed_before:
		return Result.failure("失败时不应重建或覆盖 online_dinnertime_confirmed_players")

	return Result.success()

static func _test_inventory_filter(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if int(state.players[1].get("cash", 0)) != 10:
		return Result.failure("库存不足应导致玩家1 胜出并获得 10，实际: %d" % int(state.players[1].get("cash", 0)))

	return Result.success()

static func _test_garden_does_not_affect_decision(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 规则对齐 docs/rules.md：
	# - 胜负判定用“单价 + 距离”，花园不影响单价，仅影响收入
	# - 本用例：花园房屋，score 平局应进入女服务员平局链路
	_set_house_garden(state, "house_left", true)
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 1

	# 让 score 平局：左房 distance(p0)=0, distance(p1)=1
	# p0 单价 11, p1 单价 10 -> score 都为 11
	state.round_state["price_modifiers"] = {
		0: {"test": 1},
		1: {"test": 0},
	}

	# 平局链路：女服务员数量更多者胜（玩家0 1 张女服务员）
	if int(state.employee_pool.get("waitress", 0)) <= 0:
		return Result.failure("员工池中没有 waitress")
	state.employee_pool["waitress"] = int(state.employee_pool.get("waitress", 0)) - 1
	state.players[0]["employees"].append("waitress")

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()

	# 花园仅影响收入：单价 11，数量 1 => 单价部分翻倍为 22；
	# 首个使用女服务员会自动获得里程碑（小费 5）=> 合计 27
	if int(state.players[0].get("cash", 0)) != 27:
		return Result.failure("花园不应影响选店，女服务员平局应使玩家0 获得 27，实际: %d" % int(state.players[0].get("cash", 0)))

	return Result.success()

static func _test_waitress_tiebreak(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 1

	# 让 score 平局：左房 distance(p0)=0, distance(p1)=1
	# p0 单价 11, p1 单价 10 -> score 都为 11
	state.round_state["price_modifiers"] = {
		0: {"test": 1},
		1: {"test": 0},
	}

	# 平局链路：女服务员数量更多者胜（玩家0 1 张女服务员）
	if int(state.employee_pool.get("waitress", 0)) <= 0:
		return Result.failure("员工池中没有 waitress")
	state.employee_pool["waitress"] = int(state.employee_pool.get("waitress", 0)) - 1
	state.players[0]["employees"].append("waitress")

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	# 收入：售卖 1 个 burger，单价 11 => 11；
	# 首个使用女服务员会自动获得里程碑（小费 5）=> 合计 16
	if int(state.players[0].get("cash", 0)) != 16:
		return Result.failure("女服务员平局应使玩家0 胜出并获得 16，实际: %d" % int(state.players[0].get("cash", 0)))

	return Result.success()

static func _test_turn_order_tiebreak(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 1

	# score 平局：同上
	state.round_state["price_modifiers"] = {
		0: {"test": 1},
		1: {"test": 0},
	}

	# 平局链路：女服务员数量相同，则回合顺序靠前者胜（把玩家1 放到前面）
	state.turn_order = [1, 0]

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if int(state.players[1].get("cash", 0)) != 10:
		return Result.failure("回合顺序平局应使玩家1 胜出并获得 10，实际: %d" % int(state.players[1].get("cash", 0)))

	return Result.success()

static func _test_garden_bonus_tips_cfo(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 花园房屋：2 个汉堡需求
	_set_house_garden(state, "house_left", true)
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	# 让玩家0 唯一可服务
	state.players[0]["inventory"]["burger"] = 2
	state.players[1]["inventory"]["burger"] = 0

	# 里程碑：首个营销汉堡 -> 每卖出一个汉堡 +$5（不影响单价）
	var m1 := StateUpdaterClass.claim_milestone(state, 0, "first_burger_marketed")
	if not m1.ok:
		return Result.failure("claim_milestone first_burger_marketed 失败: %s" % m1.error)

	# 女服务员里程碑 + 在岗女服务员 1 张：小费应为 5（而非 3）
	var m2 := StateUpdaterClass.claim_milestone(state, 0, "first_waitress")
	if not m2.ok:
		return Result.failure("claim_milestone first_waitress 失败: %s" % m2.error)
	if int(state.employee_pool.get("waitress", 0)) <= 0:
		return Result.failure("员工池中没有 waitress")
	state.employee_pool["waitress"] = int(state.employee_pool.get("waitress", 0)) - 1
	state.players[0]["employees"].append("waitress")

	# CFO：收入 +50%（向上取整）
	if int(state.employee_pool.get("cfo", 0)) <= 0:
		return Result.failure("员工池中没有 cfo")
	state.employee_pool["cfo"] = int(state.employee_pool.get("cfo", 0)) - 1
	state.players[0]["employees"].append("cfo")

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()

	# 基础单价 10，数量 2 -> 20；花园翻倍单价部分 -> 40；营销汉堡奖励 2*5=10；收入=50
	# 女服务员里程碑：每位女服务员 5，小费=5 -> 小计=55
	# CFO：+50% 向上取整 => +ceil(55/2)=28，总计=83
	if int(state.players[0].get("cash", 0)) != 83:
		return Result.failure("花园/奖励/小费/CFO 结算应为 83，实际: %d" % int(state.players[0].get("cash", 0)))

	return Result.success()

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("推进到 Dinnertime 失败: %s" % adv.error)
	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0

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

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i], has_garden: bool) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": has_garden,
			"dynamic": true
		}

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i], entrance_pos: Vector2i) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)  # 2×1 板块（TILE_SIZE=5），用于测试跨板块距离
	var cells := _build_empty_cells(grid_size)

	# 水平道路 y=2，连接左右两块板
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var left_house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	var right_house_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells, false)
	_set_house(cells, "house_right", 2, right_house_cells, false)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells, Vector2i(0, 3))
	_set_restaurant(cells, "rest_1", 1, rest1_cells, Vector2i(9, 3))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": left_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
			"house_right": {
				"house_id": "house_right",
				"house_number": 2,
				"anchor_pos": Vector2i(8, 0),
				"cells": right_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 3,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	RoadGraphCacheClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses

static func _set_house_garden(state: GameState, house_id: String, has_garden: bool) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["has_garden"] = has_garden
	houses[house_id] = house
	state.map["houses"] = houses
