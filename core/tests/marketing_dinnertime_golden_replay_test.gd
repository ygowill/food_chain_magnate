# 黄金回放：营销 -> 晚餐组合回归测试（M4）
# 目标：
# - Marketing 阶段根据营销实例生成需求
# - 下一回合 Dinnertime 结算并清空需求，且可重放一致
class_name MarketingDinnertimeGoldenReplayTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	EmployeeRegistryClass.reset()

	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var engine_a := GameEngine.new()
	var init := engine_a.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine_a.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 构造：从 Payday -> Marketing 开始，Marketing 生成需求；下一回合 Working 生产食物；Dinnertime 售出并清空需求。
	state.round_number = 1
	state.phase = "Payday"
	state.sub_phase = ""

	# 现金守恒：总额保持 2*$50=100
	state.players[0]["cash"] = 5
	state.players[1]["cash"] = 0
	state.bank["total"] = 95

	# 给玩家0 一个 burger_cook（用于下一回合 GetFood 生产），保持员工守恒
	var take_cook := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
	if not take_cook.ok:
		return Result.failure("从员工池取出 burger_cook 失败: %s" % take_cook.error)
	state.players[0]["employees"].append("burger_cook")

	# 放入一个忙碌营销员 + 一张待结算的 billboard 营销实例（duration=1）
	var take_marketer := StateUpdaterClass.take_from_pool(state, "marketer", 1)
	if not take_marketer.ok:
		return Result.failure("从员工池取出 marketer 失败: %s" % take_marketer.error)
	state.players[0]["busy_marketers"] = ["marketer"]

	state.marketing_instances = [{
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketer",
		"product": "burger",
		"world_pos": Vector2i(2, 1),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}]
	state.map["marketing_placements"] = {
		"11": {
			"board_number": 11,
			"type": "billboard",
			"owner": 0,
			"product": "burger",
			"world_pos": Vector2i(2, 1),
			"remaining_duration": 1,
			"axis": "",
			"tile_index": -1,
		}
	}

	# 固化初始状态（用于回放一致性）
	var initial_state_dict: Dictionary = state.to_dict().duplicate(true)

	# 1) Payday -> Marketing：应生成 house_left 的 burger 需求
	var to_marketing := engine_a.execute_command(Command.create_system("advance_phase"))
	if not to_marketing.ok:
		return Result.failure("推进到 Marketing 失败: %s" % to_marketing.error)

	state = engine_a.get_state()

	var left_after_marketing: Dictionary = state.map.get("houses", {}).get("house_left", {})
	var left_demands_after_marketing: Array = left_after_marketing.get("demands", [])
	if left_demands_after_marketing.size() != 1 or str(left_demands_after_marketing[0].get("product", "")) != "burger":
		return Result.failure("Marketing 后 house_left 应新增 1 个 burger 需求，实际: %s" % str(left_demands_after_marketing))

	# 2) Restructuring -> OrderOfBusiness
	var restruct := TestPhaseUtilsClass.complete_restructuring(engine_a)
	if not restruct.ok:
		return restruct
	state = engine_a.get_state()
	if state.phase != "OrderOfBusiness":
		return Result.failure("当前应为 OrderOfBusiness，实际: %s" % state.phase)

	var oob := _complete_order_of_business(engine_a)
	if not oob.ok:
		return oob

	# 3) OrderOfBusiness 完成后应自动进入 Working，并推进到 GetFood
	state = engine_a.get_state()
	if state.phase != "Working":
		return Result.failure("OrderOfBusiness 完成后应进入 Working，实际: %s" % state.phase)

	# 轮转到玩家0（若 OOB 选择导致玩家1 先手）
	var safety := 0
	while engine_a.get_state().get_current_player_id() != 0:
		safety += 1
		if safety > 5:
			return Result.failure("轮转到玩家0 超出安全上限")
		var pid := engine_a.get_state().get_current_player_id()
		var et := engine_a.execute_command(Command.create("end_turn", pid))
		if not et.ok:
			return Result.failure("end_turn 失败: %s" % et.error)

	# 推进到 GetFood（记录为命令，确保回放一致）
	var to_get_food := TestPhaseUtilsClass.advance_until_working_sub_phase(engine_a, "GetFood", 10)
	if not to_get_food.ok:
		return to_get_food
	state = engine_a.get_state()
	if state.sub_phase != "GetFood":
		return Result.failure("当前应为 GetFood，实际: %s" % state.sub_phase)

	# 4) 生产食物：burger_cook 产出 burger
	var prod := engine_a.execute_command(Command.create("produce_food", 0, {"employee_type": "burger_cook"}))
	if not prod.ok:
		return Result.failure("produce_food 失败: %s" % prod.error)

	# 5) 推进到 Payday（Dinnertime 会自动结算跳过）
	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine_a, "Payday", 30)
	if not to_payday.ok:
		return to_payday

	state = engine_a.get_state()
	if state.phase != "Payday":
		return Result.failure("当前应为 Payday（Dinnertime 已自动结算跳过），实际: %s" % state.phase)

	# 结算结果：
	# - Payday：玩家0 有 $5，但需支付 burger_cook 的薪水（$5），因此进入后续阶段时现金变为 $0
	# - Dinnertime：售出 1 个 burger（单价 10） + 首次营销汉堡里程碑奖励 +$5 => 现金应为 $15
	if int(state.players[0].get("cash", 0)) != 15:
		return Result.failure("玩家0 现金应为 15，实际: %d" % int(state.players[0].get("cash", 0)))
	var left_after_dinner: Dictionary = state.map.get("houses", {}).get("house_left", {})
	if Array(left_after_dinner.get("demands", [])).size() != 0:
		return Result.failure("Dinnertime 后 house_left 需求应被清空，实际: %s" % str(left_after_dinner.get("demands", [])))

	# === 回放一致性（archive -> load_from_archive -> hash 一致）===
	var final_hash_a := state.compute_hash()

	var archive := {
		"schema_version": GameStateClass.SCHEMA_VERSION,
		"game_version": "test",
		"created_at": "test",
		"rng": engine_a.random_manager.to_dict() if engine_a.random_manager != null else {},
		"initial_state": initial_state_dict,
		"commands": [],
		"checkpoints": [],
		"current_index": engine_a.get_command_history().size() - 1,
		"final_hash": final_hash_a,
	}
	for cmd in engine_a.get_command_history():
		archive.commands.append(cmd.to_dict())

	var engine_b := GameEngine.new()
	var load := engine_b.load_from_archive(archive)
	if not load.ok:
		return Result.failure("从 archive 回放失败: %s" % load.error)

	var final_hash_b := engine_b.get_state().compute_hash()
	if final_hash_a != final_hash_b:
		return Result.failure("回放哈希不一致: A=%s, B=%s" % [final_hash_a.substr(0, 12), final_hash_b.substr(0, 12)])

	var replay_b := engine_b.full_replay()
	if not replay_b.ok:
		return Result.failure("完整重放失败: %s" % replay_b.error)
	var final_hash_b2 := engine_b.get_state().compute_hash()
	if final_hash_a != final_hash_b2:
		return Result.failure("完整重放哈希不一致: A=%s, B2=%s" % [final_hash_a.substr(0, 12), final_hash_b2.substr(0, 12)])

	return Result.success({
		"seed": seed_val,
		"command_count": engine_a.get_command_history().size(),
		"final_hash": final_hash_a,
	})

static func _complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var player_count := state.players.size()
	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > player_count + 2:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		var oob: Dictionary = state.round_state.get("order_of_business", {})
		var picks: Array = oob.get("picks", [])
		if picks.size() != player_count:
			return Result.failure("OrderOfBusiness picks 长度不匹配")
		if bool(oob.get("finalized", false)):
			return Result.success()

		var actor := state.get_current_player_id()
		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

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
	var grid_size := Vector2i(10, 5)  # 2×1 板块（TILE_SIZE=5）
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
	MapRuntimeClass.invalidate_road_graph(state)
