# 采购饮料测试（M3）
# 验证：卡车司机/飞艇驾驶员在 GetDrinks 子阶段采购饮料到库存
class_name ProcureDrinksTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var last_error: String = ""
	var max_attempts: int = 20
	for i in range(max_attempts):
		var try_seed: int = seed_val + i
		var r := _run_once(player_count, try_seed)
		if r.ok:
			var payload: Dictionary = r.value
			payload["seed_used"] = try_seed
			payload["seed_attempts"] = i + 1
			return Result.success(payload)
		last_error = r.error
		# 随机地图下不保证一定存在飞艇可达饮料源；在测试中允许尝试多个 seed。
		if r.error.find("找不到任何玩家能在飞艇范围内采购饮料") != -1:
			continue
		return r

	return Result.failure("ProcureDrinksTest: 在 %d 次 seed 尝试内仍失败: %s" % [max_attempts, last_error])

static func _run_once(player_count: int, seed_val: int) -> Result:
	# 重置 EmployeeRegistry 缓存，确保测试隔离
	EmployeeRegistryClass.reset()

	# 1) 初始化游戏
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()

	# 2) Setup：为每位玩家放置 1 个餐厅（使用放置动作，确保 state.map/restaurants 写入正确）
	var place_result := _place_initial_restaurants(engine)
	if not place_result.ok:
		return place_result

	state = engine.get_state()
	if state.phase != "Working":
		# 首轮：Restructuring/OrderOfBusiness 会自动跳过到 Working
		if state.phase != "Restructuring":
			return Result.failure("放置餐厅并全员确认结束后应进入 Working（首轮自动跳过 Restructuring/OOB），实际: %s" % state.phase)

	# 3) 推进到 Working 阶段
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	state = engine.get_state()
	if state.phase != "Working":
		return Result.failure("当前应该在 Working 阶段，实际: %s" % state.phase)

	# 固定到 GetDrinks 子阶段（测试 procure_drinks 本身，不依赖 Working 自动跳子阶段的细节）
	state.sub_phase = "GetDrinks"

	# 5) 检查地图上是否有饮料源
	var drink_sources: Array = state.map.get("drink_sources", [])
	if drink_sources.is_empty():
		return Result.failure("地图上没有饮料源")

	# 6) 选择一个“飞艇可达”的玩家，并轮转到其回合
	var air_player_id := _find_player_with_air_reachable_source(state, 4)
	if air_player_id < 0:
		return Result.failure("找不到任何玩家能在飞艇范围内采购饮料")

	# 将回合切到该玩家（避免 Working 下 skip=确认结束 的限制影响测试）
	var turn_order: Array[int] = []
	for pid in range(state.players.size()):
		turn_order.append(pid)
	state.turn_order = turn_order
	state.current_player_index = air_player_id
	state.sub_phase = "GetDrinks"

	# 7) 给该玩家添加一个飞艇驾驶员（air range = 4）
	if int(state.employee_pool.get("zeppelin_pilot", 0)) <= 0:
		return Result.failure("员工池中没有 zeppelin_pilot")
	state.employee_pool["zeppelin_pilot"] = int(state.employee_pool.get("zeppelin_pilot", 0)) - 1
	state.players[air_player_id]["employees"].append("zeppelin_pilot")

	# 8) 检查初始饮料库存（按总量）
	var inv_before_air: Dictionary = state.players[air_player_id].get("inventory", {})
	var drinks_before_air := _sum_drinks(inv_before_air)
	if drinks_before_air != 0:
		return Result.failure("初始饮料总库存应为 0，实际: %d" % drinks_before_air)

	# 9) 执行采购饮料动作（飞艇）
	var procure_cmd := Command.create("procure_drinks", air_player_id, {"employee_type": "zeppelin_pilot"})
	var procure_result := engine.execute_command(procure_cmd)
	if not procure_result.ok:
		return Result.failure("执行 procure_drinks 失败: %s" % procure_result.error)

	state = engine.get_state()

	# 10) 验证库存增加（至少来自 1 个饮料源，每源 2 瓶）
	var inv_after_air: Dictionary = state.players[air_player_id].get("inventory", {})
	var drinks_after_air := _sum_drinks(inv_after_air)
	if drinks_after_air < drinks_before_air + 2:
		return Result.failure("飞艇采购后饮料总库存应至少增加 2，实际增量: %d" % (drinks_after_air - drinks_before_air))

	# 11) 尝试再次使用同一员工采购（应该失败 - 每个员工每子阶段只能采购一次）
	state.sub_phase = "GetDrinks"
	state.current_player_index = air_player_id
	var procure_again := Command.create("procure_drinks", air_player_id, {"employee_type": "zeppelin_pilot"})
	var procure_again_result := engine.execute_command(procure_again)
	if procure_again_result.ok:
		return Result.failure("同一员工不应能在同一子阶段再次采购")

	# 12) 选择一个“卡车可达”的玩家，并轮转到其回合
	state = engine.get_state()
	var road_player_id := _find_player_with_road_reachable_source(state, 3)
	if road_player_id < 0:
		return Result.failure("找不到任何玩家能在卡车范围内采购饮料")

	state.current_player_index = road_player_id
	state.sub_phase = "GetDrinks"

	# 13) 测试卡车司机（road range = 3）
	if state.employee_pool.get("truck_driver", 0) <= 0:
		return Result.failure("员工池中没有 truck_driver")
	state.employee_pool["truck_driver"] = int(state.employee_pool.get("truck_driver", 0)) - 1
	state.players[road_player_id]["employees"].append("truck_driver")
	var drinks_before_road := _sum_drinks(state.players[road_player_id].get("inventory", {}))
	var procure_truck := Command.create("procure_drinks", road_player_id, {"employee_type": "truck_driver"})
	var procure_truck_result := engine.execute_command(procure_truck)
	if not procure_truck_result.ok:
		return Result.failure("卡车司机采购应成功，但失败: %s" % procure_truck_result.error)

	state = engine.get_state()
	var drinks_after_road := _sum_drinks(state.players[road_player_id].get("inventory", {}))
	if drinks_after_road < drinks_before_road + 2:
		return Result.failure("卡车采购后饮料总库存应至少增加 2，实际增量: %d" % (drinks_after_road - drinks_before_road))

	# 14) 测试无效的员工类型
	var invalid_cmd := Command.create("procure_drinks", road_player_id, {"employee_type": "recruiter"})
	var invalid_result := engine.execute_command(invalid_cmd)
	if invalid_result.ok:
		return Result.failure("recruiter 不应该能采购饮料")

	# 15) 测试玩家没有的员工类型
	state.sub_phase = "GetDrinks"
	state.current_player_index = road_player_id
	var no_emp := Command.create("procure_drinks", road_player_id, {"employee_type": "truck_driver"})
	# 先移除 truck_driver
	var employees: Array = state.players[road_player_id]["employees"]
	var removed_truck := false
	for i in range(employees.size() - 1, -1, -1):
		if employees[i] == "truck_driver":
			employees.remove_at(i)
			removed_truck = true
			break
	if removed_truck and state.employee_pool.has("truck_driver"):
		state.employee_pool["truck_driver"] = int(state.employee_pool.get("truck_driver", 0)) + 1
	var no_emp_result := engine.execute_command(no_emp)
	if no_emp_result.ok:
		return Result.failure("没有卡车司机不应能采购")

	state = engine.get_state()
	var final_drinks: int = _sum_drinks(state.players[road_player_id].get("inventory", {}))

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"drink_sources_count": drink_sources.size(),
		"final_drink_inventory": final_drinks,
		"zeppelin_tested_player": air_player_id,
		"truck_tested_player": road_player_id
	})

