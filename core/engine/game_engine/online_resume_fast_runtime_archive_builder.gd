extends RefCounted

const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")

class _LocalEventSink:
	extends RefCounted

	func clear_history_and_reset_sequence() -> void:
		pass

	func clear_history() -> void:
		pass

	func emit_event(_event_type: String, _data: Dictionary) -> void:
		pass

# Phase 1（仅服务端旁路能力）：
# - 服务器权威 engine 仍保持完整历史；
# - 这里仅根据完整历史 engine 构造“客户端未来可用”的短链 runtime archive；
# - 当前阶段不切换现有 live 启动链路，避免在客户端双轨未落地前破坏硬约束。
static func build_from_engine(engine: GameEngine, options: Dictionary = {}) -> Result:
	if engine == null:
		return Result.failure("engine 不能为空")

	var init_r: Result = engine.ensure_initialized()
	if not init_r.ok:
		return init_r

	if engine.checkpoints.is_empty():
		return Result.failure("缺少 checkpoint，无法构造 runtime archive")
	if engine.current_command_index < -1:
		return Result.failure("current_command_index 非法: %d" % int(engine.current_command_index))
	if engine.current_command_index >= engine.command_history.size():
		return Result.failure(
			"current_command_index 越界: %d >= %d"
				% [int(engine.current_command_index), int(engine.command_history.size())]
		)

	var full_archive: Dictionary = Dictionary(options.get("full_archive", {})).duplicate(true)
	if full_archive.is_empty():
		var archive_r: Result = engine.create_archive()
		if not archive_r.ok:
			return Result.failure("create_archive failed: %s" % archive_r.error)
		full_archive = Dictionary(archive_r.value).duplicate(true)

	var target_index := int(engine.current_command_index)
	var anchor_command_start_r: Result = _select_anchor_command_start_index(engine, options)
	if not anchor_command_start_r.ok:
		return anchor_command_start_r
	var anchor_command_start_index := int(anchor_command_start_r.value)
	if target_index >= 0 and (anchor_command_start_index < 0 or anchor_command_start_index > target_index):
		return Result.failure(
			"anchor_command_start_index 非法: %d (target=%d)"
				% [anchor_command_start_index, target_index]
		)
	if target_index < 0:
		anchor_command_start_index = 0

	var anchor_snapshot_r: Result = _build_anchor_snapshot(engine, full_archive, anchor_command_start_index)
	if not anchor_snapshot_r.ok:
		return anchor_snapshot_r
	var anchor_snapshot: Dictionary = Dictionary(anchor_snapshot_r.value).duplicate(true)

	var runtime_archive: Dictionary = full_archive.duplicate(true)
	runtime_archive["initial_state"] = Dictionary(anchor_snapshot.get("state_dict", {})).duplicate(true)
	runtime_archive["commands"] = _serialize_runtime_commands(engine.command_history, anchor_command_start_index, target_index)
	runtime_archive["checkpoints"] = _build_runtime_checkpoint_metadata(
		engine.checkpoints,
		anchor_snapshot,
		anchor_command_start_index,
		target_index
	)
	runtime_archive["current_index"] = target_index - anchor_command_start_index
	if target_index < 0:
		runtime_archive["current_index"] = -1

	var runtime_anchor := {
		"global_command_start_index": anchor_command_start_index,
		"global_command_end_index": target_index,
		"global_step_start_index_hint": -1,
		"global_step_end_index_hint": -1,
		"checkpoint_id": "resume_cp_%d" % anchor_command_start_index,
		"state_hash": str(anchor_snapshot.get("hash", "")).strip_edges(),
	}

	return Result.success({
		"runtime_archive": runtime_archive,
		"runtime_anchor": runtime_anchor,
		"runtime_command_count": Array(runtime_archive.get("commands", [])).size(),
		"full_command_count": int(engine.command_history.size()),
		"shortened": anchor_command_start_index > 0,
	})

