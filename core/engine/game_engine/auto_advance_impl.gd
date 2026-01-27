# GameEngine：自动推进规则（实现）
# 说明：
# - 这些推进不应依赖 UI，必须完全由 state 决定，且确定性可重放。
# - Replay/rewind 使用 executor.compute_new_state 时不会经过 GameEngine.execute_command，因此需要在回放侧同样执行 auto-advance。
extends RefCounted

const TryStepClass = preload("res://core/engine/game_engine/auto_advance_try_step.gd")

static func drain(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry, max_steps: int = 32) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")
	if phase_manager == null:
		return Result.failure("auto_advance: phase_manager 为空")
	if action_registry == null:
		return Result.failure("auto_advance: action_registry 为空")
	if max_steps <= 0:
		return Result.failure("auto_advance: max_steps 必须 > 0")

	var warnings: Array[String] = []
	var safety := 0

	while safety < max_steps:
		safety += 1
		var step: Result = try_advance_one(state_in, phase_manager, action_registry)
		if not step.ok:
			return step
		warnings.append_array(step.warnings)
		if not bool(step.value):
			return Result.success().with_warnings(warnings)

	return Result.failure("auto_advance: exceeded max steps (possible loop)").with_warnings(warnings)

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	return TryStepClass.try_advance_one(state_in, phase_manager, action_registry)
