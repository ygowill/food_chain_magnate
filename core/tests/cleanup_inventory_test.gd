# 清理阶段库存处理测试（M3）
# 验证：
# - 无冰箱：清空库存
# - 有冰箱：food+drink 总量 <= cap；若超出则进入 pending，需玩家选择保留哪些商品
class_name CleanupInventoryTest
extends RefCounted

const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count < 2:
		return Result.failure("测试至少需要 2 名玩家")

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var state := engine.get_state()
	# 测试只关注 Cleanup 逻辑：手动切到 Cleanup（round=1 -> 离开 Cleanup 将进入 round=2）
	state.phase = DefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.round_number = 1
	state.turn_order = [0, 1]
	state.current_player_index = 0

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

	# 触发清理结算（不依赖阶段推进细节）
	var cleanup_result := CleanupSettlementClass.apply(state)
	if not cleanup_result.ok:
		return Result.failure("CleanupSettlement 失败: %s" % cleanup_result.error)

	var inv0: Dictionary = state.players[0].get("inventory", {})
	for k in inv0:
		if int(inv0.get(k, 0)) != 0:
			return Result.failure("玩家 0 在 Cleanup 后库存应清空，但 %s=%d" % [str(k), int(inv0.get(k, 0))])

	# 玩家 1：总量超出 cap，需要进入 pending（不应自动丢弃/限幅）
	var inv1: Dictionary = state.players[1].get("inventory", {})
	if int(inv1.get("burger", 0)) != 12:
		return Result.failure("玩家 1 burger 在选择前不应被自动改动，实际: %d" % int(inv1.get("burger", 0)))
	if int(inv1.get("soda", 0)) != 20:
		return Result.failure("玩家 1 soda 在选择前不应被自动改动，实际: %d" % int(inv1.get("soda", 0)))

	# pending_phase_actions[Cleanup] 应包含玩家 1，并将 current_player_index 对齐到玩家 1
	if state.get_current_player_id() != 1:
		return Result.failure("Cleanup pending 时当前玩家应为 1，实际: %d" % state.get_current_player_id())
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("缺少 pending_phase_actions")
	var ppa: Dictionary = ppa_val
	var pending_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (pending_val is Array):
		return Result.failure("pending_phase_actions[Cleanup] 类型错误（期望 Array）")
	var pending: Array = pending_val
	if pending.size() != 1:
		return Result.failure("pending_phase_actions[Cleanup] 应只有 1 个待处理项，实际: %s" % str(pending))
	if not (pending[0] is Dictionary):
		return Result.failure("pending_phase_actions[Cleanup][0] 类型错误（期望 Dictionary）: %s" % str(pending[0]))
	var task: Dictionary = pending[0]
	if str(task.get("kind", "")) != "fridge_keep" or int(task.get("player_id", -1)) != 1:
		return Result.failure("pending_phase_actions[Cleanup] 应为 fridge_keep(player=1)，实际: %s" % str(pending))

	# 执行选择：允许主动保留少于 cap
	var choose := engine.execute_command(Command.create("choose_fridge_keep", 1, {"keep": {"pizza": 3, "beer": 2}}))
	if not choose.ok:
		return Result.failure("choose_fridge_keep 失败: %s" % choose.error)

	var state_after: GameState = engine.get_state()
	var ppa_after_val = state_after.round_state.get("pending_phase_actions", null)
	if ppa_after_val is Dictionary and Dictionary(ppa_after_val).has(DefsClass.PHASE_CLEANUP):
		return Result.failure("choose_fridge_keep 后不应残留 pending_phase_actions[Cleanup]")

	var inv1_after: Dictionary = state_after.players[1].get("inventory", {})
	var kept_total := 0
	for pid in ["burger", "pizza", "soda", "lemonade", "beer"]:
		kept_total += int(inv1_after.get(pid, 0))
	if kept_total != 5:
		return Result.failure("玩家 1 选择后应总计保留 5，实际: %d inv=%s" % [kept_total, str(inv1_after)])
	if int(inv1_after.get("pizza", 0)) != 3 or int(inv1_after.get("beer", 0)) != 2:
		return Result.failure("玩家 1 选择后保留数量不正确: inv=%s" % str(inv1_after))

	# Case 2：有冰箱但总量 <= cap 时，不应进入 pending
	var engine2 := GameEngine.new()
	var init2 := engine2.initialize(player_count, seed_val)
	if not init2.ok:
		return Result.failure("游戏初始化失败(case2): %s" % init2.error)
	var state2 := engine2.get_state()
	state2.phase = DefsClass.PHASE_CLEANUP
	state2.sub_phase = ""
	state2.round_number = 1
	state2.turn_order = [0, 1]
	state2.current_player_index = 0

	var claim2 := StateUpdater.claim_milestone(state2, 1, "first_throw_away")
	if not claim2.ok:
		return Result.failure("为玩家 1 领取 first_throw_away 失败(case2): %s" % claim2.error)

	state2.players[1]["inventory"] = {
		"burger": 4,
		"pizza": 3,
		"soda": 0,
		"lemonade": 0,
		"beer": 2
	}

	var cleanup2 := CleanupSettlementClass.apply(state2)
	if not cleanup2.ok:
		return Result.failure("CleanupSettlement 失败(case2): %s" % cleanup2.error)
	var ppa2_val = state2.round_state.get("pending_phase_actions", null)
	if ppa2_val is Dictionary and Dictionary(ppa2_val).has(DefsClass.PHASE_CLEANUP):
		return Result.failure("case2 不应进入 pending_phase_actions[Cleanup]")
	var inv1_case2: Dictionary = state2.players[1].get("inventory", {})
	if int(inv1_case2.get("burger", 0)) != 4 or int(inv1_case2.get("pizza", 0)) != 3 or int(inv1_case2.get("beer", 0)) != 2:
		return Result.failure("case2 库存不应被自动改动: %s" % str(inv1_case2))

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"p0_inventory": inv0,
		"p1_inventory_before": inv1,
		"p1_inventory_after": inv1_after,
		"p1_inventory_case2": inv1_case2,
	})
