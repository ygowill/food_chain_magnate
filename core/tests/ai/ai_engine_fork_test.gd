class_name AiEngineForkTest
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)

	var fork_read := AiEngineForkClass.fork_from_engine(engine)
	if not fork_read.ok:
		return fork_read
	var fork: GameEngine = fork_read.value
	var source_hash_before := str(engine.get_state().compute_hash())
	if str(fork.get_state().compute_hash()) != source_hash_before:
		return Result.failure("fork hash should match source before simulation")

	var actor := engine.get_state().get_current_player_id()
	var command := Command.create("select_reserve_card", actor, {"selected_index": 0})
	var fork_exec := fork.execute_command(command.duplicate_command())
	if not fork_exec.ok:
		return Result.failure("fork execute failed: %s" % fork_exec.error)
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("source hash changed after fork execute")

	var source_exec := engine.execute_command(command.duplicate_command())
	if not source_exec.ok:
		return Result.failure("source execute failed: %s" % source_exec.error)
	if str(engine.get_state().compute_hash()) != str(fork.get_state().compute_hash()):
		return Result.failure("source/fork hash mismatch after same command")
	return Result.success()
