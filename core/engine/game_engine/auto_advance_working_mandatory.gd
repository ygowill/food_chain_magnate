extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

# 可自动补完的强制动作（定价/折扣/奢侈品）：
# - 这些动作无参数，且允许在 Working 任意子阶段执行。
# - 若不自动补完，会被 ActionRegistry 视为“可启动动作”，从而阻止 Working 子阶段的 auto-advance（造成软锁/需要手动跳过）。
const AUTO_MANDATORY_ACTION_IDS: Array[String] = [
	ActionIdsClass.SET_PRICE,
	ActionIdsClass.SET_DISCOUNT,
	ActionIdsClass.SET_LUXURY_PRICE,
]

static func try_auto_complete_working_mandatory_actions(state_in: GameState, action_registry: ActionRegistry) -> Result:
	if state_in == null:
		return Result.failure("auto_mandatory: state 为空")
	if action_registry == null:
		return Result.failure("auto_mandatory: action_registry 为空")
	if state_in.phase != DefsClass.PHASE_WORKING:
		return Result.success(false)

	var pid := state_in.get_current_player_id()
	if pid < 0:
		return Result.failure("auto_mandatory: Working 当前玩家无效")

	for aid in AUTO_MANDATORY_ACTION_IDS:
		var action_id := str(aid).strip_edges()
		if action_id.is_empty():
			continue

		var executor := action_registry.get_executor(action_id)
		if executor == null:
			continue

		var cmd := Command.create(action_id, pid, {"auto": true})
		cmd.phase = state_in.phase
		cmd.sub_phase = state_in.sub_phase

		var gate := action_registry.run_validators(state_in, cmd)
		if not gate.ok:
			continue

		var vr: Result = executor.validate(state_in, cmd)
		if not vr.ok:
			continue

		# IMPORTANT: 执行器的 _apply_changes 设计为“对 duplicate_state 的变更”，这里直接对 state_in 应用，
		# 以保持 AutoAdvance 的 in-place 语义（CommandRunner/Replay 依赖此行为）。
		var ar: Result = executor.apply_changes_in_place(state_in, cmd)
		if not ar.ok:
			return ar
		return Result.success(true).with_warnings(ar.warnings)

	return Result.success(false)
