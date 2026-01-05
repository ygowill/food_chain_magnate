# Coffee（模块4）规则测试（V2）
class_name CoffeeV2Test
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const CoffeeRulesEntryClass = preload("res://modules/coffee/rules/entry.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

static func run(seed_val: int = 12345) -> Result:
	var r1 := _test_train_trigger_allows_place_and_move(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_dinnertime_route_buys_multiple_coffee(seed_val)
	if not r2.ok:
		return r2

	return Result.success({
		"cases": 2,
		"seed": seed_val,
	})

static func _test_train_trigger_allows_place_and_move(seed_val: int) -> Result:
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
		"coffee",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_train_test_map(state)
	_apply_coffee_map_fields(state)

	state.phase = "Working"
	state.sub_phase = "Train"
	_mark_all_players_not_passed(state)

	# 提供培训员，保证 Train 子阶段可执行
	state.players[0]["employees"].append("coach")
	state.employee_pool["coach"] = int(state.employee_pool.get("coach", 0)) - 1

	# 手动放入 1 张 barista_trainee（待命），用于培训
	state.players[0]["reserve_employees"].append("barista_trainee")
	state.employee_pool["barista_trainee"] = int(state.employee_pool.get("barista_trainee", 0)) - 1
	# 再放入 1 张 barista_trainee，用于再次触发 Train（避免依赖链式培训规则）
	state.players[0]["reserve_employees"].append("barista_trainee")
	state.employee_pool["barista_trainee"] = int(state.employee_pool.get("barista_trainee", 0)) - 1
	# 同时放入 1 张 barista（必须在本 Train 子阶段开始前存在，用于后续升级为 lead_barista）
	state.players[0]["reserve_employees"].append("barista")
	state.employee_pool["barista"] = int(state.employee_pool.get("barista", 0)) - 1

	var t1 := e.execute_command(Command.create("train", 0, {
		"from_employee": "barista_trainee",
		"to_employee": "barista",
	}))
	if not t1.ok:
		return Result.failure("Train 执行失败: %s" % t1.error)

	var p1 := e.execute_command(Command.create("place_or_move_coffee_shop", 0, {
		"mode": "place",
		"position": [2, 1],
	}))
	if not p1.ok:
		return Result.failure("place_or_move_coffee_shop(place) 执行失败: %s" % p1.error)

	state = e.get_state()
	if int(state.players[0].get("coffee_shop_tokens_remaining", -1)) != 2:
		return Result.failure("放置后 token 应为 2，实际: %d" % int(state.players[0].get("coffee_shop_tokens_remaining", -1)))

	# 未再次培训前不能再次执行（trigger 用尽）
	var p2 := e.execute_command(Command.create("place_or_move_coffee_shop", 0, {
		"mode": "place",
		"position": [3, 1],
	}))
	if p2.ok:
		return Result.failure("未再次培训前不应允许再次放置/移动咖啡店")

	# token=0 时允许 move（但 place 仍失败）
	state.players[0]["coffee_shop_tokens_remaining"] = 0
	var t2 := e.execute_command(Command.create("train", 0, {
		"from_employee": "barista_trainee",
		"to_employee": "barista",
	}))
	if not t2.ok:
		return Result.failure("Train2 执行失败: %s" % t2.error)

	var p3 := e.execute_command(Command.create("place_or_move_coffee_shop", 0, {
		"mode": "place",
		"position": [3, 1],
	}))
	if p3.ok:
		return Result.failure("token=0 时 place 应失败")

	var shops: Dictionary = state.map.get("coffee_shops", {})
	var shop_ids: Array = shops.keys()
	if shop_ids.is_empty():
		return Result.failure("应存在 1 个 coffee_shop")
	var shop_id: String = str(shop_ids[0])

	var m1 := e.execute_command(Command.create("place_or_move_coffee_shop", 0, {
		"mode": "move",
		"from_shop_id": shop_id,
		"position": [3, 1],
	}))
	if not m1.ok:
		return Result.failure("move 执行失败: %s" % m1.error)

	return Result.success()

static func _test_dinnertime_route_buys_multiple_coffee(seed_val: int) -> Result:
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
		"coffee",
	]
	var init := e.initialize(3, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_route_test_map(state)

	# house_left 需求 1 个 burger；赢家餐厅=玩家0（玩家1/2 没 burger）
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 0
	state.players[2]["inventory"]["burger"] = 0

	# 沿路两处可买咖啡（都不是目的地餐厅）
	state.players[1]["inventory"]["coffee"] = 1
	state.players[2]["inventory"]["coffee"] = 1
	state.players[0]["inventory"]["coffee"] = 5

	# 断言：路过点应被 stop_index 覆盖（避免“地图构造错误导致买不到咖啡”）
	var stop_index_read := CoffeeRulesEntryClass._build_coffee_stop_index(state, "rest_dest")
	if not stop_index_read.ok:
		return Result.failure("coffee stop_index 构建失败: %s" % stop_index_read.error)
	var stop_index: Dictionary = stop_index_read.value
	var k_rest := CoffeeRulesEntryClass._pos_key(Vector2i(2, 4))
	var k_shop := CoffeeRulesEntryClass._pos_key(Vector2i(6, 4))
	if not stop_index.has(k_rest) or not stop_index.has(k_shop):
		var seg_2_4 = state.map.get("cells", [])[4][2].get("road_segments", null) if state.map.get("cells", []) is Array else null
		var seg_6_4 = state.map.get("cells", [])[4][6].get("road_segments", null) if state.map.get("cells", []) is Array else null
		var has_2_4 := MapRuntimeClass.has_road_at_any(state, Vector2i(2, 4))
		var has_6_4 := MapRuntimeClass.has_road_at_any(state, Vector2i(6, 4))
		return Result.failure("coffee stop_index 未覆盖预期路点: has_rest=%s has_shop=%s keys=%s road@2,4=%s seg@2,4=%s road@6,4=%s seg@6,4=%s" % [str(stop_index.has(k_rest)), str(stop_index.has(k_shop)), str(stop_index.keys()), str(has_2_4), str(seg_2_4), str(has_6_4), str(seg_6_4)])

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.size() != 1:
		return Result.failure("应存在 1 条 sale 记录，实际: %d" % sales.size())
	var s0: Dictionary = sales[0]
	var route_purchases: Array = s0.get("route_purchases", [])
	if route_purchases.size() != 2:
		return Result.failure("应买到 2 杯咖啡，实际: %d (%s)" % [route_purchases.size(), str(route_purchases)])

	# 两杯咖啡分别卖给玩家1/2（每杯 $10）
	if int(state.players[1].get("cash", 0)) != 10:
		return Result.failure("玩家1 咖啡收入应为 10，实际: %d" % int(state.players[1].get("cash", 0)))
	if int(state.players[2].get("cash", 0)) != 10:
		return Result.failure("玩家2 咖啡收入应为 10，实际: %d" % int(state.players[2].get("cash", 0)))

	# 目的地餐厅售卖 burger（单价 $10），玩家0 收入 $10
	if int(state.players[0].get("cash", 0)) != 10:
		return Result.failure("玩家0 晚餐收入应为 10，实际: %d" % int(state.players[0].get("cash", 0)))

	# 咖啡库存扣减
	if int(state.players[1]["inventory"].get("coffee", 0)) != 0:
		return Result.failure("玩家1 coffee 应被扣减，实际: %d" % int(state.players[1]["inventory"].get("coffee", 0)))
	if int(state.players[2]["inventory"].get("coffee", 0)) != 0:
		return Result.failure("玩家2 coffee 应被扣减，实际: %d" % int(state.players[2]["inventory"].get("coffee", 0)))

	# 目的地餐厅的咖啡不应被购买（规则：不在目的地消费咖啡）
	if int(state.players[0]["inventory"].get("coffee", 0)) != 5:
		return Result.failure("目的地餐厅所属玩家 coffee 不应被消耗，实际: %d" % int(state.players[0]["inventory"].get("coffee", 0)))

	return Result.success()

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = "Working"
	state.sub_phase = "PlaceRestaurants"
	_mark_all_players_passed(state)
	var adv := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("推进到 Dinnertime 失败: %s" % adv.error)
	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	var order: Array[int] = []
	for pid in range(state.players.size()):
		order.append(pid)
	state.turn_order = order
	state.current_player_index = 0

static func _mark_all_players_passed(state: GameState) -> void:
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

static func _mark_all_players_not_passed(state: GameState) -> void:
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = false
	state.round_state["sub_phase_passed"] = passed

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

static func _set_coffee_shop(cells: Array, shop_id: String, owner: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "coffee_shop",
		"owner": owner,
		"shop_id": shop_id,
		"dynamic": true
	}

static func _apply_coffee_map_fields(state: GameState) -> void:
	state.map["coffee_shops"] = {}
	state.map["next_coffee_shop_id"] = 1
	for pid in range(state.players.size()):
		state.players[pid]["coffee_shop_tokens_remaining"] = 3

static func _apply_train_test_map(state: GameState) -> void:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 0,
		"boundary_index": {},
		"marketing_placements": {}
	}
	MapRuntimeClass.invalidate_road_graph(state)

static func _apply_route_test_map(state: GameState) -> void:
	# 图形：两条同 boundary_crossings 的路径；下方绕行路过更多 coffee 点
	var grid_size := Vector2i(9, 7)
	var cells := _build_empty_cells(grid_size)

	# 上方直路 y=2: (0..8,2)
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	# 下方绕行：y=4: (0..8,4) + 两条竖路连接到 y=2
	for x in range(grid_size.x):
		var dirs2: Array = []
		if x > 0:
			dirs2.append("W")
		if x < grid_size.x - 1:
			dirs2.append("E")
		_set_road_segment(cells, Vector2i(x, 4), dirs2)

	# 连接 (2,2)<->(2,4) 与 (6,2)<->(6,4)
	for y in range(3, 4):
		_set_road_segment(cells, Vector2i(2, y), ["N", "S"])
		_set_road_segment(cells, Vector2i(6, y), ["N", "S"])
	cells[2][2]["road_segments"] = [{"dirs": ["W", "E", "S"]}]
	cells[4][2]["road_segments"] = [{"dirs": ["W", "E", "N"]}]
	cells[2][6]["road_segments"] = [{"dirs": ["W", "E", "S"]}]
	cells[4][6]["road_segments"] = [{"dirs": ["W", "E", "N"]}]

	var house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_left", 1, house_cells, false)

	var dest_rest_cells: Array[Vector2i] = [
		Vector2i(7, 5), Vector2i(8, 5),
		Vector2i(7, 6), Vector2i(8, 6),
	]
	_set_restaurant(cells, "rest_dest", 0, dest_rest_cells)

	# 路过点：restaurant (玩家1) 在 (2,5)-(3,6)（与下方路相邻）；coffee_shop (玩家2) 在 (6,5)
	var side_rest_cells: Array[Vector2i] = [
		Vector2i(2, 5), Vector2i(3, 5),
		Vector2i(2, 6), Vector2i(3, 6),
	]
	_set_restaurant(cells, "rest_side", 1, side_rest_cells)
	_set_coffee_shop(cells, "coffee_shop_side", 2, Vector2i(6, 5))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_dest": {
				"restaurant_id": "rest_dest",
				"owner": 0,
				"anchor_pos": Vector2i(7, 5),
				"entrance_pos": Vector2i(7, 5),
				"cells": dest_rest_cells,
			},
			"rest_side": {
				"restaurant_id": "rest_side",
				"owner": 1,
				"anchor_pos": Vector2i(2, 5),
				"entrance_pos": Vector2i(2, 5),
				"cells": side_rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}
	state.players[0]["restaurants"] = ["rest_dest"]
	state.players[1]["restaurants"] = ["rest_side"]
	state.players[2]["restaurants"] = []
	MapRuntimeClass.invalidate_road_graph(state)

	var shops: Dictionary = {
		"coffee_shop_side": {
			"shop_id": "coffee_shop_side",
			"owner": 2,
			"anchor_pos": Vector2i(6, 5),
			"entrance_pos": Vector2i(6, 5),
		}
	}
	state.map["coffee_shops"] = shops
	state.map["next_coffee_shop_id"] = 2

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