static func _select_anchor_command_start_index(engine: GameEngine, options: Dictionary) -> Result:
	var target_index := int(engine.current_command_index)
	if target_index < 0:
		return Result.success(0)

	var preferred_anchor_command_start_index := target_index
	var turn_start_r: Result = engine.find_current_player_turn_start_command_index()
	if turn_start_r.ok:
		var rewind_target := int(turn_start_r.value)
		preferred_anchor_command_start_index = mini(target_index, maxi(0, rewind_target + 1))
	if options.has("anchor_command_start_index"):
		preferred_anchor_command_start_index = int(options.get("anchor_command_start_index", preferred_anchor_command_start_index))
	return Result.success(clampi(preferred_anchor_command_start_index, 0, maxi(0, target_index)))

static func _build_anchor_snapshot(
	engine: GameEngine,
	full_archive: Dictionary,
	anchor_command_start_index: int
) -> Result:
	var exact_checkpoint := _find_checkpoint_with_exact_index(engine.checkpoints, anchor_command_start_index)
	if not exact_checkpoint.is_empty() and exact_checkpoint.get("state_dict", null) is Dictionary:
		return Result.success({
			"index": anchor_command_start_index,
			"state_dict": Dictionary(exact_checkpoint.get("state_dict", {})).duplicate(true),
			"hash": str(exact_checkpoint.get("hash", "")).strip_edges(),
			"rng_calls": int(exact_checkpoint.get("rng_calls", 0)),
		})

	var probe_engine := GameEngine.new()
	probe_engine.set_event_sink(_LocalEventSink.new())
	var load_r: Result = probe_engine.load_from_archive(full_archive)
	if not load_r.ok:
		return Result.failure("probe load_from_archive failed: %s" % load_r.error)

	var rewind_target := anchor_command_start_index - 1
	if int(probe_engine.current_command_index) != rewind_target:
		var rewind_r: Result = probe_engine.rewind_to_command(rewind_target)
		if not rewind_r.ok:
			return Result.failure("probe rewind_to_command failed: %s" % rewind_r.error)

	var state = probe_engine.get_state()
	if state == null:
		return Result.failure("probe anchor state missing")

	return Result.success({
		"index": anchor_command_start_index,
		"state_dict": state.to_dict().duplicate(true),
		"hash": str(state.compute_hash()),
		"rng_calls": int(probe_engine.random_manager.get_call_count()) if probe_engine.random_manager != null else 0,
	})

static func _find_checkpoint_with_exact_index(checkpoints: Array[Dictionary], checkpoint_index: int) -> Dictionary:
	for checkpoint_val in checkpoints:
		if not (checkpoint_val is Dictionary):
			continue
		var checkpoint: Dictionary = Dictionary(checkpoint_val)
		if int(checkpoint.get("index", -1)) != checkpoint_index:
			continue
		return checkpoint.duplicate(true)
	return {}

static func _serialize_runtime_commands(
	command_history: Array[Command],
	anchor_command_start_index: int,
	target_index: int
) -> Array:
	if target_index < anchor_command_start_index:
		return []

	var commands: Array[Command] = []
	for i in range(anchor_command_start_index, target_index + 1):
		var cmd: Command = command_history[i]
		if cmd == null:
			continue
		commands.append(cmd)
	return ArchiveClass.serialize_commands(commands)

static func _build_runtime_checkpoint_metadata(
	checkpoints: Array[Dictionary],
	anchor_snapshot: Dictionary,
	anchor_command_start_index: int,
	target_index: int
) -> Array:
	var out: Array = [{
		"index": 0,
		"hash": str(anchor_snapshot.get("hash", "")).strip_edges(),
		"rng_calls": int(anchor_snapshot.get("rng_calls", 0)),
	}]
	var checkpoint_upper_bound := target_index + 1
	for checkpoint_val in checkpoints:
		if not (checkpoint_val is Dictionary):
			continue
		var checkpoint: Dictionary = Dictionary(checkpoint_val)
		var checkpoint_index := int(checkpoint.get("index", -1))
		if checkpoint_index <= anchor_command_start_index or checkpoint_index > checkpoint_upper_bound:
			continue
		out.append({
			"index": checkpoint_index - anchor_command_start_index,
			"hash": str(checkpoint.get("hash", "")).strip_edges(),
			"rng_calls": int(checkpoint.get("rng_calls", 0)),
		})
	return out
