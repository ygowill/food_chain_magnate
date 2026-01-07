# 强制动作测试（M3）
# 验证：定价经理等员工的强制动作逻辑、阻塞机制
class_name MandatoryActionsTest
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	# 1) 初始化游戏（模块系统 V2 会装配 EmployeeRegistry）
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()

	# 2) 测试员工定义中的 mandatory 字段
	var pricing_def = EmployeeRegistryClass.get_def("pricing_manager")
	if pricing_def == null:
		return Result.failure("无法获取 pricing_manager 定义")
	if not pricing_def.mandatory:
		return Result.failure("pricing_manager 应该是 mandatory=true")

	var discount_def = EmployeeRegistryClass.get_def("discount_manager")
	if discount_def == null:
		return Result.failure("无法获取 discount_manager 定义")
	if not discount_def.mandatory:
		return Result.failure("discount_manager 应该是 mandatory=true")

	var luxury_def = EmployeeRegistryClass.get_def("luxury_manager")
	if luxury_def == null:
		return Result.failure("无法获取 luxury_manager 定义")
	if not luxury_def.mandatory:
		return Result.failure("luxury_manager 应该是 mandatory=true")

	# 3) 推进到 Working 阶段
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	state = engine.get_state()
	if state.phase != "Working":
		return Result.failure("当前应该在 Working 阶段，实际: %s" % state.phase)

	# 4) 获取当前玩家 ID（使用正确的回合顺序）
	var current_player_id := state.get_current_player_id()
	if current_player_id < 0:
		return Result.failure("无法获取当前玩家 ID")

	# 5) 给当前玩家添加 pricing_manager（直接修改 state，模拟招聘+激活）
	# 注意：engine.get_state() 返回的是实际 state 引用
	var pm_before: int = int(state.employee_pool.get("pricing_manager", 0))
	if pm_before <= 0:
		return Result.failure("员工池中 pricing_manager 数量不足")
	state.employee_pool["pricing_manager"] = pm_before - 1
	state.players[current_player_id]["employees"].append("pricing_manager")

	# 6) 测试 MandatoryActionsRules.get_required_mandatory_actions
	var current_player := state.get_player(current_player_id)
	var required := MandatoryActionsRulesClass.get_required_mandatory_actions(current_player)
	if not required.has("set_price"):
		return Result.failure("当前玩家应该需要执行 set_price 强制动作，实际需要: %s" % str(required))

	# 7) 测试 check_mandatory_actions_completed 失败（未完成强制动作）
	var check_result := MandatoryActionsRulesClass.check_mandatory_actions_completed(state)
	if check_result.ok:
		return Result.failure("存在未完成强制动作时，check_mandatory_actions_completed 应该失败")

	if not check_result.error.contains("set_price"):
		return Result.failure("错误消息应该包含 'set_price'，实际: %s" % check_result.error)

	# 8) 推进到最后一个子阶段 PlaceRestaurants
	var to_place_restaurants := TestPhaseUtilsClass.advance_until_working_sub_phase(engine, "PlaceRestaurants", 20)
	if not to_place_restaurants.ok:
		return to_place_restaurants

	state = engine.get_state()
	if state.sub_phase != "PlaceRestaurants":
		return Result.failure("当前子阶段应该是 PlaceRestaurants，实际: %s" % state.sub_phase)

	# 9) 强制动作未完成时，不应允许“确认结束”最后子阶段（否则会软锁）
	var idx := state.turn_order.find(current_player_id)
	if idx >= 0:
		state.current_player_index = idx
	var confirm_end := engine.execute_command(Command.create("skip", current_player_id))
	if confirm_end.ok:
		return Result.failure("存在未完成强制动作时，不应允许确认结束 PlaceRestaurants 子阶段")
	if not str(confirm_end.error).contains("set_price"):
		return Result.failure("错误消息应该包含 'set_price'，实际: %s" % str(confirm_end.error))

	# 10) 执行 set_price 动作（使用当前玩家 ID）
	var set_price_cmd := Command.create("set_price", current_player_id, {})
	var set_price_result := engine.execute_command(set_price_cmd)
	if not set_price_result.ok:
		return Result.failure("执行 set_price 失败: %s" % set_price_result.error)

	state = engine.get_state()

	# 11) 验证强制动作已完成
	assert(state.round_state.mandatory_actions_completed.has(current_player_id), "round_state.mandatory_actions_completed 缺少玩家 key")
	var completed: Array = state.round_state.mandatory_actions_completed[current_player_id]
	if not completed.has("set_price"):
		return Result.failure("set_price 应该在已完成列表中")

	# 12) 再次检查，应该通过
	var check_result2 := MandatoryActionsRulesClass.check_mandatory_actions_completed(state)
	if not check_result2.ok:
		return Result.failure("强制动作完成后检查应该通过: %s" % check_result2.error)

	# 13) 验证价格修正已设置
	var price_modifiers: Dictionary = state.round_state.get("price_modifiers", {})
	var player_modifiers: Dictionary = price_modifiers.get(current_player_id, {})
	if player_modifiers.get("pricing_manager", 0) != -1:
		return Result.failure("pricing_manager 价格修正应该是 -1，实际: %s" % str(player_modifiers))

	# 14) 现在可以离开 Working 阶段（全员结束 Working 回合）
	var leave_working := TestPhaseUtilsClass.complete_working_phase(engine, 200)
	if not leave_working.ok:
		return leave_working

	state = engine.get_state()
	if state.phase == "Working":
		return Result.failure("强制动作完成后应允许离开 Working 阶段")

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"current_player_id": current_player_id,
		"pricing_mandatory": pricing_def.mandatory,
		"discount_mandatory": discount_def.mandatory,
		"luxury_mandatory": luxury_def.mandatory,
		"price_modifier_applied": -1
	})
