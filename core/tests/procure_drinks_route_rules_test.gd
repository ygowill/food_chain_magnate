# 采购饮料路线规则测试（M3）
# 验证：按路线拾取、禁 U 型转弯、同一来源每回合一次（同一采购员）
class_name ProcureDrinksRouteRulesTest
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var action := ProcureDrinksAction.new()

	var truck_result := _run_truck_route_rules(action, player_count, seed_val)
	if not truck_result.ok:
		return truck_result

	var truck_distance_plus_one := _run_truck_distance_plus_one(action, player_count, seed_val)
	if not truck_distance_plus_one.ok:
		return truck_distance_plus_one

	var air_result := _run_air_route_rules(action, player_count, seed_val)
	if not air_result.ok:
		return air_result

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"truck": truck_result.value,
		"truck_distance_plus_one": truck_distance_plus_one.value,
		"air": air_result.value,
	})

static func _run_truck_route_rules(action: ProcureDrinksAction, player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state().duplicate_state()
	_force_turn_order(state, player_count)
	state.phase = "Working"
	state.sub_phase = "GetDrinks"

	var actor := state.get_current_player_id()
	state.players[actor]["employees"].append("truck_driver")

	var map_result := _build_truck_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)

	# 1) 禁 U 型转弯：A -> B -> A
	var uturn_route := [[1, 1], [2, 1], [1, 1]]
	var cmd_uturn := Command.create("procure_drinks", actor, {
		"employee_type": "truck_driver",
		"restaurant_id": "rest_0",
		"route": uturn_route
	})
	var vr := action.validate(state, cmd_uturn)
	if vr.ok:
		return Result.failure("卡车 U 型路线应被拒绝")
	if str(vr.error).find("U型") < 0:
		return Result.failure("卡车 U 型拒绝原因应包含'U型'，实际: %s" % vr.error)

	# 2) 按路线拾取 + 同来源仅一次：绕圈经过同一来源多次，仍只获得 2 瓶；且不经过的来源不应获得
	var loop_route := [
		[1, 1], [2, 1], [3, 1],
		[3, 2], [3, 3], [2, 3],
		[1, 3], [1, 2], [1, 1],
	]
	var cmd_loop := Command.create("procure_drinks", actor, {
		"employee_type": "truck_driver",
		"restaurant_id": "rest_0",
		"route": loop_route
	})

	var before := _sum_drinks(state.players[actor].get("inventory", {}))
	var exec := action.compute_new_state(state, cmd_loop)
	if not exec.ok:
		return Result.failure("卡车路线采购应成功，但失败: %s" % exec.error)

	var new_state: GameState = exec.value
	var inv: Dictionary = new_state.players[actor].get("inventory", {})
	var after := _sum_drinks(inv)
	if after != before + 2:
		return Result.failure("卡车绕圈后饮品总量应只增加 2（同一来源仅一次），实际增量: %d" % (after - before))

	if int(inv.get("soda", 0)) != 2:
		return Result.failure("卡车绕圈应只获得 2 瓶 soda，实际: %d" % int(inv.get("soda", 0)))
	if int(inv.get("beer", 0)) != 0:
		return Result.failure("卡车路线未经过 beer 来源，不应获得 beer，实际: %d" % int(inv.get("beer", 0)))

	# 3) 里程碑：procure_plus_one（每个来源多 +1 瓶）
	state.players[actor]["milestones"].append("first_errand_boy")
	var before_bonus := _sum_drinks(state.players[actor].get("inventory", {}))
	var exec_bonus := action.compute_new_state(state, cmd_loop)
	if not exec_bonus.ok:
		return Result.failure("卡车 procure_plus_one 采购应成功，但失败: %s" % exec_bonus.error)
	var bonus_state: GameState = exec_bonus.value
	var inv_bonus: Dictionary = bonus_state.players[actor].get("inventory", {})
	var after_bonus := _sum_drinks(inv_bonus)
	if after_bonus != before_bonus + 3:
		return Result.failure("卡车 procure_plus_one 后饮品总量应增加 3（每源+1），实际增量: %d" % (after_bonus - before_bonus))
	if int(inv_bonus.get("soda", 0)) != 3:
		return Result.failure("卡车 procure_plus_one 应获得 3 瓶 soda，实际: %d" % int(inv_bonus.get("soda", 0)))
	if int(inv_bonus.get("beer", 0)) != 0:
		return Result.failure("卡车 procure_plus_one 路线未经过 beer 来源，不应获得 beer，实际: %d" % int(inv_bonus.get("beer", 0)))

	return Result.success({
		"uturn_error": vr.error,
		"loop_drinks_delta": after - before,
		"inventory": inv
	})

