# GameEngine：自动推进规则（用于运行时与回放/倒带一致性）
# 说明：
# - 这些推进不应依赖 UI，必须完全由 state 决定，且确定性可重放。
# - Replay/rewind 使用 executor.compute_new_state 时不会经过 GameEngine.execute_command，因此需要在回放侧同样执行 auto-advance。
class_name AutoAdvance
extends RefCounted

const Impl = preload("res://core/engine/game_engine/auto_advance_impl.gd")

static func drain(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry, max_steps: int = 32) -> Result:
	return Impl.drain(state_in, phase_manager, action_registry, max_steps)

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	return Impl.try_advance_one(state_in, phase_manager, action_registry)
