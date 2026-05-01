extends RefCounted

const AutoAdvanceTryStepClass = preload("res://core/engine/game_engine/auto_advance_try_step.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"

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
	state.rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
	_persist_online_confirm_markers_to_initial_checkpoint(engine)

	if str(state.phase) == DefsClass.PHASE_DINNERTIME:
		var repair_r: Result = AutoAdvanceTryStepClass._repair_online_dinnertime_pending_guard_for_resume(state)
		if not repair_r.ok:
			return repair_r

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

static func _persist_online_confirm_markers_to_initial_checkpoint(engine: GameEngine) -> void:
	if engine == null or engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return
	var checkpoint0: Dictionary = Dictionary(engine.checkpoints[0]).duplicate(true)
	var state_dict_val = checkpoint0.get("state_dict", null)
	if not (state_dict_val is Dictionary):
		return
	var state_dict: Dictionary = Dictionary(state_dict_val).duplicate(true)
	var rules: Dictionary = Dictionary(state_dict.get("rules", {})).duplicate(true) if state_dict.get("rules", null) is Dictionary else {}
	var can_persist_dinnertime := int(engine.current_command_index) < 0 or _has_player_confirm_command(engine, "confirm_dinnertime")
	var can_persist_marketing := int(engine.current_command_index) < 0 or _has_player_confirm_command(engine, "confirm_marketing")
	var changed := false
	if can_persist_dinnertime and int(rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, 0)) != 1:
		rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
		changed = true
	if can_persist_marketing and int(rules.get(ONLINE_MARKETING_CONFIRM_KEY, 0)) != 1:
		rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
		changed = true
	if not changed:
		return
	state_dict["rules"] = rules
	checkpoint0["state_dict"] = state_dict
	var state_read := GameState.from_dict(state_dict)
	if state_read.ok and state_read.value != null:
		checkpoint0["hash"] = state_read.value.compute_hash()
	engine.checkpoints[0] = checkpoint0

static func _has_player_confirm_command(engine: GameEngine, action_id: String) -> bool:
	if engine == null:
		return false
	for cmd in engine.command_history:
		if cmd == null:
			continue
		if str(cmd.action_id) != action_id:
			continue
		if int(cmd.actor) >= 0:
			return true
	return false

static func validate_resume_point(
	engine: GameEngine,
	persist_current_state_to_checkpoint: bool = true
) -> Result:
	var validation_engine_r := _build_validation_engine(engine)
	if not validation_engine_r.ok:
		return validation_engine_r
	var validation_engine: GameEngine = validation_engine_r.value
	var prepare_r: Result = prepare_engine_for_online_resume(validation_engine, persist_current_state_to_checkpoint)
	if not prepare_r.ok:
		return prepare_r
	var validate_r: Result = _validate_prepared_resume_point(validation_engine)
	return validate_r.with_warnings(prepare_r.warnings)

static func prepare_and_validate_resume_point(
	engine: GameEngine,
	persist_current_state_to_checkpoint: bool = true
) -> Result:
	var prepare_r: Result = prepare_engine_for_online_resume(engine, persist_current_state_to_checkpoint)
	if not prepare_r.ok:
		return prepare_r
	var validate_r: Result = _validate_prepared_resume_point(engine)
	return validate_r.with_warnings(prepare_r.warnings)

static func _validate_prepared_resume_point(engine: GameEngine) -> Result:
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
			})

	return Result.failure("当前恢复点没有任何玩家可执行动作，联机恢复后将无法推进")

static func _build_validation_engine(engine: GameEngine) -> Result:
	if engine == null or not is_instance_valid(engine):
		return Result.failure("恢复引擎为空")
	if not engine.has_method("create_archive"):
		return Result.failure("恢复引擎缺少 create_archive")
	var archive_r: Result = engine.create_archive()
	if not archive_r.ok:
		return Result.failure("构造恢复点验证快照失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var validation_engine := GameEngine.new()
	var load_r: Result = validation_engine.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("加载恢复点验证快照失败: %s" % load_r.error)
	return Result.success(validation_engine)
