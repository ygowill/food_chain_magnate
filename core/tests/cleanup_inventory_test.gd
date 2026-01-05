# 清理阶段库存处理测试（M3）
# 验证：进入 Cleanup 阶段时库存按“无冰箱清空 / 有冰箱限幅（每种各自限幅）”规则处理
class_name CleanupInventoryTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count < 2:
		return Result.failure("测试至少需要 2 名玩家")

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	# 推进到 Marketing 阶段（进入 Cleanup 时触发清理）
	var to_marketing := TestPhaseUtilsClass.advance_until_phase(engine, "Marketing", 50)
	if not to_marketing.ok:
		return to_marketing

	var state := engine.get_state()
	if state.phase != "Marketing":
		return Result.failure("当前应该在 Marketing 阶段，实际: %s" % state.phase)

	# 玩家 0：无冰箱 -> 清空
	state.players[0]["inventory"] = {
		"burger": 3,
		"pizza": 1,
		"soda": 2,
		"lemonade": 4,
		"beer": 5
	}

	# 玩家 1：有冰箱 -> 每种各自限幅到 10
	var claim := StateUpdater.claim_milestone(state, 1, "first_throw_away")
	if not claim.ok:
		return Result.failure("为玩家 1 领取 first_throw_away 失败: %s" % claim.error)

	state.players[1]["inventory"] = {
		"burger": 12,
		"pizza": 9,
		"soda": 20,
		"lemonade": 0,
		"beer": 10
	}

	# 进入 Cleanup 阶段（触发清理结算）
	var to_cleanup := Command.create("advance_phase", -1, {})
	var cleanup_result := engine.execute_command(to_cleanup)
	if not cleanup_result.ok:
		return Result.failure("推进到 Cleanup 阶段失败: %s" % cleanup_result.error)

	state = engine.get_state()
	if state.phase != "Cleanup":
		return Result.failure("当前应该在 Cleanup 阶段，实际: %s" % state.phase)

	var inv0: Dictionary = state.players[0].get("inventory", {})
	for k in inv0:
		if int(inv0.get(k, 0)) != 0:
			return Result.failure("玩家 0 在 Cleanup 后库存应清空，但 %s=%d" % [str(k), int(inv0.get(k, 0))])

	var inv1: Dictionary = state.players[1].get("inventory", {})
	if int(inv1.get("burger", 0)) != 10:
		return Result.failure("玩家 1 burger 应限幅到 10，实际: %d" % int(inv1.get("burger", 0)))
	if int(inv1.get("pizza", 0)) != 9:
		return Result.failure("玩家 1 pizza 应保留 9，实际: %d" % int(inv1.get("pizza", 0)))
	if int(inv1.get("soda", 0)) != 10:
		return Result.failure("玩家 1 soda 应限幅到 10，实际: %d" % int(inv1.get("soda", 0)))
	if int(inv1.get("beer", 0)) != 10:
		return Result.failure("玩家 1 beer 应保留 10，实际: %d" % int(inv1.get("beer", 0)))

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"p0_inventory": inv0,
		"p1_inventory": inv1
	})