static func _place_initial_restaurants(engine: GameEngine) -> Result:
	var ensured_road_player: int = -1
	var road_range: int = 3
	var ensured_air_player: int = -1
	var air_range: int = 4

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
		if safety > 50:
			return Result.failure("Setup 放置餐厅循环超出安全上限")

		var current_player := engine.get_state().get_current_player_id()
		if not placed[current_player]:
			var cmd_place: Command = null
			if ensured_air_player == -1:
				cmd_place = _find_restaurant_placement_with_air_access(engine, current_player, air_range)
				if cmd_place != null:
					ensured_air_player = current_player
			if ensured_road_player == -1:
				cmd_place = _find_restaurant_placement_with_road_access(engine, current_player, road_range)
				if cmd_place != null:
					ensured_road_player = current_player

			if cmd_place == null:
				cmd_place = _find_first_valid_placement(engine, "place_restaurant", current_player)
			if cmd_place == null:
				return Result.failure("找不到玩家 %d 的合法餐厅放置点" % current_player)
			var exec_place := engine.execute_command(cmd_place)
			if not exec_place.ok:
				return Result.failure("放置餐厅失败: %s (%s)" % [exec_place.error, str(cmd_place)])
			placed[current_player] = true

		# 放置后手动结束回合
		var cmd_skip := Command.create("skip", current_player)
		var exec_skip := engine.execute_command(cmd_skip)
		if not exec_skip.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip.error, str(cmd_skip)])

	return Result.success()

