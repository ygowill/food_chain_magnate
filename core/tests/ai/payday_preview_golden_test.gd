class_name PaydayPreviewGoldenTest
extends RefCounted

const PaydayPreviewClass = preload("res://core/ai/analysis/payday_preview.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var basic := _test_preview_from_payday_matches_real_settlement(seed_val)
	if not basic.ok:
		return basic
	var fire := _test_preview_after_fire_matches_real_settlement(seed_val)
	if not fire.ok:
		return fire
	return Result.success({"cases": 2})

static func _test_preview_from_payday_matches_real_settlement(seed_val: int) -> Result:
	var source_read := _build_payday_source_engine(seed_val, ["burger_cook"], 20)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value
	var source_hash_before := str(source.get_state().compute_hash())

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var preview_read := PaydayPreviewClass.preview_after_commands(source, [], {"max_steps": 8})
	if not preview_read.ok:
		return preview_read
	if str(source.get_state().compute_hash()) != source_hash_before:
		return Result.failure("PaydayPreview should not mutate source engine")
	if MilestoneEffectRegistryClass.get_current() != source.ruleset_v2.milestone_effect_registry:
		return Result.failure("PaydayPreview should restore source milestone effect registry")
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = Dictionary(preview.get("report", {}))

	var real_advance := _advance_real_payday_direct(real)
	if not real_advance.ok:
		return real_advance
	var report_equal := _assert_report_subset_equal(Dictionary(real.get_state().round_state.get("payday", {})), preview_report)
	if not report_equal.ok:
		return report_equal
	var preview_state_read := _preview_state(preview)
	if not preview_state_read.ok:
		return preview_state_read
	var preview_state: GameState = preview_state_read.value
	if str(preview_state.phase) != DefsClass.PHASE_MARKETING:
		return Result.failure("PaydayPreview should stop at Marketing after Payday settlement, got %s/%s" % [str(preview_state.phase), str(preview_state.sub_phase)])
	if str(preview_state.compute_hash()) != str(real.get_state().compute_hash()):
		return Result.failure("PaydayPreview final state hash mismatch\nreal=%s\npreview=%s" % [
			str(real.get_state().compute_hash()),
			str(preview_state.compute_hash()),
		])
	return _assert_payday_values(preview_report, 0, 5, 5, 0)

static func _test_preview_after_fire_matches_real_settlement(seed_val: int) -> Result:
	var source_read := _build_payday_source_engine(seed_val, ["burger_cook", "pizza_cook"], 5)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value
	var source_hash_before := str(source.get_state().compute_hash())

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var command := Command.create("fire", 0, {
		"employee_id": "burger_cook",
		"location": "active",
	})
	var preview_read := PaydayPreviewClass.preview_after_commands(source, [command], {"max_steps": 8})
	if not preview_read.ok:
		return preview_read
	if str(source.get_state().compute_hash()) != source_hash_before:
		return Result.failure("PaydayPreview fire preview should not mutate source engine")
	if MilestoneEffectRegistryClass.get_current() != source.ruleset_v2.milestone_effect_registry:
		return Result.failure("PaydayPreview fire preview should restore source milestone effect registry")
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = Dictionary(preview.get("report", {}))
	var commands_executed: Array = Array(preview.get("commands_executed", []))
	if commands_executed.size() != 1 or str(Dictionary(commands_executed[0]).get("action_id", "")) != "fire":
		return Result.failure("PaydayPreview should record fire command execution: %s" % str(commands_executed))

	var real_fire := real.execute_command(command.duplicate_command())
	if not real_fire.ok:
		return Result.failure("real fire failed: %s" % real_fire.error)
	var real_advance := _advance_real_payday_direct(real)
	if not real_advance.ok:
		return real_advance
	var report_equal := _assert_report_subset_equal(Dictionary(real.get_state().round_state.get("payday", {})), preview_report)
	if not report_equal.ok:
		return report_equal
	var preview_state_read := _preview_state(preview)
	if not preview_state_read.ok:
		return preview_state_read
	var preview_state: GameState = preview_state_read.value
	if str(preview_state.compute_hash()) != str(real.get_state().compute_hash()):
		return Result.failure("PaydayPreview fire final state hash mismatch\nreal=%s\npreview=%s" % [
			str(real.get_state().compute_hash()),
			str(preview_state.compute_hash()),
		])
	return _assert_payday_values(preview_report, 0, 5, 5, 0)

static func _build_payday_source_engine(seed_val: int, employee_ids: Array[String], cash: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.current_player_index = 0
	var set_cash := StateUpdaterClass.set_player_cash(state, 0, cash)
	if not set_cash.ok:
		return Result.failure("set player cash failed: %s" % set_cash.error)

	for employee_id in employee_ids:
		var take := StateUpdaterClass.take_from_pool(state, employee_id, 1)
		if not take.ok:
			return Result.failure("take %s failed: %s" % [employee_id, take.error])
		var add := StateUpdaterClass.add_employee(state, 0, employee_id, false)
		if not add.ok:
			return Result.failure("add %s failed: %s" % [employee_id, add.error])

	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _clone_from_archive(source: GameEngine) -> Result:
	var archive_read := source.create_archive()
	if not archive_read.ok:
		return archive_read
	var clone := GameEngine.new()
	var load_read := clone.load_from_archive(Dictionary(archive_read.value).duplicate(true))
	if not load_read.ok:
		return load_read
	return Result.success(clone)

static func _advance_real_payday_direct(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("real engine/state is null")
	var state := engine.get_state()
	if str(state.phase) != DefsClass.PHASE_PAYDAY:
		return Result.failure("real engine expected Payday, got %s/%s" % [str(state.phase), str(state.sub_phase)])
	var advance := engine.phase_manager.advance_phase(state)
	if not advance.ok:
		return Result.failure("real direct Payday advance failed: %s" % advance.error)
	if not (state.round_state is Dictionary) or not (Dictionary(state.round_state).get("payday", null) is Dictionary):
		return Result.failure("real engine missing payday report after direct advance")
	return Result.success()

static func _preview_state(preview: Dictionary) -> Result:
	var preview_state_val = preview.get("state", null)
	if not (preview_state_val is GameState):
		return Result.failure("PaydayPreview missing preview state")
	return Result.success(preview_state_val)

static func _assert_report_subset_equal(real_report: Dictionary, preview_report: Dictionary) -> Result:
	var keys := [
		"base_due",
		"discount",
		"milestone_delta",
		"due",
		"paid",
		"unpaid",
		"details",
	]
	for key in keys:
		var real_val = real_report.get(key, null)
		var preview_val = preview_report.get(key, null)
		if str(real_val) != str(preview_val):
			return Result.failure("PaydayPreview mismatch at %s\nreal=%s\npreview=%s" % [key, str(real_val), str(preview_val)])
	return Result.success()

static func _assert_payday_values(report: Dictionary, player_id: int, due: int, paid: int, unpaid: int) -> Result:
	var due_arr: Array = Array(report.get("due", []))
	var paid_arr: Array = Array(report.get("paid", []))
	var unpaid_arr: Array = Array(report.get("unpaid", []))
	if player_id < 0 or player_id >= due_arr.size() or player_id >= paid_arr.size() or player_id >= unpaid_arr.size():
		return Result.failure("PaydayPreview arrays missing player %d: %s" % [player_id, str(report)])
	if int(due_arr[player_id]) != due:
		return Result.failure("PaydayPreview due mismatch: %d != %d" % [int(due_arr[player_id]), due])
	if int(paid_arr[player_id]) != paid:
		return Result.failure("PaydayPreview paid mismatch: %d != %d" % [int(paid_arr[player_id]), paid])
	if int(unpaid_arr[player_id]) != unpaid:
		return Result.failure("PaydayPreview unpaid mismatch: %d != %d" % [int(unpaid_arr[player_id]), unpaid])
	return Result.success()

static func _sync_initial_checkpoint_to_current_state(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("cannot sync checkpoint: engine/state is null")
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("cannot sync checkpoint: checkpoint[0] missing")
	var state := engine.get_state()
	var checkpoint: Dictionary = engine.checkpoints[0]
	checkpoint["state_dict"] = state.to_dict().duplicate(true)
	checkpoint["hash"] = state.compute_hash()
	engine.checkpoints[0] = checkpoint
	engine.command_history.clear()
	engine.current_command_index = -1
	return Result.success()
