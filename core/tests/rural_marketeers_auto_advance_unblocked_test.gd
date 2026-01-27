# RuralMarketeers 回归测试：
# - 没有 rural_marketeer 时，place_giant_billboard 不应被判定为“可启动动作”（缺参不应导致误判）
# - 否则会阻塞 Working/Marketing 子阶段的 auto-advance（issue_tracker #78）
class_name RuralMarketeersAutoAdvanceUnblockedTest
extends RefCounted

const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const ACTION_ID := "place_giant_billboard"
const EMPLOYEE_ID := "rural_marketeer"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("游戏初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 60)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	var pid := state.get_current_player_id()
	if pid < 0:
		return Result.failure("无法获取当前玩家 ID")

	# 构造：进入 Working/Marketing，且当前玩家没有任何营销相关员工，
	# 使“无真实动作”成为预期，从而验证 auto-advance 不应被 place_giant_billboard 阻塞。
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.players[pid]["employees"] = []

	var initiatable := engine.action_registry.get_player_initiatable_actions(state, pid)
	if initiatable.has(ACTION_ID):
		return Result.failure("%s 不应在无 %s 时被判定为可启动: %s" % [ACTION_ID, EMPLOYEE_ID, str(initiatable)])

	var before_sub := str(state.sub_phase)
	var step := AutoAdvanceClass.try_advance_one(state, engine.phase_manager, engine.action_registry)
	if not step.ok:
		return Result.failure("auto_advance 失败: %s" % step.error).with_warnings(step.warnings)
	if not bool(step.value):
		return Result.failure("auto_advance 未推进（可能被可启动动作阻塞）：sub_phase=%s" % before_sub).with_warnings(step.warnings)
	if str(state.sub_phase) == before_sub:
		return Result.failure("auto_advance 未改变子阶段：%s" % before_sub).with_warnings(step.warnings)

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"player_id": pid,
		"before_sub_phase": before_sub,
		"after_sub_phase": str(state.sub_phase),
	})