static func _find_restaurant_placement_with_air_access(engine: GameEngine, actor: int, range_value: int) -> Command:
	var state := engine.get_state()
	if state.phase != "Setup":
		return null

	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null

	var sources: Array = state.map.get("drink_sources", [])
	if sources.is_empty():
		return null

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var cmd := Command.create("place_restaurant", actor, {
					"position": [x, y],
					"rotation": rot
				})
				var vr := executor.validate(state, cmd)
				if not vr.ok:
					continue

				var entrance_pos := Vector2i(x, y)
				var reachable := false
				for source in sources:
					var world_pos = source.get("world_pos", null)
					var source_pos: Vector2i
					if world_pos is Vector2i:
						source_pos = world_pos
					elif world_pos is Dictionary:
						source_pos = Vector2i(int(world_pos.get("x", 0)), int(world_pos.get("y", 0)))
					else:
						continue

					var dist: int = abs(source_pos.x - entrance_pos.x) + abs(source_pos.y - entrance_pos.y)
					if dist <= range_value:
						reachable = true
						break

				if reachable:
					return cmd

	return null

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

static func _find_restaurant_placement_with_road_access(engine: GameEngine, actor: int, range_value: int) -> Command:
	var state := engine.get_state()
	if state.phase != "Setup":
		return null

	var executor := engine.action_registry.get_executor("place_restaurant")
	if executor == null:
		return null

	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return null

	var sources: Array = state.map.get("drink_sources", [])
	if sources.is_empty():
		return null

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var entrance_pos := Vector2i(x, y)
			var start_road := _adjacent_road_cells(state, entrance_pos)
			if start_road.is_empty():
				continue

			for rot in rotations:
				var cmd := Command.create("place_restaurant", actor, {
					"position": [x, y],
					"rotation": rot
				})
				var vr := executor.validate(state, cmd)
				if not vr.ok:
					continue

				# 验证：该入口点是否能在 road_range 内到达任一饮品源的“邻接道路格”
				var reachable := false
				for source in sources:
					var world_pos = source.get("world_pos", null)
					var source_pos: Vector2i
					if world_pos is Vector2i:
						source_pos = world_pos
					elif world_pos is Dictionary:
						source_pos = Vector2i(int(world_pos.get("x", 0)), int(world_pos.get("y", 0)))
					else:
						continue

					var end_road := _adjacent_road_cells(state, source_pos)
					if end_road.is_empty():
						continue

					var best := 999999
					for s in start_road:
						for t in end_road:
							var d := int(road_graph.get_distance(s, t))
							if d >= 0 and d < best:
								best = d

					if best != 999999 and best <= range_value:
						reachable = true
						break

				if reachable:
					return cmd

	return null

