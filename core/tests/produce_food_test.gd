# 生产食物测试（M3）
# 验证：厨师/主厨在 GetFood 子阶段生产食物到库存
class_name ProduceFoodTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	# 重置 EmployeeRegistry 缓存，确保测试隔离
	EmployeeRegistryClass.reset()

	# 1) 初始化游戏
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()

	# 2) 推进到 Working 阶段
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return to_working

	state = engine.get_state()
	if state.phase != DefsClass.PHASE_WORKING:
		return Result.failure("当前应该在 Working 阶段，实际: %s" % state.phase)

	# 3) 获取当前玩家 ID（使用正确的回合顺序）
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return Result.failure("无法获取当前玩家 ID")

	# 固定到 GetFood 子阶段（测试 produce_food 本身，不依赖 Working 自动跳子阶段的细节）
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD

	# 4) 给当前玩家添加一个汉堡厨师（模拟招聘）
	if state.employee_pool.get("burger_cook", 0) <= 0:
		return Result.failure("员工池中没有 burger_cook")
	state.employee_pool["burger_cook"] = int(state.employee_pool.get("burger_cook", 0)) - 1
	state.players[current_player_id]["employees"].append("burger_cook")

	# 为避免首个动作后 GetFood 被自动跳过，预先加入另一种可生产员工
	if state.employee_pool.get("pizza_cook", 0) <= 0:
		return Result.failure("员工池中没有 pizza_cook")
	state.employee_pool["pizza_cook"] = int(state.employee_pool.get("pizza_cook", 0)) - 1
	state.players[current_player_id]["employees"].append("pizza_cook")

	# 5) 检查初始库存
	var initial_burger: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if initial_burger != 0:
		return Result.failure("初始汉堡库存应为 0，实际: %d" % initial_burger)

	# 6) 执行生产食物动作
	var produce_cmd := Command.create("produce_food", current_player_id, {"employee_type": "burger_cook"})
	var produce_result := engine.execute_command(produce_cmd)
	if not produce_result.ok:
		return Result.failure("执行 produce_food 失败: %s" % produce_result.error)

	state = engine.get_state()

	# 7) 验证库存增加
	var new_burger: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if new_burger != 3:
		return Result.failure("生产后汉堡库存应为 3，实际: %d" % new_burger)

	# 8) 尝试再次使用同一厨师生产（应该失败 - 每个厨师每子阶段只能生产一次）
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var produce_again := Command.create("produce_food", current_player_id, {"employee_type": "burger_cook"})
	var produce_again_result := engine.execute_command(produce_again)
	if produce_again_result.ok:
		return Result.failure("同一厨师不应能在同一子阶段再次生产")

	# 9) 添加第二个汉堡厨师并验证可以生产
	if state.employee_pool.get("burger_cook", 0) <= 0:
		return Result.failure("员工池中没有 burger_cook（第二个）")
	state.employee_pool["burger_cook"] = int(state.employee_pool.get("burger_cook", 0)) - 1
	state.players[current_player_id]["employees"].append("burger_cook")
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var produce_second := Command.create("produce_food", current_player_id, {"employee_type": "burger_cook"})
	var produce_second_result := engine.execute_command(produce_second)
	if not produce_second_result.ok:
		return Result.failure("第二个厨师应该可以生产: %s" % produce_second_result.error)

	state = engine.get_state()
	var final_burger: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if final_burger != 6:
		return Result.failure("两个厨师生产后库存应为 6，实际: %d" % final_burger)

	# 10) 测试汉堡主厨（生产 8 个）
	if state.employee_pool.get("burger_chef", 0) <= 0:
		return Result.failure("员工池中没有 burger_chef")
	state.employee_pool["burger_chef"] = int(state.employee_pool.get("burger_chef", 0)) - 1
	state.players[current_player_id]["employees"].append("burger_chef")
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var produce_chef := Command.create("produce_food", current_player_id, {"employee_type": "burger_chef"})
	var produce_chef_result := engine.execute_command(produce_chef)
	if not produce_chef_result.ok:
		return Result.failure("汉堡主厨应该可以生产: %s" % produce_chef_result.error)

	state = engine.get_state()
	var chef_burger: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if chef_burger != 14:  # 6 + 8
		return Result.failure("加上主厨后库存应为 14，实际: %d" % chef_burger)

	# 11) 测试披萨厨师
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var produce_pizza := Command.create("produce_food", current_player_id, {"employee_type": "pizza_cook"})
	var produce_pizza_result := engine.execute_command(produce_pizza)
	if not produce_pizza_result.ok:
		return Result.failure("披萨厨师应该可以生产: %s" % produce_pizza_result.error)

	state = engine.get_state()
	var pizza_count: int = state.players[current_player_id]["inventory"].get("pizza", 0)
	if pizza_count != 3:
		return Result.failure("披萨库存应为 3，实际: %d" % pizza_count)

	# 12) 测试无效的员工类型
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var invalid_cmd := Command.create("produce_food", current_player_id, {"employee_type": "recruiting_girl"})
	var invalid_result := engine.execute_command(invalid_cmd)
	if invalid_result.ok:
		return Result.failure("recruiting_girl 不应该能生产食物")

	# 13) 测试玩家没有的厨师类型
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var no_cook := Command.create("produce_food", current_player_id, {"employee_type": "pizza_chef"})
	var no_cook_result := engine.execute_command(no_cook)
	if no_cook_result.ok:
		return Result.failure("没有披萨主厨不应能生产")

	# 14) 测试见习厨师（kitchen_trainee）：可选择生产汉堡/披萨（每次 1 个）
	if state.employee_pool.get("kitchen_trainee", 0) <= 1:
		return Result.failure("员工池中没有足够的 kitchen_trainee")
	state.employee_pool["kitchen_trainee"] = int(state.employee_pool.get("kitchen_trainee", 0)) - 2
	state.players[current_player_id]["employees"].append("kitchen_trainee")
	state.players[current_player_id]["employees"].append("kitchen_trainee")

	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var trainee_missing := Command.create("produce_food", current_player_id, {"employee_type": "kitchen_trainee"})
	var trainee_missing_result := engine.execute_command(trainee_missing)
	if trainee_missing_result.ok:
		return Result.failure("kitchen_trainee 未提供 food_type 时不应能生产")

	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var trainee_invalid := Command.create("produce_food", current_player_id, {"employee_type": "kitchen_trainee", "food_type": "lemonade"})
	var trainee_invalid_result := engine.execute_command(trainee_invalid)
	if trainee_invalid_result.ok:
		return Result.failure("kitchen_trainee 不应能生产 lemonade")

	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var trainee_burger := Command.create("produce_food", current_player_id, {"employee_type": "kitchen_trainee", "food_type": "burger"})
	var trainee_burger_result := engine.execute_command(trainee_burger)
	if not trainee_burger_result.ok:
		return Result.failure("kitchen_trainee(burger) 应该可以生产: %s" % trainee_burger_result.error)

	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	var trainee_pizza := Command.create("produce_food", current_player_id, {"employee_type": "kitchen_trainee", "food_type": "pizza"})
	var trainee_pizza_result := engine.execute_command(trainee_pizza)
	if not trainee_pizza_result.ok:
		return Result.failure("kitchen_trainee(pizza) 应该可以生产: %s" % trainee_pizza_result.error)

	state = engine.get_state()
	var burger_after_trainee: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if burger_after_trainee != 15: # 14 + 1
		return Result.failure("见习厨师生产后汉堡库存应为 15，实际: %d" % burger_after_trainee)
	var pizza_after_trainee: int = state.players[current_player_id]["inventory"].get("pizza", 0)
	if pizza_after_trainee != 4: # 3 + 1
		return Result.failure("见习厨师生产后披萨库存应为 4，实际: %d" % pizza_after_trainee)

	var staff_resolution := _test_staff_id_resolution_for_duplicate_producers(player_count, seed_val + 1000)
	if not staff_resolution.ok:
		return staff_resolution

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"final_burger_inventory": burger_after_trainee,
		"final_pizza_inventory": pizza_after_trainee,
		"burger_cooks_tested": 2,
		"burger_chef_tested": 1,
		"pizza_cook_tested": 1,
		"kitchen_trainees_tested": 2,
		"staff_id_resolution_checked": true,
	})

