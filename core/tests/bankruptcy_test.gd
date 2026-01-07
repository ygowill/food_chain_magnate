# 银行破产测试（M4）
# 覆盖：第一次破产（翻储备卡注入现金 + CEO 卡槽重设）与第二次破产（允许透支并在晚餐结束后终局）
class_name BankruptcyTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_first_bankruptcy(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_second_bankruptcy_ends_game(seed_val)
	if not r2.ok:
		return r2

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"cases": 2,
	})

static func _test_first_bankruptcy(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 固定储备卡（两人都选同一张，避免平局）
	for pid in range(2):
		state.players[pid]["reserve_cards"] = [{"type": 10, "cash": 20, "ceo_slots": 4}]
		state.players[pid]["reserve_card_selected"] = 0
		state.players[pid]["reserve_card_revealed"] = false

	# 先把银行资金压到不足以支付晚餐收入（保持现金守恒：从银行转给玩家1）
	var bank_before: int = int(state.bank.get("total", 0))
	var drain := bank_before - 5
	if drain <= 0:
		return Result.failure("测试前置失败：银行初始资金过低: %d" % bank_before)
	var drain_result := StateUpdaterClass.player_receive_from_bank(state, 1, drain)
	if not drain_result.ok:
		return Result.failure("预置转账失败: %s" % drain_result.error)
	if int(state.bank.get("total", 0)) != 5:
		return Result.failure("预置转账后银行应为 5，实际: %d" % int(state.bank.get("total", 0)))

	# 触发一次售卖：$10（银行只有$5，必须触发第一次破产）
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	state.players[0]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["burger"] = 0

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != "Payday":
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	if int(state.bank.get("broke_count", 0)) != 1:
		return Result.failure("第一次破产后 broke_count 应为 1，实际: %d" % int(state.bank.get("broke_count", 0)))
	if int(state.bank.get("reserve_added_total", 0)) != 40:
		return Result.failure("reserve_added_total 不匹配: %d != 40" % int(state.bank.get("reserve_added_total", 0)))
	if int(state.bank.get("ceo_slots_after_first_break", -1)) != 4:
		return Result.failure("ceo_slots_after_first_break 不匹配: %d != 4" % int(state.bank.get("ceo_slots_after_first_break", -1)))

	for pid in range(2):
		var cs: Dictionary = state.players[pid].get("company_structure", {})
		if int(cs.get("ceo_slots", 0)) != 4:
			return Result.failure("玩家 %d 的 CEO 卡槽应更新为 4，实际: %s" % [pid, str(cs.get("ceo_slots", null))])
		if not bool(state.players[pid].get("reserve_card_revealed", false)):
			return Result.failure("第一次破产后玩家 %d 的 reserve_card_revealed 应为 true" % pid)

	# 银行：5 + 40 - 10 = 35
	if int(state.bank.get("total", 0)) != 35:
		return Result.failure("第一次破产后银行余额不匹配: %d != 35" % int(state.bank.get("total", 0)))

	if int(state.players[0].get("cash", 0)) != 10:
		return Result.failure("玩家0 应获得晚餐收入 10，实际: %d" % int(state.players[0].get("cash", 0)))

	var bankruptcy: Dictionary = state.round_state.get("bankruptcy", {})
	var events: Array = bankruptcy.get("events", [])
	if events.is_empty():
		return Result.failure("round_state.bankruptcy.events 不应为空")
	if str(events[0].get("kind", "")) != "first":
		return Result.failure("首个破产事件 kind 应为 first，实际: %s" % str(events[0].get("kind", null)))

	return Result.success()

static func _test_second_bankruptcy_ends_game(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 固定为小额储备卡：第一次破产注入 $20，不足以支付 $50，触发第二次破产并允许透支完成支付
	for pid in range(2):
		state.players[pid]["reserve_cards"] = [{"type": 10, "cash": 10, "ceo_slots": 4}]
		state.players[pid]["reserve_card_selected"] = 0
		state.players[pid]["reserve_card_revealed"] = false

	# 清空银行（保持现金守恒：从银行转给玩家1）
	var bank_before: int = int(state.bank.get("total", 0))
	var drain_result := StateUpdaterClass.player_receive_from_bank(state, 1, bank_before)
	if not drain_result.ok:
		return Result.failure("预置转账失败: %s" % drain_result.error)
	if int(state.bank.get("total", 0)) != 0:
		return Result.failure("预置转账后银行应为 0，实际: %d" % int(state.bank.get("total", 0)))

	# 单个房屋 3 需求（对齐普通上限 3），收入 $30
	_set_house_garden(state, "house_left", false)
	var demands: Array = []
	for _i in range(3):
		demands.append({"product": "burger"})
	_set_house_demands(state, "house_left", demands)
	state.players[0]["inventory"]["burger"] = 3
	state.players[1]["inventory"]["burger"] = 0

	var adv := _advance_to_dinnertime(engine)
	if not adv.ok:
		return adv

	state = engine.get_state()
	if state.phase != "GameOver":
		return Result.failure("当前应为 GameOver（第二次破产后应跳过 Payday），实际: %s" % state.phase)
	if int(state.bank.get("broke_count", 0)) != 2:
		return Result.failure("第二次破产后 broke_count 应为 2，实际: %d" % int(state.bank.get("broke_count", 0)))
	if int(state.bank.get("reserve_added_total", 0)) != 20:
		return Result.failure("reserve_added_total 不匹配: %d != 20" % int(state.bank.get("reserve_added_total", 0)))

	# 银行：0 + 20 - 30 = -10（第二次破产允许透支）
	if int(state.bank.get("total", 0)) != -10:
		return Result.failure("第二次破产后银行余额不匹配: %d != -10" % int(state.bank.get("total", 0)))
	if int(state.players[0].get("cash", 0)) != 30:
		return Result.failure("玩家0 应获得晚餐收入 30，实际: %d" % int(state.players[0].get("cash", 0)))

	var game_over: Dictionary = state.round_state.get("game_over", {})
	if str(game_over.get("reason", "")) != "bankruptcy":
		return Result.failure("第二次破产后应写入 round_state.game_over，实际: %s" % str(game_over))

	return Result.success()

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = "Working"
	state.sub_phase = "PlaceRestaurants"
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

	var adv := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
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
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# 水平道路 y=2
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
	_set_house(cells, "house_left", 1, left_house_cells, false)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells, Vector2i(0, 3))

	var rest1_cells: Array[Vector2i] = [
		Vector2i(3, 3), Vector2i(4, 3),
		Vector2i(3, 4), Vector2i(4, 4),
	]
	_set_restaurant(cells, "rest_1", 1, rest1_cells, Vector2i(4, 3))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
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
				"anchor_pos": Vector2i(3, 3),
				"entrance_pos": Vector2i(4, 3),
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
	MapRuntimeClass.invalidate_road_graph(state)

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
