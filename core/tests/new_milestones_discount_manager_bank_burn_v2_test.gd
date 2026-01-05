# 模块3：全新里程碑（New Milestones）
# 覆盖：FIRST DISCOUNT MANAGER USED
# - 触发：使用 discount_manager 的 set_discount
# - 效果：下回合 Restructuring 结束移除银行 $100（可多玩家叠加）
class_name NewMilestonesDiscountManagerBankBurnV2Test
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 445566) -> Result:
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

	# 在 Working 中执行 set_discount（不依赖子阶段）
	state.phase = "Working"
	state.sub_phase = "Recruit"
	var take := StateUpdaterClass.take_from_pool(state, "discount_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 discount_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "discount_manager", false)
	if not add.ok:
		return Result.failure("添加 discount_manager 失败: %s" % add.error)

	var r := engine.execute_command(Command.create("set_discount", 0, {}))
	if not r.ok:
		return Result.failure("set_discount 失败: %s" % r.error)

	state = engine.get_state()
	if not Array(state.players[0].get("milestones", [])).has("first_discount_manager_used"):
		return Result.failure("应获得里程碑 first_discount_manager_used")
	if not bool(state.players[0].get("bank_burn_pending", false)):
		return Result.failure("应标记 bank_burn_pending=true")

	# 模拟进入下一回合的 Restructuring，并离开 Restructuring（触发 BEFORE_EXIT hook）
	state.phase = "Restructuring"
	state.sub_phase = ""
	state.round_number += 1

	var before := int(state.bank.get("total", 0))
	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("advance_phase(Restructuring->...) 失败: %s" % adv.error)

	state = engine.get_state()
	var after := int(state.bank.get("total", 0))
	if after != before - 100:
		return Result.failure("银行应被移除 $100：before=%d after=%d" % [before, after])
	if bool(state.players[0].get("bank_burn_pending", false)):
		return Result.failure("bank_burn_pending 应在扣款后清除")

	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0
