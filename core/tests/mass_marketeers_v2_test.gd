# 模块10：大众营销员（Mass Marketeers）
# - 场上每有一个在岗的大众营销员，Marketing 阶段额外结算 1 轮（全局）
class_name MassMarketeersV2Test
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"mass_marketeers",
	]
	var init := engine.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if int(state.employee_pool.get("mass_marketeer", 0)) < 2:
		return Result.failure("员工池中 mass_marketeer 不足以测试: %s" % str(state.employee_pool.get("mass_marketeer", 0)))
	state.employee_pool["mass_marketeer"] = int(state.employee_pool.get("mass_marketeer", 0)) - 2
	state.players[0]["employees"].append("mass_marketeer")
	state.players[0]["employees"].append("mass_marketeer")

	# 放置一个 duration=2 的营销实例，验证“多轮结算只在最后统一 -1 持续时间”
	var board_number := 11
	var pos := Vector2i(0, 0)
	state.marketing_instances = [
		{
			"board_number": board_number,
			"type": "billboard",
			"owner": 0,
			"employee_type": "marketer",
			"product": "burger",
			"world_pos": pos,
			"remaining_duration": 2,
			"axis": "",
			"tile_index": -1,
			"created_round": state.round_number,
		},
	]
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": "billboard",
		"owner": 0,
		"product": "burger",
		"world_pos": pos,
		"remaining_duration": 2,
		"axis": "",
		"tile_index": -1,
	}

	state.phase = "Payday"
	state.sub_phase = ""
	var cash := StateUpdaterClass.player_receive_from_bank(state, 0, 20)
	if not cash.ok:
		return Result.failure("发放测试现金失败: %s" % cash.error)
	var adv := engine.phase_manager.advance_phase(state)
	if not adv.ok:
		return Result.failure("推进到 Marketing 失败: %s" % adv.error)

	state = engine.get_state()

	var rs_marketing_val = state.round_state.get("marketing", null)
	if not (rs_marketing_val is Dictionary):
		return Result.failure("round_state.marketing 缺失或类型错误（期望 Dictionary）")
	var rs_marketing: Dictionary = rs_marketing_val
	var rounds_val = rs_marketing.get("rounds", null)
	if not (rounds_val is int):
		return Result.failure("round_state.marketing.rounds 缺失或类型错误（期望 int）")
	var rounds: int = int(rounds_val)
	if rounds != 3:
		return Result.failure("Marketing 轮次应为 1+2=3，实际: %d" % rounds)

	if state.marketing_instances.is_empty():
		return Result.failure("营销实例不应被移除（duration=2），但 marketing_instances 为空")
	var inst_val = state.marketing_instances[0]
	if not (inst_val is Dictionary):
		return Result.failure("marketing_instances[0] 类型错误（期望 Dictionary）")
	var inst: Dictionary = inst_val
	if int(inst.get("remaining_duration", 0)) != 1:
		return Result.failure("duration=2 且多轮结算后应统一 -1 到 1，实际: %s" % str(inst.get("remaining_duration", null)))

	return Result.success({
		"rounds": rounds,
		"remaining_duration": int(inst.get("remaining_duration", 0)),
	})
