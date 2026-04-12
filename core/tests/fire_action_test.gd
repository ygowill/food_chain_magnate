# 解雇动作测试（M3）
# 验证：Payday 阶段可解雇员工并回补员工池；禁止解雇 CEO；忙碌营销员限制
class_name FireActionTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	# 1) Restructuring：不允许解雇（约束对齐 rules.md）
	var engine_r := GameEngine.new()
	var init_r := engine_r.initialize(player_count, seed_val)
	if not init_r.ok:
		return Result.failure("游戏初始化失败: %s" % init_r.error)
	var state_r := engine_r.get_state()
	state_r.phase = DefsClass.PHASE_RESTRUCTURING
	state_r.sub_phase = ""
	var restructuring_actor := state_r.get_current_player_id()
	if restructuring_actor < 0:
		return Result.failure("无法获取 Restructuring 当前玩家")
	var fire_in_restructuring := engine_r.execute_command(Command.create("fire", restructuring_actor, {"employee_id": "burger_cook"}))
	if fire_in_restructuring.ok:
		return Result.failure("Restructuring 不应允许解雇")

	# 2) 推进到 Payday
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)
	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_PAYDAY, 30)
	if not to_payday.ok:
		return to_payday

	var state := engine.get_state()
	if state.phase != DefsClass.PHASE_PAYDAY:
		return Result.failure("当前应为 Payday，实际: %s" % state.phase)

	# Payday：解雇应可用
	var payday_actor := state.get_current_player_id()
	if payday_actor < 0:
		return Result.failure("无法获取 Payday 当前玩家")

	# 3) 禁止解雇 CEO
	var fire_ceo := engine.execute_command(Command.create("fire", payday_actor, {"employee_id": "ceo"}))
	if fire_ceo.ok:
		return Result.failure("不应允许解雇 CEO")

	# 4) Payday：解雇在岗员工应回补员工池
	var pool_before_active: int = int(state.employee_pool.get("pizza_cook", 0))
	if pool_before_active <= 0:
		return Result.failure("员工池中 pizza_cook 数量不足")
	state.employee_pool["pizza_cook"] = pool_before_active - 1
	state.players[payday_actor]["employees"].append("pizza_cook")

	var fire_active := engine.execute_command(Command.create("fire", payday_actor, {"employee_id": "pizza_cook"}))
	if not fire_active.ok:
		return Result.failure("Payday 解雇在岗 pizza_cook 失败: %s" % fire_active.error)

	state = engine.get_state()
	var pool_after_active: int = int(state.employee_pool.get("pizza_cook", 0))
	if pool_after_active != pool_before_active:
		return Result.failure("Payday 解雇在岗后员工池数量不匹配: %d != %d" % [pool_after_active, pool_before_active])
	if state.get_player(payday_actor).get("employees", []).has("pizza_cook"):
		return Result.failure("Payday 解雇在岗后不应仍包含 pizza_cook")

	# 5) Payday：解雇待命员工应回补员工池
	var pool_before_reserve: int = int(state.employee_pool.get("burger_cook", 0))
	if pool_before_reserve <= 0:
		return Result.failure("员工池中 burger_cook 数量不足")
	state.employee_pool["burger_cook"] = pool_before_reserve - 1
	state.players[payday_actor]["reserve_employees"].append("burger_cook")

	var fire_reserve := engine.execute_command(Command.create("fire", payday_actor, {"employee_id": "burger_cook"}))
	if not fire_reserve.ok:
		return Result.failure("Payday 解雇待命 burger_cook 失败: %s" % fire_reserve.error)

	state = engine.get_state()
	var pool_after_reserve: int = int(state.employee_pool.get("burger_cook", 0))
	if pool_after_reserve != pool_before_reserve:
		return Result.failure("Payday 解雇待命后员工池数量不匹配: %d != %d" % [pool_after_reserve, pool_before_reserve])
	if state.get_player(payday_actor).get("reserve_employees", []).has("burger_cook"):
		return Result.failure("Payday 解雇待命后不应仍包含 burger_cook")

	# 6) Payday：通常忙碌营销员不能解雇（现金充足时应拒绝）
	var pool_before_busy: int = int(state.employee_pool.get("campaign_manager", 0))
	if pool_before_busy <= 0:
		return Result.failure("员工池中 campaign_manager 数量不足")
	state.employee_pool["campaign_manager"] = pool_before_busy - 1
	state.players[payday_actor]["busy_marketers"].append("campaign_manager")
	state.players[payday_actor]["cash"] = 999  # 确保现金充足，不满足特殊例外

	var fire_busy_denied := engine.execute_command(Command.create("fire", payday_actor, {"employee_id": "campaign_manager"}))
	if fire_busy_denied.ok:
		return Result.failure("现金充足时不应允许解雇忙碌营销员")

	# 7) Payday：特殊例外 - 解雇所有其他带薪员工后仍无力支付忙碌营销员薪水 -> 允许解雇该忙碌营销员
	state = engine.get_state()
	state.players[payday_actor]["cash"] = 0
	var fire_busy_allowed := engine.execute_command(Command.create("fire", payday_actor, {"employee_id": "campaign_manager"}))
	if not fire_busy_allowed.ok:
		return Result.failure("特殊例外下应允许解雇忙碌营销员，但失败: %s" % fire_busy_allowed.error)

	state = engine.get_state()
	var pool_after_busy: int = int(state.employee_pool.get("campaign_manager", 0))
	if pool_after_busy != pool_before_busy:
		return Result.failure("忙碌营销员解雇后员工池数量不匹配: %d != %d" % [pool_after_busy, pool_before_busy])
	if state.get_player(payday_actor).get("busy_marketers", []).has("campaign_manager"):
		return Result.failure("忙碌营销员解雇后不应仍包含 campaign_manager")

	var online_parallel := _test_online_parallel_payday_fire(seed_val)
	if not online_parallel.ok:
		return online_parallel

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"restructuring_actor": restructuring_actor,
		"payday_actor": payday_actor,
		"fire_in_restructuring_error": fire_in_restructuring.error,
		"fire_busy_denied_error": fire_busy_denied.error
	})

