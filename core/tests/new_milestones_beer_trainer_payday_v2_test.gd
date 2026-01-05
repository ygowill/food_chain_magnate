# 模块3：全新里程碑（New Milestones）
# 覆盖：
# - FIRST BEER SOLD：允许用 food/drink token 支付薪水
# - FIRST TRAINER USED：无法支付时不再强制解雇（允许欠薪离开 Payday）
class_name NewMilestonesBeerTrainerPaydayV2Test
extends RefCounted

const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 882211) -> Result:
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

	# 场景A：无 first_trainer_used 时，欠薪应阻止离开 Payday
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Payday"
	state.sub_phase = ""
	var take_pc := StateUpdaterClass.take_from_pool(state, "pizza_cook", 1)
	if not take_pc.ok:
		return Result.failure("从员工池取出 pizza_cook 失败: %s" % take_pc.error)
	var add_pc := StateUpdaterClass.add_employee(state, 0, "pizza_cook", false)
	if not add_pc.ok:
		return Result.failure("添加 pizza_cook 失败: %s" % add_pc.error)
	state.players[0]["cash"] = 0 # 需要支付薪水但无现金

	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if adv.ok:
		return Result.failure("欠薪时不应允许离开 Payday（无 first_trainer_used）")

	# 触发 first_trainer_used（直接发 UseEmployee 事件）
	var ms := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": 0, "id": "trainer"})
	if not ms.ok:
		return Result.failure("触发里程碑失败(UseEmployee/trainer): %s" % ms.error)

	var adv2 := engine.execute_command(Command.create_system("advance_phase"))
	if not adv2.ok:
		return Result.failure("有 first_trainer_used 时应允许离开 Payday: %s" % adv2.error)

	# 场景B：first_beer_sold 可用 token 支付薪水（并消耗库存）
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(player_count, seed_val + 1, enabled_modules)
	if not init2.ok:
		return Result.failure("初始化失败(2): %s" % init2.error)
	var state2 := engine2.get_state()
	_force_turn_order(state2)
	state2.phase = "Payday"
	state2.sub_phase = ""
	var take_pc2 := StateUpdaterClass.take_from_pool(state2, "pizza_cook", 1)
	if not take_pc2.ok:
		return Result.failure("从员工池取出 pizza_cook 失败(2): %s" % take_pc2.error)
	var add_pc2 := StateUpdaterClass.add_employee(state2, 0, "pizza_cook", false)
	if not add_pc2.ok:
		return Result.failure("添加 pizza_cook 失败(2): %s" % add_pc2.error)
	state2.players[0]["cash"] = 0
	state2.players[0]["inventory"]["pizza"] = 1

	var ms2 := MilestoneSystemClass.process_event(state2, "ProductSold", {"player_id": 0, "product": "beer"})
	if not ms2.ok:
		return Result.failure("触发里程碑失败(ProductSold/beer): %s" % ms2.error)

	var adv3 := engine2.execute_command(Command.create_system("advance_phase"))
	if not adv3.ok:
		return Result.failure("有 first_beer_sold 且 token 足够时应允许离开 Payday: %s" % adv3.error)

	state2 = engine2.get_state()
	if int(Dictionary(state2.players[0].get("inventory", {})).get("pizza", 0)) != 0:
		return Result.failure("pizza token 应被消耗 1 个用于支付薪水")

	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0
