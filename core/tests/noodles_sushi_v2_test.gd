# Noodles / Sushi（模块6/7）晚餐替代规则测试（V2）
class_name NoodlesSushiV2Test
extends RefCounted

const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_sushi_replaces_all_for_garden_house(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_sushi_production_then_replaces_all(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_sushi_insufficient_falls_back_to_base(seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_sushi_tiebreak_waitresses(seed_val)
	if not r4.ok:
		return r4

	var r5 := _test_noodles_only_when_base_unavailable(seed_val)
	if not r5.ok:
		return r5

	var r6 := _test_noodles_not_used_when_base_available(seed_val)
	if not r6.ok:
		return r6

	var r7 := _test_extra_luxury_manager_patch(seed_val)
	if not r7.ok:
		return r7

	return Result.success({
		"cases": 7,
		"seed": seed_val,
	})

static func _test_sushi_replaces_all_for_garden_house(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_garden(state, "house_left", true)

	# 花园房屋需求 2 个：若 sushi 足够，应优先用 sushi 完全替代
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	# 两边都能满足 base demand，但只有玩家0 有 sushi
	state.players[0]["inventory"]["burger"] = 2
	state.players[0]["inventory"]["soda"] = 2
	state.players[0]["inventory"]["sushi"] = 2

	state.players[1]["inventory"]["burger"] = 2
	state.players[1]["inventory"]["soda"] = 2
	state.players[1]["inventory"]["sushi"] = 0

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var cash0: int = int(state.players[0].get("cash", 0))
	# 花园翻倍“单价部分”：unit_price=10，quantity=2 => price_part=40
	if cash0 != 40:
		return Result.failure("寿司替代应使玩家0 获得 40，实际: %d" % cash0)
	if int(state.players[0]["inventory"].get("sushi", 0)) != 0:
		return Result.failure("寿司库存应被扣减至 0，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))
	if int(state.players[0]["inventory"].get("burger", 0)) != 2:
		return Result.failure("寿司替代不应消耗 burger，实际: %d" % int(state.players[0]["inventory"].get("burger", 0)))
	if int(state.players[0]["inventory"].get("soda", 0)) != 2:
		return Result.failure("寿司替代不应消耗 soda，实际: %d" % int(state.players[0]["inventory"].get("soda", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "sushi:replace_all":
		return Result.failure("demand_variant_id 应为 sushi:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_sushi_production_then_replaces_all(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_garden(state, "house_left", true)

	# 花园房屋需求 2 个：先生产 2 sushi，再用 sushi 完全替代
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 2
	state.players[0]["inventory"]["soda"] = 2
	state.players[0]["inventory"]["sushi"] = 0

	# 注入 1 张 sushi_cook（维持员工池守恒）
	if int(state.employee_pool.get("sushi_cook", 0)) <= 0:
		return Result.failure("员工池中没有 sushi_cook")
	state.employee_pool["sushi_cook"] = int(state.employee_pool.get("sushi_cook", 0)) - 1
	state.players[0]["employees"].append("sushi_cook")
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD

	var prod := e.execute_command(Command.create("produce_food", 0, {"employee_type": "sushi_cook"}))
	if not prod.ok:
		return Result.failure("produce_food(sushi_cook) 失败: %s" % prod.error)

	state = e.get_state()
	if int(state.players[0]["inventory"].get("sushi", 0)) != 2:
		return Result.failure("sushi_cook 应生产 2 sushi，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	if int(state.players[0]["inventory"].get("sushi", 0)) != 0:
		return Result.failure("寿司库存应被扣减至 0，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))
	if int(state.players[0]["inventory"].get("burger", 0)) != 2:
		return Result.failure("寿司替代不应消耗 burger，实际: %d" % int(state.players[0]["inventory"].get("burger", 0)))
	if int(state.players[0]["inventory"].get("soda", 0)) != 2:
		return Result.failure("寿司替代不应消耗 soda，实际: %d" % int(state.players[0]["inventory"].get("soda", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "sushi:replace_all":
		return Result.failure("demand_variant_id 应为 sushi:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_sushi_insufficient_falls_back_to_base(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	_set_house_garden(state, "house_left", true)

	# 需求 2 个：restaurant 必须能提供 2 sushi 才能替代；
	# 若所有 restaurant 都寿司不足，应回退到 base（且不允许“部分寿司 + 部分原需求”混合成交）。
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	# 玩家0：寿司不足且 base 也无法满足
	state.players[0]["inventory"]["sushi"] = 1
	state.players[0]["inventory"]["burger"] = 0
	state.players[0]["inventory"]["soda"] = 0

	# 玩家1：满足 base，但无寿司
	state.players[1]["inventory"]["sushi"] = 0
	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["soda"] = 1

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "base":
		return Result.failure("寿司不足时应回退 base，实际 demand_variant_id=%s" % str(s0.get("demand_variant_id", null)))
	if int(s0.get("winner_owner", -1)) != 1:
		return Result.failure("回退 base 时应由玩家1 成交（玩家0 无 base 库存），实际: %s" % str(s0.get("winner_owner", null)))
	var required: Dictionary = s0.get("required", {})
	if int(required.get("burger", 0)) != 1 or int(required.get("soda", 0)) != 1:
		return Result.failure("base 成交 required 应为 burger=1,soda=1，实际: %s" % str(required))

	if int(state.players[0]["inventory"].get("sushi", 0)) != 1:
		return Result.failure("回退 base 不应消耗玩家0 的 sushi，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))
	if int(state.players[1]["inventory"].get("burger", 0)) != 0 or int(state.players[1]["inventory"].get("soda", 0)) != 0:
		return Result.failure("base 成交应消耗玩家1 的 burger/soda，实际 inv=%s" % str(state.players[1]["inventory"]))

	return Result.success()

static func _test_sushi_tiebreak_waitresses(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_tiebreak_map(state)
	_set_house_garden(state, "house_mid", true)

	_set_house_demands(state, "house_mid", [{"product": "burger"}, {"product": "soda"}])

	# 两家餐厅寿司都足够：用常规规则平局裁决
	state.players[0]["inventory"]["sushi"] = 2
	state.players[1]["inventory"]["sushi"] = 2

	# player0 多 1 个 waitress，应胜出（平局规则：waitresses -> turn order）
	if int(state.employee_pool.get("waitress", 0)) <= 0:
		return Result.failure("员工池中没有 waitress")
	state.employee_pool["waitress"] = int(state.employee_pool.get("waitress", 0)) - 1
	state.players[0]["employees"].append("waitress")

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "sushi:replace_all":
		return Result.failure("demand_variant_id 应为 sushi:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))
	if int(s0.get("winner_owner", -1)) != 0:
		return Result.failure("平局应由 waitress 更多的玩家0 获胜，实际 winner_owner=%s" % str(s0.get("winner_owner", null)))

	if int(state.players[0]["inventory"].get("sushi", 0)) != 0:
		return Result.failure("玩家0 sushi 应被扣减至 0，实际: %d" % int(state.players[0]["inventory"].get("sushi", 0)))
	if int(state.players[1]["inventory"].get("sushi", 0)) != 2:
		return Result.failure("玩家1 sushi 不应被消耗，实际: %d" % int(state.players[1]["inventory"].get("sushi", 0)))

	return Result.success()

static func _test_noodles_only_when_base_unavailable(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 非花园房屋：base demand 无人满足时，才用 noodles 完全替代
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 0
	state.players[0]["inventory"]["soda"] = 0
	state.players[0]["inventory"]["noodles"] = 0

	state.players[1]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["soda"] = 0
	state.players[1]["inventory"]["noodles"] = 2

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var cash1: int = int(state.players[1].get("cash", 0))
	if cash1 != 20:
		return Result.failure("面条替代应使玩家1 获得 20，实际: %d" % cash1)
	if int(state.players[1]["inventory"].get("noodles", 0)) != 0:
		return Result.failure("面条库存应被扣减至 0，实际: %d" % int(state.players[1]["inventory"].get("noodles", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "noodles:replace_all":
		return Result.failure("demand_variant_id 应为 noodles:replace_all，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_noodles_not_used_when_base_available(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# base demand 可成交时，房屋应始终优先选择“原有需求”，而不是 noodles（即使 noodles 的 score 更好）
	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "soda"}])
	_set_house_demands(state, "house_right", [])

	# 玩家1（更远）可满足 base；玩家0（更近）仅有 noodles
	state.players[0]["inventory"]["burger"] = 0
	state.players[0]["inventory"]["soda"] = 0
	state.players[0]["inventory"]["noodles"] = 2

	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["soda"] = 1
	state.players[1]["inventory"]["noodles"] = 0

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var cash1: int = int(state.players[1].get("cash", 0))
	if cash1 != 20:
		return Result.failure("base 成交应使玩家1 获得 20，实际: %d" % cash1)
	if int(state.players[0].get("cash", 0)) != 0:
		return Result.failure("玩家0 不应售出，现金应为 0，实际: %d" % int(state.players[0].get("cash", 0)))

	if int(state.players[1]["inventory"].get("burger", 0)) != 0 or int(state.players[1]["inventory"].get("soda", 0)) != 0:
		return Result.failure("base 成交应扣减 burger+soda，实际 inv=%s" % str(state.players[1]["inventory"]))
	if int(state.players[0]["inventory"].get("noodles", 0)) != 2:
		return Result.failure("base 成交时 noodles 不应被消耗，实际: %d" % int(state.players[0]["inventory"].get("noodles", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "base":
		return Result.failure("demand_variant_id 应为 base，实际: %s" % str(s0.get("demand_variant_id", null)))
	if int(s0.get("winner_owner", -1)) != 1:
		return Result.failure("winner_owner 应为 1，实际: %s" % str(s0.get("winner_owner", null)))

	return Result.success()

static func _test_extra_luxury_manager_patch(seed_val: int) -> Result:
	# 基线（2 人局 one_x=1）：base_rules 的 luxury_manager 应为 1
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var s0 := e0.get_state()
	var lm0: int = int(s0.employee_pool.get("luxury_manager", -1))
	if lm0 != 1:
		return Result.failure("基线 luxury_manager 应为 1，实际: %d" % lm0)

	# 启用 noodles：+1
	var e1 := GameEngine.new()
	var init1 := e1.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
	])
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var s1 := e1.get_state()
	var lm1: int = int(s1.employee_pool.get("luxury_manager", -1))
	if lm1 != 2:
		return Result.failure("启用 noodles 后 luxury_manager 应为 2，实际: %d" % lm1)

	# 启用 sushi + noodles：仍只加一次（去重）
	var e2 := GameEngine.new()
	var init2 := e2.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
		"sushi",
	])
	if not init2.ok:
		return Result.failure("初始化失败: %s" % init2.error)
	var s2 := e2.get_state()
	var lm2: int = int(s2.employee_pool.get("luxury_manager", -1))
	if lm2 != 2:
		return Result.failure("启用 noodles+sushi 后 luxury_manager 应为 2（只加一次），实际: %d" % lm2)

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

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState) -> void:
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
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

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

static func _apply_tiebreak_map(state: GameState) -> void:
	# 仅用于测试平局裁决：将 tile_grid_size 设为 1x1，使 distance 固定为 0
	var grid_size := Vector2i(7, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var house_cells: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(2, 1), Vector2i(3, 1),
	]
	_set_house(cells, "house_mid", 1, house_cells, false)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(5, 3), Vector2i(6, 3),
		Vector2i(5, 4), Vector2i(6, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"house_mid": {
				"house_id": "house_mid",
				"house_number": 1,
				"anchor_pos": Vector2i(2, 0),
				"cells": house_cells,
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
				"anchor_pos": Vector2i(5, 3),
				"entrance_pos": Vector2i(6, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
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
