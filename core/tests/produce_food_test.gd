# 生产食物测试（M3）
# 验证：厨师/主厨在 GetFood 子阶段生产食物到库存
class_name ProduceFoodTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

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
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	state = engine.get_state()
	if state.phase != "Working":
		return Result.failure("当前应该在 Working 阶段，实际: %s" % state.phase)

	# 3) 获取当前玩家 ID（使用正确的回合顺序）
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return Result.failure("无法获取当前玩家 ID")

	# 固定到 GetFood 子阶段（测试 produce_food 本身，不依赖 Working 自动跳子阶段的细节）
	state.sub_phase = "GetFood"

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
	state.sub_phase = "GetFood"
	var produce_again := Command.create("produce_food", current_player_id, {"employee_type": "burger_cook"})
	var produce_again_result := engine.execute_command(produce_again)
	if produce_again_result.ok:
		return Result.failure("同一厨师不应能在同一子阶段再次生产")

	# 9) 添加第二个汉堡厨师并验证可以生产
	if state.employee_pool.get("burger_cook", 0) <= 0:
		return Result.failure("员工池中没有 burger_cook（第二个）")
	state.employee_pool["burger_cook"] = int(state.employee_pool.get("burger_cook", 0)) - 1
	state.players[current_player_id]["employees"].append("burger_cook")
	state.sub_phase = "GetFood"
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
	state.sub_phase = "GetFood"
	var produce_chef := Command.create("produce_food", current_player_id, {"employee_type": "burger_chef"})
	var produce_chef_result := engine.execute_command(produce_chef)
	if not produce_chef_result.ok:
		return Result.failure("汉堡主厨应该可以生产: %s" % produce_chef_result.error)

	state = engine.get_state()
	var chef_burger: int = state.players[current_player_id]["inventory"].get("burger", 0)
	if chef_burger != 14:  # 6 + 8
		return Result.failure("加上主厨后库存应为 14，实际: %d" % chef_burger)

	# 11) 测试披萨厨师
	state.sub_phase = "GetFood"
	var produce_pizza := Command.create("produce_food", current_player_id, {"employee_type": "pizza_cook"})
	var produce_pizza_result := engine.execute_command(produce_pizza)
	if not produce_pizza_result.ok:
		return Result.failure("披萨厨师应该可以生产: %s" % produce_pizza_result.error)

	state = engine.get_state()
	var pizza_count: int = state.players[current_player_id]["inventory"].get("pizza", 0)
	if pizza_count != 3:
		return Result.failure("披萨库存应为 3，实际: %d" % pizza_count)

	# 12) 测试无效的员工类型
	state.sub_phase = "GetFood"
	var invalid_cmd := Command.create("produce_food", current_player_id, {"employee_type": "recruiter"})
	var invalid_result := engine.execute_command(invalid_cmd)
	if invalid_result.ok:
		return Result.failure("recruiter 不应该能生产食物")

	# 13) 测试玩家没有的厨师类型
	state.sub_phase = "GetFood"
	var no_cook := Command.create("produce_food", current_player_id, {"employee_type": "pizza_chef"})
	var no_cook_result := engine.execute_command(no_cook)
	if no_cook_result.ok:
		return Result.failure("没有披萨主厨不应能生产")

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"final_burger_inventory": chef_burger,
		"final_pizza_inventory": pizza_count,
		"burger_cooks_tested": 2,
		"burger_chef_tested": 1,
		"pizza_cook_tested": 1
	})