static func _run_truck_distance_plus_one(action: ProcureDrinksAction, player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state().duplicate_state()
	_force_turn_order(state, player_count)
	state.phase = "Working"
	state.sub_phase = "GetDrinks"

	var actor := state.get_current_player_id()
	state.players[actor]["employees"].append("truck_driver")

	var map_result := _build_truck_distance_plus_one_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)

	var route: Array = []
	for x in range(25):
		route.append([x, 1])

	var cmd := Command.create("procure_drinks", actor, {
		"employee_type": "truck_driver",
		"restaurant_id": "rest_0",
		"route": route
	})

	# 无里程碑：range=3，route 跨越 4 次边界，应失败
	var vr := action.validate(state, cmd)
	if vr.ok:
		return Result.failure("没有 distance_plus_one 时，超范围路线应被拒绝")
	if str(vr.error).find("超出卡车范围") < 0:
		return Result.failure("超范围拒绝原因应包含'超出卡车范围'，实际: %s" % vr.error)

	# 有里程碑：first_cart_operator -> truck_driver 距离 +1，允许执行
	state.players[actor]["milestones"].append("first_cart_operator")
	var vr2 := action.validate(state, cmd)
	if not vr2.ok:
		return Result.failure("有 distance_plus_one 时应允许超范围路线，但失败: %s" % vr2.error)

	var before := _sum_drinks(state.players[actor].get("inventory", {}))
	var exec := action.compute_new_state(state, cmd)
	if not exec.ok:
		return Result.failure("有 distance_plus_one 时执行采购应成功，但失败: %s" % exec.error)
	var new_state: GameState = exec.value
	var inv: Dictionary = new_state.players[actor].get("inventory", {})
	var after := _sum_drinks(inv)
	if after != before + 2:
		return Result.failure("distance_plus_one 生效后应获得 2 瓶饮品，实际增量: %d" % (after - before))

	return Result.success({
		"error_without_bonus": vr.error,
		"inventory": inv
	})

static func _run_air_route_rules(action: ProcureDrinksAction, player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.get_state().duplicate_state()
	_force_turn_order(state, player_count)
	state.phase = "Working"
	state.sub_phase = "GetDrinks"

	var actor := state.get_current_player_id()
	state.players[actor]["employees"].append("zeppelin_pilot")

	var map_result := _build_air_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	MapRuntimeClass.invalidate_road_graph(state)

	# 1) 禁 U 型转弯：A -> B -> A
	var uturn_route := [[1, 1], [2, 1], [1, 1]]
	var cmd_uturn := Command.create("procure_drinks", actor, {
		"employee_type": "zeppelin_pilot",
		"restaurant_id": "rest_0",
		"route": uturn_route
	})
	var vr := action.validate(state, cmd_uturn)
	if vr.ok:
		return Result.failure("飞艇 U 型路线应被拒绝")
	if str(vr.error).find("U型") < 0:
		return Result.failure("飞艇 U 型拒绝原因应包含'U型'，实际: %s" % vr.error)

	# 2) 按路线拾取 + 同来源仅一次：绕圈回到同一来源格，仍只获得 2 瓶；且不经过的来源不应获得
	var loop_route := [[1, 1], [2, 1], [2, 2], [1, 2], [1, 1]]  # 4 步闭环
	var cmd_loop := Command.create("procure_drinks", actor, {
		"employee_type": "zeppelin_pilot",
		"restaurant_id": "rest_0",
		"route": loop_route
	})

	var before := _sum_drinks(state.players[actor].get("inventory", {}))
	var exec := action.compute_new_state(state, cmd_loop)
	if not exec.ok:
		return Result.failure("飞艇路线采购应成功，但失败: %s" % exec.error)

	var new_state: GameState = exec.value
	var inv: Dictionary = new_state.players[actor].get("inventory", {})
	var after := _sum_drinks(inv)
	if after != before + 2:
		return Result.failure("飞艇绕圈后饮品总量应只增加 2（同一来源仅一次），实际增量: %d" % (after - before))

	if int(inv.get("lemonade", 0)) != 2:
		return Result.failure("飞艇绕圈应只获得 2 瓶 lemonade，实际: %d" % int(inv.get("lemonade", 0)))
	if int(inv.get("beer", 0)) != 0:
		return Result.failure("飞艇路线未经过 beer 来源，不应获得 beer，实际: %d" % int(inv.get("beer", 0)))

	return Result.success({
		"uturn_error": vr.error,
		"loop_drinks_delta": after - before,
		"inventory": inv
	})

static func _force_turn_order(state: GameState, player_count: int) -> void:
	state.turn_order.clear()
	for i in range(player_count):
		state.turn_order.append(i)
	state.current_player_index = 0

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": []
			})
		cells.append(row)
	return cells

