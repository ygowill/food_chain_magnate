# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST PIZZA SOLD
# - 规则（按用户确认）：
#   - 计数口径：按晚餐房屋顺序，筛出包含 pizza 的房屋，取前 3 个
#   - 影响范围：全局（无论卖家是谁）
#   - 落子：由卖家通过动作选择；使用 base radio(#1-#3)，持续 2 回合；不绑定营销员
class_name NewMilestonesPizzaSoldV2Test
extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const Phase = PhaseDefsClass.Phase

static func run(player_count: int = 2, seed_val: int = 990011) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

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
	]
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# 让玩家0 可以卖出 3 次 pizza
	var inv: Dictionary = state.players[0]["inventory"]
	inv["pizza"] = 3
	state.players[0]["inventory"] = inv

	# 3 个房屋均有 pizza 需求（按 house_number 顺序=1,2,3）
	var houses: Dictionary = state.map["houses"]
	for hid in ["h1", "h2", "h3"]:
		var h: Dictionary = houses[hid]
		h["demands"] = [{"product": "pizza"}]
		houses[hid] = h
	state.map["houses"] = houses

	# 运行晚餐结算（含 new_milestones 的 extension：ProductSold + pizza radio pending）
	state.phase = "Dinnertime"
	state.sub_phase = ""
	var reg = engine.phase_manager.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 未设置")
	var run_any = reg.run(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, state, engine.phase_manager)
	if not (run_any is Result):
		return Result.failure("运行晚餐结算失败: 返回类型错误（期望 Result）")
	var r: Result = run_any
	if not r.ok:
		return Result.failure("运行晚餐结算失败: %s" % r.error)

	# 应产生 3 个待放置 radio（并阻止推进阶段）
	var pending_val = state.round_state.get("new_milestones_pizza_radios_pending", null)
	if not (pending_val is Array):
		return Result.failure("应生成 pizza radios pending（Array），实际: %s" % str(pending_val))
	var pending: Array = pending_val
	if pending.size() != 3:
		return Result.failure("pizza radios pending 应为 3，实际: %d" % pending.size())

	var adv1 := engine.execute_command(Command.create_system("advance_phase"))
	if adv1.ok:
		return Result.failure("存在 pending 时不应允许推进阶段")

	# 依次放置 3 张 radio（使用 tile 内的合法位置）
	var p1 := engine.execute_command(Command.create("place_pizza_radio", 0, {"position": [2, 3]}))
	if not p1.ok:
		return Result.failure("place_pizza_radio(1) 失败: %s" % p1.error)
	var p2 := engine.execute_command(Command.create("place_pizza_radio", 0, {"position": [3, 3]}))
	if not p2.ok:
		return Result.failure("place_pizza_radio(2) 失败: %s" % p2.error)
	var p3 := engine.execute_command(Command.create("place_pizza_radio", 0, {"position": [4, 3]}))
	if not p3.ok:
		return Result.failure("place_pizza_radio(3) 失败: %s" % p3.error)

	# 放完后应允许推进阶段
	var adv2 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv2.ok:
		return Result.failure("放完 radio 后应允许推进阶段: %s" % adv2.error)

	# 检查 marketing_instances：3 个 radio，product=pizza，duration=2，employee_type=__milestone__
	state = engine.get_state()
	var radios := []
	for inst_val in state.marketing_instances:
		if inst_val is Dictionary and str(Dictionary(inst_val).get("type", "")) == "radio":
			radios.append(inst_val)
	if radios.size() != 3:
		return Result.failure("应存在 3 个 radio marketing_instances，实际: %d" % radios.size())
	var seen := {}
	for inst_val in radios:
		var inst: Dictionary = inst_val
		if str(inst.get("product", "")) != "pizza":
			return Result.failure("radio.product 应为 pizza，实际: %s" % str(inst.get("product", null)))
		if int(inst.get("remaining_duration", 0)) != 2:
			return Result.failure("radio.remaining_duration 应为 2，实际: %s" % str(inst.get("remaining_duration", null)))
		if str(inst.get("employee_type", "")) != "__milestone__":
			return Result.failure("radio.employee_type 应为 __milestone__，实际: %s" % str(inst.get("employee_type", null)))
		var bn: int = int(inst.get("board_number", -1))
		seen[bn] = true
	for bn in [1, 2, 3]:
		if not seen.has(bn):
			return Result.failure("应使用 base radio #%d" % bn)

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

static func _set_road(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(5, 5) # 1 tile
	var cells := _build_empty_cells(grid_size)

	# 给 radio 营销提供邻路放置点：y=2 横向道路，使 y=1 上的若干空位都邻接道路
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road(cells, Vector2i(x, 2), dirs)

	# 餐厅在底部 2x2，并有入口邻接道路
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)

	# 3 个 1x1 房屋，编号 1,2,3
	_set_house_1x1(cells, "h1", 1, Vector2i(2, 1))
	_set_house_1x1(cells, "h2", 2, Vector2i(3, 1))
	_set_house_1x1(cells, "h3", 3, Vector2i(4, 1))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h1": {"house_id": "h1", "house_number": 1, "anchor_pos": Vector2i(2, 1), "cells": [Vector2i(2, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h2": {"house_id": "h2", "house_number": 2, "anchor_pos": Vector2i(3, 1), "cells": [Vector2i(3, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h3": {"house_id": "h3", "house_number": 3, "anchor_pos": Vector2i(4, 1), "cells": [Vector2i(4, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 3), "entrance_pos": Vector2i(1, 2), "cells": rest_cells},
		},
		"drink_sources": [],
		"next_house_number": 4,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	MapRuntimeClass.invalidate_road_graph(state)