static func _test_staff_id_resolution_for_duplicate_producers(player_count: int, seed_val: int) -> Result:
	EmployeeRegistryClass.reset()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("staff_id 生产测试初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not to_working.ok:
		return Result.failure("staff_id 生产测试推进到 Working 失败: %s" % to_working.error)

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	state.turn_order = [actor]
	state.current_player_index = 0
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD

	for i in range(2):
		var take := StateUpdater.take_from_pool(state, "burger_cook", 1)
		if not take.ok:
			return Result.failure("staff_id 生产测试取出 burger_cook 失败: %s" % take.error)
		var add := StateUpdater.add_employee(state, actor, "burger_cook", false)
		if not add.ok:
			return Result.failure("staff_id 生产测试添加 burger_cook 失败: %s" % add.error)

	var ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, actor, "burger_cook", ["employees"])
	if not ids_read.ok:
		return Result.failure("staff_id 生产测试读取 burger_cook staff_ids 失败: %s" % ids_read.error)
	var ids: Array = ids_read.value
	if ids.size() < 2:
		return Result.failure("staff_id 生产测试需要 2 个 burger_cook staff_id，实际: %s" % str(ids))
	var first_staff_id := int(ids[0])
	var second_staff_id := int(ids[1])

	var explicit := engine.execute_command(Command.create("produce_food", actor, {
		"employee_type": "burger_cook",
		"staff_id": second_staff_id,
	}))
	if not explicit.ok:
		return Result.failure("显式 staff_id 生产应成功，但失败: %s" % explicit.error)
	var food_events: Array = EventBus.get_history_by_type(EventBus.EventType.FOOD_PRODUCED)
	if food_events.is_empty():
		return Result.failure("显式 staff_id 生产后应生成 FOOD_PRODUCED 事件")
	var explicit_event_val = food_events[food_events.size() - 1]
	if not (explicit_event_val is Dictionary):
		return Result.failure("FOOD_PRODUCED 事件类型错误（期望 Dictionary）")
	var explicit_event: Dictionary = explicit_event_val
	var explicit_data_val = explicit_event.get("data", null)
	if not (explicit_data_val is Dictionary):
		return Result.failure("FOOD_PRODUCED 事件缺少 data")
	var explicit_data: Dictionary = explicit_data_val
	if int(explicit_data.get("staff_id", -1)) != second_staff_id:
		return Result.failure("显式 staff_id 生产事件应记录第二个员工 staff_id=%d，实际: %s" % [second_staff_id, str(explicit_data)])

	state = engine.get_state()
	var second_used_read := StaffStateClass.get_staff_track_used(state, second_staff_id, "produce_food")
	if not second_used_read.ok:
		return Result.failure("读取第二个 staff 生产 usage 失败: %s" % second_used_read.error)
	var first_used_read := StaffStateClass.get_staff_track_used(state, first_staff_id, "produce_food")
	if not first_used_read.ok:
		return Result.failure("读取第一个 staff 生产 usage 失败: %s" % first_used_read.error)
	if int(second_used_read.value) != 1 or int(first_used_read.value) != 0:
		return Result.failure("显式 staff_id 生产应只消耗第二个员工，实际 first=%s second=%s" % [str(first_used_read.value), str(second_used_read.value)])

	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD
	state.turn_order = [actor]
	state.current_player_index = 0
	var implicit := engine.execute_command(Command.create("produce_food", actor, {
		"employee_type": "burger_cook",
	}))
	if not implicit.ok:
		return Result.failure("默认 staff_id 生产应成功，但失败: %s" % implicit.error)
	food_events = EventBus.get_history_by_type(EventBus.EventType.FOOD_PRODUCED)
	if food_events.is_empty():
		return Result.failure("默认 staff_id 生产后应生成 FOOD_PRODUCED 事件")
	var implicit_event_val = food_events[food_events.size() - 1]
	if not (implicit_event_val is Dictionary):
		return Result.failure("FOOD_PRODUCED 事件类型错误（期望 Dictionary）")
	var implicit_event: Dictionary = implicit_event_val
	var implicit_data_val = implicit_event.get("data", null)
	if not (implicit_data_val is Dictionary):
		return Result.failure("FOOD_PRODUCED 事件缺少 data")
	var implicit_data: Dictionary = implicit_data_val
	if int(implicit_data.get("staff_id", -1)) != first_staff_id:
		return Result.failure("默认 staff_id 生产应回退到最小可用 staff_id=%d，实际事件: %s" % [first_staff_id, str(implicit_data)])

	state = engine.get_state()
	second_used_read = StaffStateClass.get_staff_track_used(state, second_staff_id, "produce_food")
	if not second_used_read.ok:
		return Result.failure("再次读取第二个 staff 生产 usage 失败: %s" % second_used_read.error)
	first_used_read = StaffStateClass.get_staff_track_used(state, first_staff_id, "produce_food")
	if not first_used_read.ok:
		return Result.failure("再次读取第一个 staff 生产 usage 失败: %s" % first_used_read.error)
	if int(second_used_read.value) != 1 or int(first_used_read.value) != 1:
		return Result.failure("默认 staff_id 生产后应两个员工各消耗 1 次，实际 first=%s second=%s" % [str(first_used_read.value), str(second_used_read.value)])

	return Result.success()
