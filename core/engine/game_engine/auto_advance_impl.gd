# GameEngine：自动推进规则（实现）
# 说明：
# - 这些推进不应依赖 UI，必须完全由 state 决定，且确定性可重放。
# - Replay/rewind 使用 executor.compute_new_state 时不会经过 GameEngine.execute_command，因此需要在回放侧同样执行 auto-advance。
extends RefCounted

const TryStepClass = preload("res://core/engine/game_engine/auto_advance_try_step.gd")
const DrainStepsClass = preload("res://core/engine/game_engine/auto_advance_drain_steps.gd")

static func drain(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry, max_steps: int = 32) -> Result:
	var drain_r := DrainStepsClass.drain_steps(state_in, phase_manager, action_registry, max_steps, "auto_advance")
	if not drain_r.ok:
		return drain_r
	return Result.success().with_warnings(drain_r.warnings)

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	return TryStepClass.try_advance_one(state_in, phase_manager, action_registry)
