# ConfirmDinnertimeAction：pending_phase_actions 的 key 必须与阶段名一致（Dinnertime），否则会导致 auto-advance 误跳过
class_name ConfirmDinnertimePendingPhaseActionsKeyTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ConfirmDinnertimeActionClass = preload("res://gameplay/actions/confirm_dinnertime_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.state
	state.phase = DefsClass.PHASE_DINNERTIME
	state.sub_phase = ""
	if not (state.round_state is Dictionary):
		state.round_state = {}

	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: ["confirm_dinnertime"],
	}

	var action := ConfirmDinnertimeActionClass.new()
	var cmd := Command.create_system("confirm_dinnertime")
	var new_state_r: Result = action.compute_new_state(state, cmd)
	if not new_state_r.ok:
		return Result.failure("confirm_dinnertime 计算新状态失败: %s" % new_state_r.error)

	var new_state: GameState = new_state_r.value
	if not (new_state.round_state is Dictionary):
		return Result.failure("confirm_dinnertime 后 round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = new_state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("confirm_dinnertime 后 pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val

	if ppa.has(DefsClass.PHASE_DINNERTIME):
		return Result.failure("confirm_dinnertime 后 pending_phase_actions[Dinnertime] 应被清除")
	if ppa.has("dinnertime"):
		return Result.failure("confirm_dinnertime 不应写入 pending_phase_actions[dinnertime]（大小写错误）")

	return Result.success()