static func _test_online_parallel_payday_fire(seed_val: int) -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode = NetContext.mode
	var prev_local_player_id := int(NetContext.local_player_id)

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val + 101)
	if not init.ok:
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online fire 测试初始化失败: %s" % init.error)

	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_PAYDAY, 40)
	if not to_payday.ok:
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online fire 测试推进失败: %s" % to_payday.error)

	NetContext.mode = NetContext.Mode.ONLINE_SERVER
	NetContext.local_player_id = -1

	var state := engine.get_state()
	var current_actor := int(state.get_current_player_id())
	var other_actor := 1 if current_actor == 0 else 0

	var pool_before: int = int(state.employee_pool.get("pizza_cook", 0))
	if pool_before <= 0:
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online fire 测试员工池中 pizza_cook 数量不足")
	state.employee_pool["pizza_cook"] = pool_before - 1
	state.players[other_actor]["employees"].append("pizza_cook")

	var fire_other := engine.execute_command(Command.create("fire", other_actor, {"employee_id": "pizza_cook"}))
	if not fire_other.ok:
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online payday 非当前玩家 fire 应成功，实际失败: %s" % fire_other.error)

	state = engine.get_state()
	var pool_after: int = int(state.employee_pool.get("pizza_cook", 0))
	if pool_after != pool_before:
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online payday 非当前玩家 fire 后员工池数量不匹配: %d != %d" % [pool_after, pool_before])
	if state.get_player(other_actor).get("employees", []).has("pizza_cook"):
		_restore_net_context(prev_mode, prev_local_player_id)
		return Result.failure("online payday 非当前玩家 fire 后仍包含 pizza_cook")

	_restore_net_context(prev_mode, prev_local_player_id)
	return Result.success()

static func _restore_net_context(prev_mode, prev_local_player_id: int) -> void:
	if NetContext == null:
		return
	NetContext.mode = prev_mode
	NetContext.local_player_id = prev_local_player_id
