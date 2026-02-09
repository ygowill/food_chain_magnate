# 模块8：番茄酱机制（The Ketchup Mechanism）
# - “他人卖出你营销产生的需求” -> 晚餐结束时获得里程碑
# - 里程碑效果：晚餐选店使用 (unit_price + distance - 1)，可叠加且允许为负数
class_name KetchupMechanismV2Test
extends RefCounted

const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")
const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")

const MILESTONE_ID := "ketchup_sold_your_demand"
const EFFECT_ID := "ketchup_mechanism:dinnertime:distance_delta:ketchup"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var basic := _run_basic_award_and_distance(seed_val)
	if not basic.ok:
		return basic

	var multi := _run_multi_award(seed_val + 1)
	if not multi.ok:
		return multi

	var drink := _run_drink_only_award(seed_val + 2)
	if not drink.ok:
		return drink

	var timing := _run_award_timing(seed_val + 3)
	if not timing.ok:
		return timing

	var stack := _run_distance_stacking(seed_val + 4)
	if not stack.ok:
		return stack

	var pool := _run_pool_consumption(seed_val + 5)
	if not pool.ok:
		return pool

	return Result.success()

static func _run_basic_award_and_distance(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state, [0, 1])

	# 玩家0 的“营销需求”被玩家1 售出：player0 应在晚餐结算结束后获得里程碑
	_set_house_demands(state, "house_left", [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}])
	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != DefsClass.PHASE_PAYDAY:
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	# distance_delta handler：对齐 (unit_price + distance - 1)，并设置 allow_negative=true
	var effect_registry = engine.phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("EffectRegistry 未设置")
	var ctx0 := {"distance": 0, "allow_negative": false}
	var r0: Result = effect_registry.invoke(EFFECT_ID, [state, 0, ctx0])
	if not r0.ok:
		return r0
	if int(ctx0.get("distance", 999)) != -1:
		return Result.failure("distance=0 应变为 -1，实际: %s" % str(ctx0.get("distance", null)))
	if not bool(ctx0.get("allow_negative", false)):
		return Result.failure("ketchup effect 应设置 allow_negative=true，实际: %s" % str(ctx0.get("allow_negative", null)))
	var ctx2 := {"distance": 2, "allow_negative": false}
	var r2: Result = effect_registry.invoke(EFFECT_ID, [state, 0, ctx2])
	if not r2.ok:
		return r2
	if int(ctx2.get("distance", -1)) != 1:
		return Result.failure("distance=2 应变为 1，实际: %s" % str(ctx2.get("distance", null)))
	if not bool(ctx2.get("allow_negative", false)):
		return Result.failure("ketchup effect 应设置 allow_negative=true，实际: %s" % str(ctx2.get("allow_negative", null)))

	return Result.success()

