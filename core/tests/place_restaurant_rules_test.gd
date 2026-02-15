# 放置餐厅规则测试（P1）
# 验证：Working/PlaceRestaurants 需要在岗的本地/大区经理；每张卡每子阶段仅可使用一次；
# 免下车（drivethrough 标签）：只要在岗即生效，餐厅四角都视为入口点；
# 本地经理（local_manager）放置的新餐厅为“即将开业”，在 Cleanup 才正式加入 restaurants。
class_name PlaceRestaurantRulesTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 为避免测试推进到 Payday 时因薪水不足中断，给每位玩家少量现金（保持现金守恒）。
	var s := engine.get_state()
	for pid in range(player_count):
		var grant := StateUpdaterClass.player_receive_from_bank(s, pid, 20)
		if not grant.ok:
			return Result.failure("发放测试现金失败: %s" % grant.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		return Result.failure("应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("无法获取当前玩家")

	# 1) 没有本地/大区经理：应拒绝放置
	var cmd_fail := Command.create("place_restaurant", actor, {"position": [0, 0], "rotation": 0})
	var exec_fail := engine.execute_command(cmd_fail)
	if exec_fail.ok:
		return Result.failure("没有本地/大区经理时不应允许放置餐厅")
	if str(exec_fail.error).find("本地经理") < 0 and str(exec_fail.error).find("区域经理") < 0 and str(exec_fail.error).find("大区经理") < 0:
		return Result.failure("拒绝原因应包含'本地经理/区域经理'，实际: %s" % exec_fail.error)

	# 当前玩家应已有 1 个起始餐厅（Setup 放置）
	var base_rest_ids := StructuresClass.get_player_restaurants(state, actor)
	if base_rest_ids.is_empty():
		return Result.failure("玩家应至少拥有 1 个起始餐厅")
	var base_rest_id := str(base_rest_ids[0]).strip_edges()
	if base_rest_id.is_empty():
		return Result.failure("起始餐厅 id 为空")
	var base_rest: Dictionary = state.map.get("restaurants", {}).get(base_rest_id, {})
	if base_rest.is_empty():
		return Result.failure("起始餐厅不存在: %s" % base_rest_id)

	# 无免下车：默认仅 1 个入口点
	var ep0_read := StructuresClass.get_restaurant_entrance_points(state, base_rest_id, base_rest)
	if not ep0_read.ok:
		return ep0_read
	var ep0_any: Array = ep0_read.value
	if ep0_any.size() != 1:
		return Result.failure("无免下车时入口点应为 1 个，实际: %s" % str(ep0_any))

	# 2) 给玩家添加 1 名在岗本地经理（从池取卡，保持守恒）
	state = engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "local_manager", false)
	if not add.ok:
		return Result.failure("添加 local_manager 失败: %s" % add.error)

	# 在岗即可免下车：起始餐厅入口点应为四角
	state = engine.get_state()
	base_rest = state.map.get("restaurants", {}).get(base_rest_id, {})
	var ep1_read := StructuresClass.get_restaurant_entrance_points(state, base_rest_id, base_rest)
	if not ep1_read.ok:
		return ep1_read
	var corners_r := _get_footprint_corners(base_rest.get("cells", []), "起始餐厅")
	if not corners_r.ok:
		return corners_r
	var corners: Array = corners_r.value
	var ep1_check := _assert_entrance_points_match_corners(ep1_read.value, corners, "local_manager 在岗")
	if not ep1_check.ok:
		return ep1_check

	# 找一个合法的餐厅放置点
	var cmd_ok := _find_first_valid_restaurant_placement(engine, actor, {"employee_type": "local_manager"})
	if cmd_ok == null:
		return Result.failure("找不到合法的餐厅放置点（可能是地图数据异常）")

	# GameEngine.execute_command 的返回值是“新 state”，不是 action 的返回值；餐厅 id 可由 next_restaurant_id 推导。
	state = engine.get_state()
	var next_id_val = state.map.get("next_restaurant_id", null)
	if not (next_id_val is int):
		return Result.failure("map.next_restaurant_id 类型错误（期望 int）")
	var next_id_before: int = int(next_id_val)

	var exec_ok := engine.execute_command(cmd_ok)
	if not exec_ok.ok:
		return Result.failure("有本地经理时放置餐厅应成功，但失败: %s (%s)" % [exec_ok.error, str(cmd_ok)])

	var placed_rest_id := "rest_%d" % next_id_before

	# opening_soon：本回合不应立即加入 map.restaurants / player.restaurants，应写入 round_state.opening_soon_restaurants
	state = engine.get_state()
	if state.map.get("restaurants", {}).has(placed_rest_id):
		return Result.failure("opening_soon 餐厅不应立即加入 map.restaurants: %s" % placed_rest_id)
	var plist: Array = state.players[actor].get("restaurants", [])
	if plist.has(placed_rest_id):
		return Result.failure("opening_soon 餐厅不应立即加入 player.restaurants: %s" % placed_rest_id)
	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	var pending_val = (state.round_state as Dictionary).get("opening_soon_restaurants", null)
	if not (pending_val is Array):
		return Result.failure("opening_soon_restaurants 缺失或类型错误（期望 Array）")
	var pending: Array = pending_val
	var pending_entry: Dictionary = {}
	for e_val in pending:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		if str(e.get("restaurant_id", "")).strip_edges() == placed_rest_id:
			pending_entry = e
			break
	if pending_entry.is_empty():
		return Result.failure("opening_soon_restaurants 未包含新餐厅: %s" % placed_rest_id)

	# opening_soon：地图格子上的 structure 应标记 opening_soon=true
	var pending_cells_val = pending_entry.get("cells", null)
	if not (pending_cells_val is Array):
		return Result.failure("opening_soon_restaurants[%s].cells 类型错误（期望 Array）" % placed_rest_id)
	var pending_cells: Array = pending_cells_val
	if pending_cells.is_empty():
		return Result.failure("opening_soon_restaurants[%s].cells 为空" % placed_rest_id)
	for i in range(pending_cells.size()):
		var cpos_val = pending_cells[i]
		if not (cpos_val is Vector2i):
			return Result.failure("opening_soon_restaurants[%s].cells[%d] 类型错误（期望 Vector2i）" % [placed_rest_id, i])
		var cpos: Vector2i = cpos_val
		var idx := CoordsClass.world_to_index(state, cpos)
		var cell: Dictionary = state.map.cells[idx.y][idx.x]
		var s_val = cell.get("structure", null)
		if not (s_val is Dictionary):
			return Result.failure("opening_soon 餐厅格子结构缺失: %s" % str(cpos))
		var structure: Dictionary = s_val
		if str(structure.get("piece_id", "")) != "restaurant":
			return Result.failure("opening_soon 餐厅格子 piece_id 错误: %s" % str(structure.get("piece_id", null)))
		if str(structure.get("restaurant_id", "")) != placed_rest_id:
			return Result.failure("opening_soon 餐厅格子 restaurant_id 错误: %s" % str(structure.get("restaurant_id", null)))
		var os_val = structure.get("opening_soon", null)
		if not (os_val is bool) or not bool(os_val):
			return Result.failure("opening_soon 餐厅格子应标记 opening_soon=true: %s" % str(cpos))

	# 3) 同一子阶段再次放置：应因“每张卡一次”被拒绝
	var exec_again := engine.execute_command(Command.create("place_restaurant", actor, {"position": [0, 0], "rotation": 0}))
	if exec_again.ok:
		return Result.failure("同一子阶段不应允许再次放置餐厅（经理次数应耗尽）")
	if str(exec_again.error).find("已用完") < 0:
		return Result.failure("第二次放置应提示次数已用完，实际: %s" % exec_again.error)

	# 4) 推进到下一回合 Restructuring：Cleanup 会自动结算 opening_soon 餐厅（正式开业）
	var to_restructuring := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_RESTRUCTURING, 80)
	if not to_restructuring.ok:
		return to_restructuring

	state = engine.get_state()
	if not state.map.get("restaurants", {}).has(placed_rest_id):
		return Result.failure("Cleanup 后 opening_soon 餐厅应加入 map.restaurants: %s" % placed_rest_id)
	var plist2: Array = state.players[actor].get("restaurants", [])
	if not plist2.has(placed_rest_id):
		return Result.failure("Cleanup 后 opening_soon 餐厅应加入 player.restaurants: %s" % placed_rest_id)
	if state.round_state is Dictionary and (state.round_state as Dictionary).has("opening_soon_restaurants"):
		return Result.failure("Cleanup 后应移除 round_state.opening_soon_restaurants")
	for i2 in range(pending_cells.size()):
		var cpos_val2 = pending_cells[i2]
		if not (cpos_val2 is Vector2i):
			continue
		var cpos2: Vector2i = cpos_val2
		var idx2 := CoordsClass.world_to_index(state, cpos2)
		var cell2: Dictionary = state.map.cells[idx2.y][idx2.x]
		var s2_val = cell2.get("structure", null)
		if not (s2_val is Dictionary):
			return Result.failure("Cleanup 后餐厅格子结构缺失: %s" % str(cpos2))
		var s2: Dictionary = s2_val
		if s2.has("opening_soon"):
			return Result.failure("Cleanup 后餐厅格子不应保留 opening_soon 标志: %s" % str(cpos2))

	# Cleanup 后进入重组：本地经理默认转入待命，入口点应恢复默认（不依赖“本回合使用”）
	var opened_rest: Dictionary = state.map.get("restaurants", {}).get(placed_rest_id, {})
	var ep_opened_default_r := StructuresClass.get_restaurant_entrance_points(state, placed_rest_id, opened_rest)
	if not ep_opened_default_r.ok:
		return ep_opened_default_r
	var ep_opened_default: Array = ep_opened_default_r.value
	if ep_opened_default.size() != 1:
		return Result.failure("Cleanup 后默认入口点应为 1 个（local_manager 已转待命），实际: %s" % str(ep_opened_default))

	# 在重组阶段将 local_manager 放入公司结构后，应恢复四角入口点
	var re_enable := engine.execute_command(Command.create("set_company_structure_direct", actor, {"slot_index": 0, "employee_id": "local_manager"}))
	if not re_enable.ok:
		return Result.failure("重组放置 local_manager 失败: %s" % re_enable.error)

	state = engine.get_state()
	opened_rest = state.map.get("restaurants", {}).get(placed_rest_id, {})
	var ep_opened_r := StructuresClass.get_restaurant_entrance_points(state, placed_rest_id, opened_rest)
	if not ep_opened_r.ok:
		return ep_opened_r
	var opened_corners_r := _get_footprint_corners(opened_rest.get("cells", []), "开业餐厅")
	if not opened_corners_r.ok:
		return opened_corners_r
	var ep_opened_check := _assert_entrance_points_match_corners(ep_opened_r.value, opened_corners_r.value, "重组放置 local_manager 后在岗")
	if not ep_opened_check.ok:
		return ep_opened_check

	# 额外用例：大区经理放置的新餐厅应“立即开业”（opening_soon=false）
	var regional_case := _run_regional_manager_open_immediately_case(player_count, seed_val)
	if not regional_case.ok:
		return regional_case

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"actor": actor,
		"opening_soon_restaurant_id": placed_rest_id,
	})