static func _set_road(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _build_truck_test_map(owner: int) -> Result:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# 环形道路 + 右侧支路（用于“可达但未经过”的来源）
	_set_road(cells, Vector2i(1, 1), ["E", "S"])
	_set_road(cells, Vector2i(2, 1), ["W", "E"])
	_set_road(cells, Vector2i(3, 1), ["W", "S", "E"])
	_set_road(cells, Vector2i(4, 1), ["W"])  # 支路
	_set_road(cells, Vector2i(3, 2), ["N", "S"])
	_set_road(cells, Vector2i(3, 3), ["N", "W"])
	_set_road(cells, Vector2i(2, 3), ["E", "W"])
	_set_road(cells, Vector2i(1, 3), ["E", "N"])
	_set_road(cells, Vector2i(1, 2), ["N", "S"])

	var restaurants := {
		"rest_0": {
			"restaurant_id": "rest_0",
			"owner": owner,
			"anchor_pos": Vector2i(0, 0),
			"entrance_pos": Vector2i(0, 1)
		}
	}

	var drink_sources := [
		{"world_pos": Vector2i(2, 2), "type": "soda", "tile_id": "A"},  # 位于环内：会被多次经过，但只计一次
		{"world_pos": Vector2i(4, 0), "type": "beer", "tile_id": "B"},  # 邻接支路：可达但路线不经过
	]

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
		"restaurants": restaurants,
		"drink_sources": drink_sources,
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	})

static func _build_truck_distance_plus_one_test_map(owner: int) -> Result:
	var grid_size := Vector2i(25, 5) # 5 个板块宽（TILE_SIZE=5），用于制造 4 次边界跨越
	var cells := _build_empty_cells(grid_size)

	# 水平直线道路：y=1，x=0..24
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road(cells, Vector2i(x, 1), dirs)

	var restaurants := {
		"rest_0": {
			"restaurant_id": "rest_0",
			"owner": owner,
			"anchor_pos": Vector2i(0, 0),
			"entrance_pos": Vector2i(0, 0)
		}
	}

	var drink_sources := [
		{"world_pos": Vector2i(24, 0), "type": "soda", "tile_id": "R"},
	]

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(5, 1),
		"cells": cells,
		"houses": {},
		"restaurants": restaurants,
		"drink_sources": drink_sources,
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	})

static func _build_air_test_map(owner: int) -> Result:
	var grid_size := Vector2i(3, 3)
	var cells := _build_empty_cells(grid_size)

	var restaurants := {
		"rest_0": {
			"restaurant_id": "rest_0",
			"owner": owner,
			"anchor_pos": Vector2i(1, 1),
			"entrance_pos": Vector2i(1, 1)
		}
	}

	var drink_sources := [
		{"world_pos": Vector2i(1, 1), "type": "lemonade", "tile_id": "C"},  # 起点：会被重复经过，但只计一次
		{"world_pos": Vector2i(0, 1), "type": "beer", "tile_id": "D"},      # 在范围内但不在路线
	]

	return Result.success({
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
		"restaurants": restaurants,
		"drink_sources": drink_sources,
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	})

static func _sum_drinks(inventory: Dictionary) -> int:
	return int(inventory.get("soda", 0)) + int(inventory.get("lemonade", 0)) + int(inventory.get("beer", 0))
