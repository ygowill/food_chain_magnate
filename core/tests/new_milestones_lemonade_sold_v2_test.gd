# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST LEMONADE SOLD
# - 触发：晚餐卖出柠檬水
# - 效果：允许在岗同色培训；旧员工未被使用时，新员工可立刻在岗
class_name NewMilestonesLemonadeSoldV2Test
extends RefCounted

const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

const MILESTONE_ID := "first_lemonade_sold"

static func run(player_count: int = 2, seed_val: int = 771122) -> Result:
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

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)

	# 直接触发 ProductSold（等价于晚餐售卖记录驱动）
	var ms := MilestoneSystemClass.process_event(state, "ProductSold", {"player_id": 0, "product": "lemonade"})
	if not ms.ok:
		return Result.failure("触发里程碑失败(ProductSold/lemonade): %s" % ms.error)
	if not Array(state.players[0].get("milestones", [])).has(MILESTONE_ID):
		return Result.failure("玩家0 应获得里程碑 %s" % MILESTONE_ID)

	# 场景A：在岗 management_trainee -> junior_vice_president（同色，且旧员工未使用）=> 新员工应立刻在岗
	state.phase = "Working"
	state.sub_phase = "Train"
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)
	# 需要至少 2 次培训容量：用于后续再次培训（场景B）
	var take_trainer2 := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer2.ok:
		return Result.failure("从员工池取出 trainer(2) 失败: %s" % take_trainer2.error)
	var add_trainer2 := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer2.ok:
		return Result.failure("添加 trainer(2) 失败: %s" % add_trainer2.error)

	var take_mt := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_mt.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_mt.error)
	var add_mt := StateUpdaterClass.add_employee(state, 0, "management_trainee", false)
	if not add_mt.ok:
		return Result.failure("添加 management_trainee 失败: %s" % add_mt.error)

	# 预先准备 pizza_cook（在本 Train 子阶段开始前存在），用于后续“已使用后再培训”的场景
	var take_pc := StateUpdaterClass.take_from_pool(state, "pizza_cook", 1)
	if not take_pc.ok:
		return Result.failure("从员工池取出 pizza_cook 失败: %s" % take_pc.error)
	var add_pc := StateUpdaterClass.add_employee(state, 0, "pizza_cook", false)
	if not add_pc.ok:
		return Result.failure("添加 pizza_cook 失败: %s" % add_pc.error)

	var t1 := engine.execute_command(Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "junior_vice_president",
	}))
	if not t1.ok:
		return Result.failure("train(management_trainee->junior_vice_president) 失败: %s" % t1.error)
	state = engine.get_state()
	if not Array(state.players[0].get("employees", [])).has("junior_vice_president"):
		return Result.failure("junior_vice_president 应立刻在岗")
	if Array(state.players[0].get("reserve_employees", [])).has("junior_vice_president"):
		return Result.failure("junior_vice_president 不应在 reserve_employees 中")

	# 场景B：在岗 pizza_cook 先被使用（produce_food），再培训 -> pizza_chef => 新员工应进入待命
	state.phase = "Working"
	state.sub_phase = "GetFood"
	var p := engine.execute_command(Command.create("produce_food", 0, {"employee_type": "pizza_cook"}))
	if not p.ok:
		return Result.failure("produce_food(pizza_cook) 失败: %s" % p.error)

	state = engine.get_state()
	state.phase = "Working"
	state.sub_phase = "Train"
	var t2 := engine.execute_command(Command.create("train", 0, {
		"from_employee": "pizza_cook",
		"to_employee": "pizza_chef",
	}))
	if not t2.ok:
		return Result.failure("train(pizza_cook->pizza_chef) 失败: %s" % t2.error)
	state = engine.get_state()
	if not Array(state.players[0].get("reserve_employees", [])).has("pizza_chef"):
		return Result.failure("pizza_chef 应进入 reserve_employees（旧员工已使用）")
	if Array(state.players[0].get("employees", [])).has("pizza_chef"):
		return Result.failure("pizza_chef 不应立刻在岗（旧员工已使用）")

	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0
