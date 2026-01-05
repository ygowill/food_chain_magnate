# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST COKE SOLD
# - 触发：Dinnertime 售卖包含 soda（规则原文 coke，对应本项目 product_id=soda）
# - 效果：获得 freezer（复用 gain_fridge=10），Cleanup 后 soda 库存应保留到 10
class_name NewMilestonesCokeSoldV2Test
extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const Phase = PhaseDefsClass.Phase

const MILESTONE_ID := "first_coke_sold"

static func run(player_count: int = 2, seed_val: int = 889900) -> Result:
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

	# 准备：玩家0 有 soda 库存，且房屋有 soda 需求
	var inv: Dictionary = state.players[0]["inventory"]
	inv["soda"] = 1
	state.players[0]["inventory"] = inv

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "soda"}]
	houses["h0"] = h
	state.map["houses"] = houses

	# 直接运行 DINNERTIME settlement（含模块 extension：ProductSold）
	var reg = engine.phase_manager.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 未设置")
	var run_any = reg.run(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, state, engine.phase_manager)
	if not (run_any is Result):
		return Result.failure("运行晚餐结算失败: 返回类型错误（期望 Result）")
	var r: Result = run_any
	if not r.ok:
		return Result.failure("运行晚餐结算失败: %s" % r.error)

	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	# Cleanup：有 freezer 后库存不清空（soda 限幅到 10）
	var inv2: Dictionary = state.players[0]["inventory"]
	inv2["soda"] = 12
	state.players[0]["inventory"] = inv2
	var cl := CleanupSettlementClass.apply(state)
	if not cl.ok:
		return Result.failure("CleanupSettlement 失败: %s" % cl.error)
	var after: int = int(state.players[0]["inventory"].get("soda", -1))
	if after != 10:
		return Result.failure("有 freezer 时 soda 应限幅为 10，实际: %d" % after)

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
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	# y=3 为横向道路
	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 3), dirs)

	# 餐厅在左下 2x2（入口邻接道路）
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)

	# 房屋在道路上方 1x1（邻接道路）
	_set_house_1x1(cells, "h0", 1, Vector2i(3, 2))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h0": {
				"house_id": "h0",
				"house_number": 1,
				"anchor_pos": Vector2i(3, 2),
				"cells": [Vector2i(3, 2)],
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			}
		},
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
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	MapRuntimeClass.invalidate_road_graph(state)

