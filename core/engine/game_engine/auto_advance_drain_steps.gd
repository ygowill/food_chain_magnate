# GameEngine：auto-advance drain 循环契约
# 只负责推进循环、safety 与 before/after 快照；事件和时间线投影留给调用层。
extends RefCounted

const TryStepClass = preload("res://core/engine/game_engine/auto_advance_try_step.gd")

static func drain_steps(
	state_in: GameState,
	phase_manager: PhaseManager,
	action_registry: ActionRegistry,
	max_steps: int = 32,
	context: String = "auto_advance"
) -> Result:
	var prefix := str(context).strip_edges()
	if prefix.is_empty():
		prefix = "auto_advance"
	if state_in == null:
		return Result.failure("%s: state 为空" % prefix)
	if phase_manager == null:
		return Result.failure("%s: phase_manager 为空" % prefix)
	if action_registry == null:
		return Result.failure("%s: action_registry 为空" % prefix)
	if max_steps <= 0:
		return Result.failure("%s: max_steps 必须 > 0" % prefix)

	var steps: Array[Dictionary] = []
	var warnings: Array[String] = []
	var safety := 0

	while safety < max_steps:
		safety += 1
		var before := state_in.duplicate_state()
		var step: Result = TryStepClass.try_advance_one(state_in, phase_manager, action_registry)
		if not step.ok:
			return step.with_warnings(warnings)
		warnings.append_array(step.warnings)
		if not bool(step.value):
			return Result.success({
				"state": state_in,
				"steps": steps,
			}).with_warnings(warnings)

		steps.append({
			"before": before,
			"after": state_in.duplicate_state(),
		})

	return Result.failure("%s: exceeded max steps (possible loop)" % prefix).with_warnings(warnings)
