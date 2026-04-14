extends RefCounted

const AutoAdvanceTryStepClass = preload("res://core/engine/game_engine/auto_advance_try_step.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"

static func prepare_engine_for_online_resume(
	engine: GameEngine,
	persist_current_state_to_checkpoint: bool = true
) -> Result:
	if engine == null or not is_instance_valid(engine):
		return Result.failure("恢复引擎为空")
	if not engine.has_method("get_state"):
		return Result.failure("恢复引擎缺少 get_state")

	var state = engine.get_state()
	if state == null:
		return Result.failure("恢复状态为空")
	if not (state.rules is Dictionary):
		state.rules = {}
	state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1

	if str(state.phase) == DefsClass.PHASE_DINNERTIME:
		AutoAdvanceTryStepClass._ensure_online_dinnertime_pending_guard(state)

	if persist_current_state_to_checkpoint and int(engine.current_command_index) < 0 and engine.checkpoints.size() > 0 and (engine.checkpoints[0] is Dictionary):
		var checkpoint0: Dictionary = Dictionary(engine.checkpoints[0]).duplicate(true)
		checkpoint0["state_dict"] = state.to_dict().duplicate(true)
		checkpoint0["hash"] = state.compute_hash()
		checkpoint0["rng_calls"] = int(engine.random_manager.get_call_count()) if engine.random_manager != null else 0
		engine.checkpoints[0] = checkpoint0

	return Result.success({
		"phase": str(state.phase),
		"current_index": int(engine.current_command_index),
		"history_size": int(engine.command_history.size()),
		"state_hash": str(state.compute_hash()),
	})

static func validate_resume_point(
	engine: GameEngine,
	persist_current_state_to_checkpoint: bool = true
) -> Result:
	var prepare_r: Result = prepare_engine_for_online_resume(engine, persist_current_state_to_checkpoint)
	if not prepare_r.ok:
		return prepare_r

	var state = engine.get_state()
	if state == null:
		return Result.failure("恢复状态为空")
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		return Result.failure("当前恢复点处于游戏结束阶段，不能用于联机恢复")
	if not (state.players is Array):
		return Result.failure("恢复状态缺少玩家列表")
	if engine.action_registry == null:
		return Result.failure("恢复引擎缺少 ActionRegistry")

	for player_id in range(state.players.size()):
		var initiatable: Array[String] = engine.action_registry.get_player_initiatable_actions(state, player_id)
		if not initiatable.is_empty():
			return Result.success({
				"player_id": player_id,
				"initiatable_actions": initiatable.duplicate(),
				"state_hash": str(state.compute_hash()),
			}).with_warnings(prepare_r.warnings)

	return Result.failure("当前恢复点没有任何玩家可执行动作，联机恢复后将无法推进").with_warnings(prepare_r.warnings)
