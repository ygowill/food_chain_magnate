# 移动餐厅规则测试（P2）
# 验证：
# - 移动餐厅需要在岗的区域经理
# - PlaceRestaurants 子阶段中 place/move 共享次数上限
# - 免下车（drivethrough 标签）：只要在岗即生效，餐厅四角都视为入口点
class_name MoveRestaurantRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# Setup：每位玩家放置 1 个餐厅（用于后续移动测试）
	var setup := _place_initial_restaurants(engine)
	if not setup.ok:
		return setup

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	# 推进到 PlaceRestaurants 子阶段（Recruit -> Train -> Marketing -> GetFood -> GetDrinks -> PlaceHouses -> PlaceRestaurants）
	var to_place_restaurants := TestPhaseUtilsClass.advance_until_working_sub_phase(engine, DefsClass.SUB_PHASE_PLACE_RESTAURANTS, 20)
	if not to_place_restaurants.ok:
		return to_place_restaurants

	var state := engine.get_state()
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		return Result.failure("应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	var rest_ids := StructuresClass.get_player_restaurants(state, actor)
	if rest_ids.is_empty():
		return Result.failure("玩家应至少拥有 1 个餐厅")
	var rest_id := str(rest_ids[0])

	# 1) 没有区域经理：应拒绝移动
	var cmd_fail := Command.create("move_restaurant", actor, {"restaurant_id": rest_id, "position": [0, 0], "rotation": 0})
	var exec_fail := engine.execute_command(cmd_fail)
	if exec_fail.ok:
		return Result.failure("没有区域经理时不应允许移动餐厅")
	if str(exec_fail.error).find("区域经理") < 0:
		return Result.failure("拒绝原因应包含'区域经理'，实际: %s" % exec_fail.error)

	# 2) 给玩家添加 1 名在岗区域经理（从池取卡，保持守恒）
	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "regional_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 regional_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "regional_manager", false)
	if not add.ok:
		return Result.failure("添加 regional_manager 失败: %s" % add.error)

	# 在岗即可免下车：入口点应为餐厅四角（不依赖“本回合使用”）
	state = engine.get_state()
	var rest_before: Dictionary = state.map.get("restaurants", {}).get(rest_id, {})
	var ep_before_r := StructuresClass.get_restaurant_entrance_points(state, rest_id, rest_before)
	if not ep_before_r.ok:
		return ep_before_r
	var corners_r := _get_footprint_corners(rest_before.get("cells", []), "移动前餐厅")
	if not corners_r.ok:
		return corners_r
	var ep_before_check := _assert_entrance_points_match_corners(ep_before_r.value, corners_r.value, "regional_manager 在岗")
	if not ep_before_check.ok:
		return ep_before_check

	state = engine.get_state()
	var old_anchor: Vector2i = state.map.get("restaurants", {}).get(rest_id, {}).get("anchor_pos", Vector2i(-1, -1))
	var old_rotation: int = int(state.map.get("restaurants", {}).get(rest_id, {}).get("rotation", 0))

	var cmd_ok := _find_first_valid_move(engine, actor, rest_id, old_anchor, old_rotation)
	if cmd_ok == null:
		return Result.failure("找不到合法的餐厅移动位置（可能是地图数据异常）")

	var exec_ok := engine.execute_command(cmd_ok)
	if not exec_ok.ok:
		return Result.failure("移动餐厅应成功，但失败: %s (%s)" % [exec_ok.error, str(cmd_ok)])

	state = engine.get_state()
	var rest_after: Dictionary = state.map.get("restaurants", {}).get(rest_id, {})
	if rest_after.is_empty():
		return Result.failure("移动后餐厅应存在: %s" % rest_id)

	var ep_after_r := StructuresClass.get_restaurant_entrance_points(state, rest_id, rest_after)
	if not ep_after_r.ok:
		return ep_after_r
	var corners_after_r := _get_footprint_corners(rest_after.get("cells", []), "移动后餐厅")
	if not corners_after_r.ok:
		return corners_after_r
	var ep_after_check := _assert_entrance_points_match_corners(ep_after_r.value, corners_after_r.value, "移动后 regional_manager 在岗")
	if not ep_after_check.ok:
		return ep_after_check

	# 3) 与 place_restaurant 共享次数：只有 1 名区域经理时，移动后不应再允许放置餐厅
	var cmd_place := Command.create("place_restaurant", actor, {"position": [0, 0], "rotation": 0})
	var exec_place := engine.execute_command(cmd_place)
	if exec_place.ok:
		return Result.failure("移动餐厅后不应允许继续放置餐厅（次数应耗尽）")
	if str(exec_place.error).find("已用完") < 0:
		return Result.failure("放置餐厅被拒绝应提示次数已用完，实际: %s" % exec_place.error)

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
		"restaurant_id": rest_id,
	})

