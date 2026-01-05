# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST CAMPAIGN MANAGER USED
# - 触发：使用 campaign_manager 发起营销
# - 效果：同回合可额外放置第二张同类型板件（同商品/同持续时间）
# - 员工应在两张板件都到期后才从 busy_marketers 返回
class_name NewMilestonesCampaignManagerV2Test
extends RefCounted

const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "first_campaign_manager_used"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
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

	# 给玩家0 添加 1 张在岗 campaign_manager（从池取卡，保持守恒）
	if int(state.employee_pool.get("campaign_manager", 0)) <= 0:
		return Result.failure("employee_pool 中没有 campaign_manager")
	state.employee_pool["campaign_manager"] = int(state.employee_pool.get("campaign_manager", 0)) - 1
	state.players[0]["employees"].append("campaign_manager")

	# 发起 mailbox #5（duration=1，方便验证到期释放时机；2P 下 mailbox 有多张可用）
	var cmd := Command.create("initiate_marketing", 0, {
		"employee_type": "campaign_manager",
		"board_number": 5,
		"product": "burger",
		"duration": 1,
		"position": [3, 2],
	})
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("initiate_marketing 失败: %s" % r.error)

	state = engine.get_state()
	var milestones0: Array = state.players[0].get("milestones", [])
	if not milestones0.has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones0)])

	# 追加放置第二张 mailbox #6（同商品/同持续时间）
	var cmd2 := Command.create("place_campaign_manager_second_tile", 0, {
		"board_number": 6,
		"position": [1, 2],
	})
	var r2 := engine.execute_command(cmd2)
	if not r2.ok:
		return Result.failure("place_campaign_manager_second_tile 失败: %s" % r2.error)

	state = engine.get_state()
	if state.players[0]["busy_marketers"].has("campaign_manager") == false:
		return Result.failure("campaign_manager 应仍在 busy_marketers 中")

	# 两张实例应共享 link_id
	var link := ""
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", -1)) == 5:
			link = str(inst.get("link_id", ""))
			break
	if link.is_empty():
		return Result.failure("board #5 应存在 link_id")
	var link2 := ""
	for inst_val2 in state.marketing_instances:
		if not (inst_val2 is Dictionary):
			continue
		var inst2: Dictionary = inst_val2
		if int(inst2.get("board_number", -1)) == 6:
			link2 = str(inst2.get("link_id", ""))
			break
	if link2 != link:
		return Result.failure("第二张板件应与第一张共享 link_id")

	# Marketing 结算一轮：两张都到期，员工应在最后一张到期时回到 reserve_employees
	var mk := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk.ok:
		return Result.failure("MarketingSettlement 失败: %s" % mk.error)
	if state.players[0]["busy_marketers"].has("campaign_manager"):
		return Result.failure("两张板件到期后，campaign_manager 不应仍在 busy_marketers")
	if not state.players[0]["reserve_employees"].has("campaign_manager"):
		return Result.failure("两张板件到期后，campaign_manager 应回到 reserve_employees")

	# 再次追加放置：本回合应已消耗能力
	var r3 := engine.execute_command(cmd2)
	if r3.ok:
		return Result.failure("同回合不应允许再次追加放置第二张板件")

	# 已获得里程碑的后续回合：不应再次获得“第二张板件”能力
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(player_count, seed_val + 1, enabled_modules)
	if not init2.ok:
		return Result.failure("初始化失败(2): %s" % init2.error)
	var state2 := engine2.get_state()
	_force_turn_order(state2)
	_apply_test_map(state2)
	state2.phase = "Working"
	state2.sub_phase = "Marketing"
	state2.players[0]["milestones"].append(MILESTONE_ID)
	if int(state2.employee_pool.get("campaign_manager", 0)) <= 0:
		return Result.failure("employee_pool 中没有 campaign_manager(2)")
	state2.employee_pool["campaign_manager"] = int(state2.employee_pool.get("campaign_manager", 0)) - 1
	state2.players[0]["employees"].append("campaign_manager")
	var r4 := engine2.execute_command(cmd)
	if not r4.ok:
		return Result.failure("initiate_marketing(2) 失败: %s" % r4.error)
	var r5 := engine2.execute_command(cmd2)
	if r5.ok:
		return Result.failure("后续回合不应允许 place_campaign_manager_second_tile")

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

	# 餐厅在底部 2x2，并有入口邻接道路
	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
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
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	MapRuntimeClass.invalidate_road_graph(state)
