# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST BRAND MANAGER USED
# - 触发：brand_manager 放置 airplane
# - 效果：本回合可为该 airplane 追加第二种商品（A→B 顺序结算），不可叠加/不可保存
class_name NewMilestonesBrandManagerV2Test
extends RefCounted

const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "first_brand_manager_used"

static func run(player_count: int = 2, seed_val: int = 223344) -> Result:
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

	state.phase = "Working"
	state.sub_phase = "Marketing"

	# 给玩家0 添加 1 张在岗 brand_manager（从池取卡，保持守恒）
	if int(state.employee_pool.get("brand_manager", 0)) <= 0:
		return Result.failure("employee_pool 中没有 brand_manager")
	state.employee_pool["brand_manager"] = int(state.employee_pool.get("brand_manager", 0)) - 1
	state.players[0]["employees"].append("brand_manager")

	# brand_manager 放置 airplane（商品 A=beer）
	var cmd := Command.create("initiate_marketing", 0, {
		"employee_type": "brand_manager",
		"board_number": 4,
		"product": "beer",
		"duration": 1,
		"position": [0, 11],
	})
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("initiate_marketing 失败: %s" % r.error)

	state = engine.get_state()
	if not Array(state.players[0].get("milestones", [])).has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s" % MILESTONE_ID)

	# 追加第二种商品 B=burger
	var cmd2 := Command.create("set_brand_manager_airplane_second_good", 0, {
		"product_b": "burger",
	})
	var r2 := engine.execute_command(cmd2)
	if not r2.ok:
		return Result.failure("set_brand_manager_airplane_second_good 失败: %s" % r2.error)

	state = engine.get_state()
	var mk := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk.ok:
		return Result.failure("MarketingSettlement 失败: %s" % mk.error)

	var houses: Dictionary = state.map.get("houses", {})
	for hid in ["h20", "h21", "h22"]:
		var h: Dictionary = houses.get(hid, {})
		var demands: Array = h.get("demands", [])
		if demands.size() != 2:
			return Result.failure("airplane 双商品后 %s 需求应为 2，实际: %d" % [hid, demands.size()])
		if str(demands[0].get("product", "")) != "beer":
			return Result.failure("airplane 双商品后 %s 第1个需求应为 beer，实际: %s" % [hid, str(demands[0].get("product", null))])
		if str(demands[1].get("product", "")) != "burger":
			return Result.failure("airplane 双商品后 %s 第2个需求应为 burger，实际: %s" % [hid, str(demands[1].get("product", null))])

	# 同回合不可再次设置
	var r3 := engine.execute_command(cmd2)
	if r3.ok:
		return Result.failure("同回合不应允许再次设置第二种商品")

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

static func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(15, 15) # 3x3 tiles
	var tile_grid_size := Vector2i(3, 3)
	var cells := _build_empty_cells(grid_size)

	# 放置 1x1 房屋：tile row=2 (y=10) 内应被 airplane 影响
	_set_house_1x1(cells, "h20", 6, Vector2i(0, 10))  # tile (0,2)
	_set_house_1x1(cells, "h21", 7, Vector2i(5, 10))  # tile (1,2)
	_set_house_1x1(cells, "h22", 8, Vector2i(10, 10)) # tile (2,2)

	var houses := {}
	var defs := [
		{"id": "h20", "n": 6, "pos": Vector2i(0, 10)},
		{"id": "h21", "n": 7, "pos": Vector2i(5, 10)},
		{"id": "h22", "n": 8, "pos": Vector2i(10, 10)},
	]
	for d in defs:
		var hid := str(d.get("id", ""))
		var pos: Vector2i = d.get("pos", Vector2i.ZERO)
		houses[hid] = {
			"house_id": hid,
			"house_number": int(d.get("n", 0)),
			"anchor_pos": pos,
			"cells": [pos],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": tile_grid_size,
		"cells": cells,
		"houses": houses,
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(7, 14),
				"entrance_pos": Vector2i(7, 14),
			}
		},
		"drink_sources": [],
		"next_house_number": 9,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
	MapRuntimeClass.invalidate_road_graph(state)
