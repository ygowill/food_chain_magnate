# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST NEW RESTAURANT
# - 触发：首次在 Working 阶段放置新餐厅
# - 效果：允许占用 mailbox(#5-#10) 放置一个永久邮箱（同街区=mailbox block，且必须是自家餐厅街区）
class_name NewMilestonesNewRestaurantV2Test
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

const MILESTONE_ID := "first_new_restaurant"
const ACTION_ID := "place_new_restaurant_mailbox"
const USED_KEY := "new_milestones_first_new_restaurant_mailbox_used"
const EMPLOYEE_TYPE_SENTINEL := "__milestone_mailbox__"

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

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	# 推进到 PlaceRestaurants 子阶段
	for i in range(6):
		var pass_all := TestPhaseUtilsClass.pass_all_players_in_working_sub_phase(engine)
		if not pass_all.ok:
			return pass_all
		var sub := engine.execute_command(Command.create_system("advance_phase", {"target": "sub_phase"}))
		if not sub.ok:
			return Result.failure("推进到 PlaceRestaurants 子阶段失败(step=%d): %s" % [i, sub.error])

	var state := engine.get_state()
	if state.phase != "Working" or state.sub_phase != "PlaceRestaurants":
		return Result.failure("应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	# 准备 1 张在岗本地经理（从池取卡，保持守恒）
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add.ok:
		return Result.failure("添加 local_manager 失败: %s" % add.error)

	# 放置一个新餐厅（Working）
	var cmd_place_rest := _find_first_valid_restaurant_placement(engine, actor)
	if cmd_place_rest == null:
		return Result.failure("找不到合法的餐厅放置点（可能是地图数据异常）")
	var exec_place_rest := engine.execute_command(cmd_place_rest)
	if not exec_place_rest.ok:
		return Result.failure("放置新餐厅失败: %s (%s)" % [exec_place_rest.error, str(cmd_place_rest)])

	state = engine.get_state()
	var milestones: Array = state.players[actor].get("milestones", [])
	if not milestones.has(MILESTONE_ID):
		return Result.failure("放置新餐厅后应获得里程碑 %s，实际: %s" % [MILESTONE_ID, str(milestones)])

	# 使用确定性小地图构造“同街区可放置点”，避免依赖随机地图的空格分布
	_apply_simple_map_with_restaurant(state, actor)

	# 放置永久 mailbox（占用 #5..#10），固定放在 (1,2)：与餐厅同 block 且邻接道路
	var cmd_mailbox := Command.create(ACTION_ID, actor, {
		"board_number": 5,
		"product": "burger",
		"position": [1, 2],
	})
	var exec_mailbox := engine.execute_command(cmd_mailbox)
	if not exec_mailbox.ok:
		return Result.failure("放置永久 mailbox 失败: %s (%s)" % [exec_mailbox.error, str(cmd_mailbox)])

	state = engine.get_state()
	if not (state.map is Dictionary) or not (state.map.get("marketing_placements", null) is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	var placements: Dictionary = state.map["marketing_placements"]
	if not placements.has("5"):
		return Result.failure("应占用 mailbox #5（marketing_placements[\"5\"] 缺失）")
	var p: Dictionary = placements["5"]
	if int(p.get("remaining_duration", 0)) != -1:
		return Result.failure("永久 mailbox remaining_duration 应为 -1，实际: %s" % str(p.get("remaining_duration", null)))

	var found := false
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", -1)) != 5:
			continue
		if int(inst.get("remaining_duration", 0)) != -1:
			return Result.failure("marketing_instance.remaining_duration 应为 -1，实际: %s" % str(inst.get("remaining_duration", null)))
		if str(inst.get("employee_type", "")) != EMPLOYEE_TYPE_SENTINEL:
			return Result.failure("marketing_instance.employee_type 应为 sentinel，实际: %s" % str(inst.get("employee_type", null)))
		found = true
		break
	if not found:
		return Result.failure("marketing_instances 中缺少 board_number=5 的实例")

	var used_val = state.players[actor].get(USED_KEY, null)
	if not (used_val is bool) or not bool(used_val):
		return Result.failure("player.%s 应为 true" % USED_KEY)

	# 再次放置应被拒绝（一次性）
	var exec_again := engine.execute_command(cmd_mailbox)
	if exec_again.ok:
		return Result.failure("第二次放置永久 mailbox 不应允许")

	return Result.success()

static func _find_first_valid_restaurant_placement(engine: GameEngine, actor: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]
	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var cmd := Command.create("place_restaurant", actor, {"position": [x, y], "rotation": r})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd
	return null

static func _find_first_valid_mailbox_placement(engine: GameEngine, actor: int, board_number: int, product: String) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor(ACTION_ID)
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	for y in range(grid.y):
		for x in range(grid.x):
			var cmd := Command.create(ACTION_ID, actor, {
				"board_number": board_number,
				"product": product,
				"position": [x, y],
			})
			var vr := executor.validate(state, cmd)
			if vr.ok:
				return cmd
	return null

static func _apply_simple_map_with_restaurant(state: GameState, owner: int) -> void:
	# 5x5：x=2 为纵向道路，将地图分成左右两个 block
	var grid_size := Vector2i(5, 5)
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			var road_segments: Array = []
			if x == 2:
				var dirs: Array = []
				if y > 0:
					dirs.append("N")
				if y < grid_size.y - 1:
					dirs.append("S")
				road_segments = [{"dirs": dirs}]
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": road_segments,
				"blocked": false
			})
		cells.append(row)

	# 餐厅占用左上 2x2（同 block），并与道路相邻（餐厅不占道路格）
	for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": "rest_test",
			"dynamic": true
		}

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_test": {
				"restaurant_id": "rest_test",
				"owner": owner,
				"anchor_pos": Vector2i(0, 0),
				"entrance_pos": Vector2i(1, 1),
				"cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
			},
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
