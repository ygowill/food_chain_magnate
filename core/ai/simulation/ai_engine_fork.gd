class_name AiEngineFork
extends RefCounted

static func fork_from_engine(source: GameEngine) -> Result:
	if source == null:
		return Result.failure("AiEngineFork.fork_from_engine: source engine is null")
	var source_state := source.get_state()
	if source_state == null:
		return Result.failure("AiEngineFork.fork_from_engine: source state is null")

	var archive_read := source.create_archive()
	if not archive_read.ok:
		return Result.failure("AiEngineFork.fork_from_engine: create_archive failed: %s" % archive_read.error)
	var archive: Dictionary = Dictionary(archive_read.value).duplicate(true)

	var fork := GameEngine.new()
	var load_read := fork.load_from_archive(archive)
	if not load_read.ok:
		return Result.failure("AiEngineFork.fork_from_engine: load_from_archive failed: %s" % load_read.error)
	var fork_state := fork.get_state()
	if fork_state == null:
		return Result.failure("AiEngineFork.fork_from_engine: fork state is null")

	var source_hash := str(source_state.compute_hash())
	var fork_hash := str(fork_state.compute_hash())
	if source_hash != fork_hash:
		return Result.failure("AiEngineFork.fork_from_engine: hash mismatch source=%s fork=%s" % [source_hash, fork_hash])
	return Result.success(fork)
