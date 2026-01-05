# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST BRAND DIRECTOR USED
# - 触发：使用 brand_director 发起营销（任意类型）
# - 效果：
#   - 之后你放置的 radio 永久（duration=-1）
#   - brand_director 忙碌到游戏结束（营销到期也不返回）
class_name NewMilestonesBrandDirectorV2Test
extends RefCounted

const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MILESTONE_ID := "first_brand_director_used"

static func run(player_count: int = 2, seed_val: int = 334455) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

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

	# 场景A：brand_director 放置 radio -> 永久；且 busy 到游戏结束
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map(state)
	state.phase = "Working"
	state.sub_phase = "Marketing"
	if int(state.employee_pool.get("brand_director", 0)) <= 0:
		return Result.failure("员工池中没有 brand_director")
	state.employee_pool["brand_director"] = int(state.employee_pool.get("brand_director", 0)) - 1
	state.players[0]["employees"].append("brand_director")

	var cmd := Command.create("initiate_marketing", 0, {
		"employee_type": "brand_director",
		"board_number": 1,
		"product": "soda",
		"duration": 1,
		"position": [2, 2],
	})
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("initiate_marketing(radio) 失败: %s" % r.error)

	state = engine.get_state()
	if not Array(state.players[0].get("milestones", [])).has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s" % MILESTONE_ID)
	if not Array(state.players[0].get("busy_marketers", [])).has("brand_director"):
		return Result.failure("brand_director 应在 busy_marketers 中")
	if state.marketing_instances.is_empty():
		return Result.failure("应存在 marketing_instances")
	if int(state.marketing_instances[0].get("remaining_duration", 0)) != -1:
		return Result.failure("radio 应为永久（remaining_duration=-1），实际: %s" % str(state.marketing_instances[0].get("remaining_duration", null)))

	var mk := MarketingSettlementClass.apply(state, engine.phase_manager.get_marketing_range_calculator(), 1, engine.phase_manager)
	if not mk.ok:
		return Result.failure("MarketingSettlement 失败: %s" % mk.error)
	if state.marketing_instances.is_empty():
		return Result.failure("radio 永久不应到期移除")
	if not Array(state.players[0].get("busy_marketers", [])).has("brand_director"):
		return Result.failure("brand_director 不应被释放")

	# 场景B：brand_director 放置 mailbox(duration=1) -> 不永久，但依旧不释放
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(player_count, seed_val + 1, enabled_modules)
	if not init2.ok:
		return Result.failure("初始化失败(2): %s" % init2.error)
	var state2 := engine2.get_state()
	_force_turn_order(state2)
	_apply_test_map(state2)
	state2.phase = "Working"
	state2.sub_phase = "Marketing"
	if int(state2.employee_pool.get("brand_director", 0)) <= 0:
		return Result.failure("员工池中没有 brand_director")
	state2.employee_pool["brand_director"] = int(state2.employee_pool.get("brand_director", 0)) - 1
	state2.players[0]["employees"].append("brand_director")

	var cmd2 := Command.create("initiate_marketing", 0, {
		"employee_type": "brand_director",
		"board_number": 5,
		"product": "soda",
		"duration": 1,
		"position": [2, 2],
	})
	var r2 := engine2.execute_command(cmd2)
	if not r2.ok:
		return Result.failure("initiate_marketing(mailbox) 失败: %s" % r2.error)
	state2 = engine2.get_state()
	if int(state2.marketing_instances[0].get("remaining_duration", 0)) != 1:
		return Result.failure("mailbox 不应被设置为永久，实际: %s" % str(state2.marketing_instances[0].get("remaining_duration", null)))

	var mk2 := MarketingSettlementClass.apply(state2, engine2.phase_manager.get_marketing_range_calculator(), 1, engine2.phase_manager)
	if not mk2.ok:
		return Result.failure("MarketingSettlement(2) 失败: %s" % mk2.error)
	if not state2.marketing_instances.is_empty():
		return Result.failure("mailbox 应到期移除")
	if not Array(state2.players[0].get("busy_marketers", [])).has("brand_director"):
		return Result.failure("mailbox 到期后 brand_director 仍应保持忙碌")
	if Array(state2.players[0].get("reserve_employees", [])).has("brand_director"):
		return Result.failure("brand_director 不应返回 reserve_employees")

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

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(15, 15)
	var tile_grid_size := Vector2i(3, 3)
	var cells := _build_empty_cells(grid_size)

	# (2,2) 放置 mailbox 需要邻接道路：在 (2,3) 放一段道路
	_set_road(cells, Vector2i(2, 3), ["N", "S"])

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": tile_grid_size,
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(7, 14),
				"entrance_pos": Vector2i(7, 14),
			}
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
	MapRuntimeClass.invalidate_road_graph(state)