static func _find_player_with_air_reachable_source(state: GameState, range_value: int) -> int:
	var sources: Array = state.map.get("drink_sources", [])
	var restaurants: Dictionary = state.map.get("restaurants", {})

	for pid in range(state.players.size()):
		var rest_ids := MapRuntimeClass.get_player_restaurants(state, pid)
		for rest_id in rest_ids:
				var rest: Dictionary = restaurants.get(rest_id, {})
				if rest.is_empty():
					continue
				var entrance_pos: Vector2i = rest.get("entrance_pos", rest.get("anchor_pos", Vector2i.ZERO))
				for source in sources:
					var world_pos = source.get("world_pos", null)
					var source_pos: Vector2i
					if world_pos is Vector2i:
						source_pos = world_pos
					elif world_pos is Dictionary:
						source_pos = Vector2i(int(world_pos.get("x", 0)), int(world_pos.get("y", 0)))
					else:
						continue

					var dist: int = abs(source_pos.x - entrance_pos.x) + abs(source_pos.y - entrance_pos.y)
					if dist <= range_value:
						return pid

	return -1

static func _find_player_with_road_reachable_source(state: GameState, range_value: int) -> int:
	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return -1

	var sources: Array = state.map.get("drink_sources", [])
	var restaurants: Dictionary = state.map.get("restaurants", {})

	for pid in range(state.players.size()):
		var rest_ids := MapRuntimeClass.get_player_restaurants(state, pid)
		for rest_id in rest_ids:
			var rest: Dictionary = restaurants.get(rest_id, {})
			if rest.is_empty():
				continue
			var entrance_pos: Vector2i = rest.get("entrance_pos", rest.get("anchor_pos", Vector2i.ZERO))
			var start_road := _adjacent_road_cells(state, entrance_pos)
			if start_road.is_empty():
				continue

			for source in sources:
				var world_pos = source.get("world_pos", null)
				var source_pos: Vector2i
				if world_pos is Vector2i:
					source_pos = world_pos
				elif world_pos is Dictionary:
					source_pos = Vector2i(int(world_pos.get("x", 0)), int(world_pos.get("y", 0)))
				else:
					continue

				var end_road := _adjacent_road_cells(state, source_pos)
				if end_road.is_empty():
					continue

				var best := 999999
				for s in start_road:
					for t in end_road:
						var d := int(road_graph.get_distance(s, t))
						if d >= 0 and d < best:
							best = d

				if best != 999999 and best <= range_value:
					return pid

	return -1

static func _rotate_to_player(engine: GameEngine, target_player_id: int) -> Result:
	var safety := 0
	while engine.get_state().get_current_player_id() != target_player_id:
		safety += 1
		if safety > 20:
			return Result.failure("轮转到目标玩家超出安全上限")
		var current := engine.get_state().get_current_player_id()
		var sk := engine.execute_command(Command.create("skip", current))
		if not sk.ok:
			return Result.failure("skip 失败: %s" % sk.error)
	return Result.success()

static func _sum_drinks(inventory: Dictionary) -> int:
	return int(inventory.get("soda", 0)) + int(inventory.get("lemonade", 0)) + int(inventory.get("beer", 0))

static func _adjacent_road_cells(state: GameState, anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	if not _is_in_bounds(grid_size, anchor):
		return cells
	if MapRuntimeClass.has_road_at(state, anchor):
		cells.append(anchor)
	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(anchor, dir)
		if not _is_in_bounds(grid_size, neighbor):
			continue
		if MapRuntimeClass.has_road_at(state, neighbor) and not cells.has(neighbor):
			cells.append(neighbor)
	return cells

static func _is_in_bounds(grid_size: Vector2i, pos: Vector2i) -> bool:
	if grid_size.x <= 0 or grid_size.y <= 0:
		return false
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y