static func _run_multi_award(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(3, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state, [0, 1, 2])

	# 同一房屋需求来自多个玩家：由玩家2 售出时，玩家0/1 都应在晚餐结束后获得里程碑
	_set_house_demands(state, "house_left", [
		{
			"product": "burger",
			"from_player": 0,
			"board_number": 11,
			"type": "billboard"
		},
		{
			"product": "burger",
			"from_player": 1,
			"board_number": 12,
			"type": "billboard"
		},
	])
	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 0
	state.players[2]["inventory"]["burger"] = 2

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != DefsClass.PHASE_PAYDAY:
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	var milestones0: Array = state.players[0].get("milestones", [])
	var milestones1: Array = state.players[1].get("milestones", [])
	var milestones2: Array = state.players[2].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])
	if not milestones1.has(MILESTONE_ID):
		return Result.failure("玩家1 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones1)])
	if milestones2.has(MILESTONE_ID):
		return Result.failure("玩家2（卖家）不应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones2)])

	return Result.success()

static func _run_drink_only_award(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state, [0, 1])

	# 规则书：ketchup 也对“仅饮品”订单生效
	_set_house_demands(state, "house_left", [{
		"product": "soda",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}])
	state.players[0]["inventory"]["soda"] = 0
	state.players[1]["inventory"]["soda"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("仅饮品订单也应触发里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])
	return Result.success()

static func _run_award_timing(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state, [0, 1])

	# 房屋1：玩家0 的需求被玩家1 售出 -> 玩家0 在晚餐结束后获得 ketchup milestone
	_set_house_demands(state, "house_left", [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}])
	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	# 房屋2：若 ketchup 在同一晚餐内即时生效，本应反转赢家；但规则书要求“晚餐结束后授予，不影响本次晚餐剩余结算”
	_set_house_demands(state, "house_right", [{
		"product": "pizza",
		"from_player": 1,
		"board_number": 12,
		"type": "mailbox"
	}])
	state.players[0]["inventory"]["pizza"] = 1
	state.players[1]["inventory"]["pizza"] = 1

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	var dt_val = state.round_state.get("dinnertime", null)
	if not (dt_val is Dictionary):
		return Result.failure("缺少 round_state.dinnertime")
	var dt: Dictionary = dt_val
	var sales_val = dt.get("sales", null)
	if not (sales_val is Array):
		return Result.failure("round_state.dinnertime.sales 类型错误（期望 Array）")
	var sales: Array = sales_val
	var right_sale: Dictionary = {}
	for s_val in sales:
		if s_val is Dictionary and str(Dictionary(s_val).get("house_id", "")) == "house_right":
			right_sale = Dictionary(s_val)
			break
	if right_sale.is_empty():
		return Result.failure("应存在 house_right 的售卖记录")
	if int(right_sale.get("winner_owner", -1)) != 1:
		return Result.failure("ketchup 不应影响同一晚餐后续房屋：house_right winner_owner 应为 1，实际: %s" % str(right_sale.get("winner_owner", null)))

	# 下一次晚餐：玩家0 已拥有 ketchup，应使 house_right 的胜者反转
	_set_house_demands(state, "house_right", [{
		"product": "pizza",
		"from_player": 1,
		"board_number": 12,
		"type": "mailbox"
	}])
	state.players[0]["inventory"]["pizza"] = 1
	state.players[1]["inventory"]["pizza"] = 1

	var adv2 := _advance_to_dinnertime(engine)
	if not adv2.ok:
		return adv2

	state = engine.get_state()
	dt_val = state.round_state.get("dinnertime", null)
	if not (dt_val is Dictionary):
		return Result.failure("缺少 round_state.dinnertime（第二次晚餐）")
	dt = dt_val
	sales_val = dt.get("sales", null)
	if not (sales_val is Array):
		return Result.failure("round_state.dinnertime.sales 类型错误（第二次晚餐）")
	sales = sales_val
	right_sale = {}
	for s_val2 in sales:
		if s_val2 is Dictionary and str(Dictionary(s_val2).get("house_id", "")) == "house_right":
			right_sale = Dictionary(s_val2)
			break
	if right_sale.is_empty():
		return Result.failure("第二次晚餐应存在 house_right 的售卖记录")
	if int(right_sale.get("winner_owner", -1)) != 0:
		return Result.failure("ketchup 应影响后续晚餐：house_right winner_owner 应为 0，实际: %s" % str(right_sale.get("winner_owner", null)))

	return Result.success()

static func _run_distance_stacking(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_marketing",
		"new_milestones",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)

	# 规则书：ketchup 距离修正可与 new_milestones 的 first_marketeer_used 叠加
	state.players[0]["milestones"] = [
		MILESTONE_ID,
		"first_marketeer_used",
	]

	var effect_registry = engine.phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("EffectRegistry 未设置")

	var ctx := {"distance": 0, "allow_negative": false}
	var r: Result = DinnertimeEffectsClass.apply_milestone_effects_by_segment(state, 0, effect_registry, ":dinnertime:distance_delta:", ctx)
	if not r.ok:
		return r
	if int(ctx.get("distance", 999)) != -3:
		return Result.failure("叠加距离修正应为 -3（0-1-2=-3），实际: %s" % str(ctx.get("distance", null)))
	if not bool(ctx.get("allow_negative", false)):
		return Result.failure("叠加修正后 allow_negative 应为 true")
	return Result.success()

static func _run_pool_consumption(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"ketchup_mechanism",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()

	var before := 0
	for mid in state.milestone_pool:
		if str(mid) == MILESTONE_ID:
			before += 1
	if before <= 1:
		return Result.failure("ketchup milestone supply 应包含多份拷贝（用于多人局/不同玩家），实际: %d" % before)

	var claim0 := StateUpdaterClass.claim_milestone(state, 0, MILESTONE_ID)
	if not claim0.ok:
		return claim0
	var cleanup0 := CleanupSettlementClass.apply_cleanup_milestones(state)
	if not cleanup0.ok:
		return cleanup0

	var after0 := 0
	for mid2 in state.milestone_pool:
		if str(mid2) == MILESTONE_ID:
			after0 += 1
	if after0 != before - 1:
		return Result.failure("Cleanup 应仅移除 1 份 ketchup milestone 拷贝（允许其他玩家后续获得），before=%d after=%d" % [before, after0])

	# 模拟下一回合：允许另一位玩家后续获得其 ketchup
	state.round_state["milestones_claimed"] = {}
	var claim1 := StateUpdaterClass.claim_milestone(state, 1, MILESTONE_ID)
	if not claim1.ok:
		return claim1
	var cleanup1 := CleanupSettlementClass.apply_cleanup_milestones(state)
	if not cleanup1.ok:
		return cleanup1
	var after1 := 0
	for mid3 in state.milestone_pool:
		if str(mid3) == MILESTONE_ID:
			after1 += 1
	if after1 != after0 - 1:
		return Result.failure("第二次 Cleanup 也应仅移除 1 份拷贝，after0=%d after1=%d" % [after0, after1])

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
	var order: Array[int] = []
	for pid in range(state.players.size()):
		order.append(pid)
	state.turn_order = order
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

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState, restaurant_owners: Array[int]) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

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
	_set_house(cells, "house_left", 1, left_house_cells)

	var right_house_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_house(cells, "house_right", 2, right_house_cells)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	var rest2_cells: Array[Vector2i] = [
		Vector2i(4, 3), Vector2i(5, 3),
		Vector2i(4, 4), Vector2i(5, 4),
	]
	var all_rest_cells: Array = [rest0_cells, rest1_cells, rest2_cells]

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
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	var restaurants: Dictionary = {}
	for i in range(restaurant_owners.size()):
		var owner: int = int(restaurant_owners[i])
		var rest_id := "rest_%d" % i
		var rest_cells: Array[Vector2i] = all_rest_cells[i]
		_set_restaurant(cells, rest_id, owner, rest_cells)

		var entrance_pos := rest_cells[0]
		if i == 1:
			entrance_pos = Vector2i(9, 3)

		restaurants[rest_id] = {
			"restaurant_id": rest_id,
			"owner": owner,
			"anchor_pos": rest_cells[0],
			"entrance_pos": entrance_pos,
			"cells": rest_cells,
		}
	state.map["restaurants"] = restaurants

	for pid in range(state.players.size()):
		state.players[pid]["restaurants"] = []
	for rest_id in restaurants.keys():
		var rest: Dictionary = restaurants[rest_id]
		var owner: int = int(rest.get("owner", -1))
		if owner >= 0 and owner < state.players.size():
			state.players[owner]["restaurants"].append(rest_id)

	RoadGraphCacheClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