static func _place_initial_restaurants(engine: GameEngine) -> Result:
	var placed := {}
	for p in range(engine.get_state().players.size()):
		placed[p] = false

	var safety := 0
	while true:
		var done := true
		for p in placed.keys():
			if not placed[p]:
				done = false
				break
		if done:
			break

		safety += 1
		if safety > 60:
			return Result.failure("Setup 放置餐厅循环超出安全上限")

		var state := engine.get_state()
		var current_player := state.get_current_player_id()

		# Setup 第一步：先秘密选择储备卡（不能 skip）
		if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			var pick := engine.execute_command(Command.create("select_reserve_card", current_player, {"selected_index": 0}))
			if not pick.ok:
				return Result.failure("选择储备卡失败: %s" % pick.error)
			continue

		if not placed[current_player]:
			var cmd_place := _find_first_valid_placement(engine, "place_restaurant", current_player)
			if cmd_place == null:
				return Result.failure("找不到玩家 %d 的合法餐厅放置点" % current_player)
			var exec_place := engine.execute_command(cmd_place)
			if not exec_place.ok:
				return Result.failure("放置餐厅失败: %s (%s)" % [exec_place.error, str(cmd_place)])
			placed[current_player] = true

		# 结束回合
		var cmd_skip := Command.create(ActionIdsClass.SKIP, current_player)
		var exec_skip := engine.execute_command(cmd_skip)
		if not exec_skip.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip.error, str(cmd_skip)])

	return Result.success()

static func _find_first_valid_placement(engine: GameEngine, action_id: String, actor: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor(action_id)
	if executor == null:
		return null

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var cmd := Command.create(action_id, actor, {
					"position": [x, y],
					"rotation": rot
				})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null

static func _get_footprint_corners(cells_any: Array, label: String) -> Result:
	if cells_any == null or cells_any.is_empty():
		return Result.failure("%s cells 为空" % label)
	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	for i in range(cells_any.size()):
		var c_val = cells_any[i]
		if not (c_val is Vector2i):
			return Result.failure("%s cells[%d] 类型错误（期望 Vector2i）" % [label, i])
		var c: Vector2i = c_val
		min_x = min(min_x, c.x)
		min_y = min(min_y, c.y)
		max_x = max(max_x, c.x)
		max_y = max(max_y, c.y)
	return Result.success([
		Vector2i(min_x, min_y),
		Vector2i(max_x, min_y),
		Vector2i(min_x, max_y),
		Vector2i(max_x, max_y),
	])

static func _assert_entrance_points_match_corners(points_any: Array, corners_any: Array, label: String) -> Result:
	if points_any == null:
		return Result.failure("%s entrance_points 为空" % label)
	if corners_any == null or corners_any.is_empty():
		return Result.failure("%s corners 为空" % label)
	if points_any.size() != 4:
		return Result.failure("%s entrance_points 应为 4 个角点，实际: %s" % [label, str(points_any)])
	var set := {}
	for i in range(points_any.size()):
		var p_val = points_any[i]
		if not (p_val is Vector2i):
			return Result.failure("%s entrance_points[%d] 类型错误（期望 Vector2i）" % [label, i])
		set[Vector2i(p_val)] = true
	for j in range(corners_any.size()):
		var c_val = corners_any[j]
		if c_val is Vector2i and not set.has(Vector2i(c_val)):
			return Result.failure("%s entrance_points 缺少角点 %s，实际: %s" % [label, str(c_val), str(points_any)])
	return Result.success(true)

static func _find_first_valid_move(engine: GameEngine, actor: int, rest_id: String, old_anchor: Vector2i, old_rotation: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("move_restaurant")
	if executor == null:
		return null

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var anchor := Vector2i(x, y)
				if anchor == old_anchor and rot == old_rotation:
					continue
				var cmd := Command.create("move_restaurant", actor, {
					"restaurant_id": rest_id,
					"position": [x, y],
					"rotation": rot
				})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null