static func _find_first_valid_restaurant_placement(engine: GameEngine, actor: int, extra_params: Dictionary = {}) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid.y):
		for x in range(grid.x):
			for r in rotations:
				var params := {"position": [x, y], "rotation": r}
				if extra_params != null and not extra_params.is_empty():
					for k in extra_params.keys():
						params[k] = extra_params[k]
				var cmd := Command.create("place_restaurant", actor, params)
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

static func _run_regional_manager_open_immediately_case(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("大区经理开业用例：初始化失败: %s" % init.error)

	# 为避免测试推进到 Payday 时因薪水不足中断，给每位玩家少量现金（保持现金守恒）。
	var s := engine.get_state()
	for pid in range(player_count):
		var grant := StateUpdaterClass.player_receive_from_bank(s, pid, 20)
		if not grant.ok:
			return Result.failure("大区经理开业用例：发放测试现金失败: %s" % grant.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return Result.failure("大区经理开业用例：推进到 Working 失败: %s" % to_working.error)

	var state := engine.get_state()
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		return Result.failure("大区经理开业用例：应处于 Working/PlaceRestaurants，实际: %s/%s" % [state.phase, state.sub_phase])

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("大区经理开业用例：无法获取当前玩家")

	var take := StateUpdaterClass.take_from_pool(state, "regional_manager", 1)
	if not take.ok:
		return Result.failure("大区经理开业用例：从员工池取出 regional_manager 失败: %s" % take.error)

	var add := StateUpdaterClass.add_employee(state, actor, "regional_manager", false)
	if not add.ok:
		return Result.failure("大区经理开业用例：添加 regional_manager 失败: %s" % add.error)

	var cmd := _find_first_valid_restaurant_placement(engine, actor, {"employee_type": "regional_manager"})
	if cmd == null:
		return Result.failure("大区经理开业用例：找不到合法的餐厅放置点")

	state = engine.get_state()
	var next_id_val = state.map.get("next_restaurant_id", null)
	if not (next_id_val is int):
		return Result.failure("大区经理开业用例：map.next_restaurant_id 类型错误（期望 int）")
	var rid := "rest_%d" % int(next_id_val)

	var exec_ok := engine.execute_command(cmd)
	if not exec_ok.ok:
		return Result.failure("大区经理开业用例：放置餐厅失败: %s (%s)" % [exec_ok.error, str(cmd)])

	state = engine.get_state()
	if not state.map.get("restaurants", {}).has(rid):
		return Result.failure("大区经理放置后餐厅应立即加入 map.restaurants: %s" % rid)
	var plist: Array = state.players[actor].get("restaurants", [])
	if not plist.has(rid):
		return Result.failure("大区经理放置后 player.restaurants 应包含新餐厅: %s" % rid)

	if state.round_state is Dictionary:
		var pending_val = (state.round_state as Dictionary).get("opening_soon_restaurants", null)
		if pending_val is Array:
			for e_val in Array(pending_val):
				if e_val is Dictionary and str((e_val as Dictionary).get("restaurant_id", "")).strip_edges() == rid:
					return Result.failure("大区经理放置后不应把餐厅写入 opening_soon_restaurants: %s" % rid)

	return Result.success(true)
