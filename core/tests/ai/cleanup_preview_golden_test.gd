class_name CleanupPreviewGoldenTest
extends RefCounted

const CleanupPreviewClass = preload("res://core/ai/analysis/cleanup_preview.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var basic := _test_preview_from_marketing_matches_real_cleanup(seed_val)
	if not basic.ok:
		return basic
	var fridge := _test_preview_after_fridge_keep_matches_real_cleanup(seed_val)
	if not fridge.ok:
		return fridge
	return Result.success({"cases": 2})

static func _test_preview_from_marketing_matches_real_cleanup(seed_val: int) -> Result:
	var source_read := _build_marketing_source_engine(seed_val)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value
	var state := source.get_state()
	state.players[0]["inventory"] = {
		"burger": 2,
		"soda": 1,
	}
	var sync := _sync_initial_checkpoint_to_current_state(source)
	if not sync.ok:
		return sync
	var source_hash_before := str(source.get_state().compute_hash())

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var preview_read := CleanupPreviewClass.preview_after_commands(source, [], {"max_steps": 8})
	if not preview_read.ok:
		return preview_read
	if str(source.get_state().compute_hash()) != source_hash_before:
		return Result.failure("CleanupPreview should not mutate source engine")
	if MilestoneEffectRegistryClass.get_current() != source.ruleset_v2.milestone_effect_registry:
		return Result.failure("CleanupPreview should restore source milestone effect registry")
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = Dictionary(preview.get("report", {}))

	var real_advance := _advance_real_marketing_to_cleanup(real)
	if not real_advance.ok:
		return real_advance
	var report_equal := _assert_report_subset_equal(Dictionary(real.get_state().round_state.get("cleanup", {})), preview_report)
	if not report_equal.ok:
		return report_equal
	var preview_state_read := _preview_state(preview)
	if not preview_state_read.ok:
		return preview_state_read
	var preview_state: GameState = preview_state_read.value
	if str(preview_state.phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("CleanupPreview should stop at Cleanup after direct Marketing advance, got %s/%s" % [str(preview_state.phase), str(preview_state.sub_phase)])
	if str(preview_state.compute_hash()) != str(real.get_state().compute_hash()):
		return Result.failure("CleanupPreview final state hash mismatch\nreal=%s\npreview=%s" % [
			str(real.get_state().compute_hash()),
			str(preview_state.compute_hash()),
		])
	var burger_discard := _assert_discarded(preview_report, 0, "burger", 2)
	if not burger_discard.ok:
		return burger_discard
	return _assert_discarded(preview_report, 0, "soda", 1)

static func _test_preview_after_fridge_keep_matches_real_cleanup(seed_val: int) -> Result:
	var source_read := _build_fridge_pending_cleanup_source_engine(seed_val)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value
	var source_hash_before := str(source.get_state().compute_hash())

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var command := Command.create("choose_fridge_keep", 1, {
		"keep": {
			"burger": 4,
			"beer": 2,
		}
	})
	var preview_read := CleanupPreviewClass.preview_after_commands(source, [command], {"max_steps": 8})
	if not preview_read.ok:
		return preview_read
	if str(source.get_state().compute_hash()) != source_hash_before:
		return Result.failure("CleanupPreview fridge keep preview should not mutate source engine")
	if MilestoneEffectRegistryClass.get_current() != source.ruleset_v2.milestone_effect_registry:
		return Result.failure("CleanupPreview fridge keep preview should restore source milestone effect registry")
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = Dictionary(preview.get("report", {}))
	var commands_executed: Array = Array(preview.get("commands_executed", []))
	if commands_executed.size() != 1 or str(Dictionary(commands_executed[0]).get("action_id", "")) != "choose_fridge_keep":
		return Result.failure("CleanupPreview should record choose_fridge_keep command execution: %s" % str(commands_executed))

	var real_choose := _execute_cleanup_command_without_auto_skip(real, command.duplicate_command())
	if not real_choose.ok:
		return Result.failure("real choose_fridge_keep failed: %s" % real_choose.error)
	var report_equal := _assert_report_subset_equal(Dictionary(real.get_state().round_state.get("cleanup", {})), preview_report)
	if not report_equal.ok:
		return report_equal
	var preview_state_read := _preview_state(preview)
	if not preview_state_read.ok:
		return preview_state_read
	var preview_state: GameState = preview_state_read.value
	if str(preview_state.compute_hash()) != str(real.get_state().compute_hash()):
		return Result.failure("CleanupPreview fridge keep final state hash mismatch\nreal=%s\npreview=%s" % [
			str(real.get_state().compute_hash()),
			str(preview_state.compute_hash()),
		])
	if bool(preview_report.get("fridge_choice_pending", true)):
		return Result.failure("CleanupPreview fridge keep should clear fridge_choice_pending: %s" % str(preview_report))
	var inv1: Dictionary = Dictionary(preview_state.players[1]).get("inventory", {})
	if int(inv1.get("burger", 0)) != 4 or int(inv1.get("beer", 0)) != 2:
		return Result.failure("CleanupPreview fridge keep inventory mismatch: %s" % str(inv1))
	var burger_discard := _assert_discarded(preview_report, 1, "burger", 8)
	if not burger_discard.ok:
		return burger_discard
	return _assert_discarded(preview_report, 1, "beer", 1)

static func _build_marketing_source_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_MARKETING
	state.sub_phase = ""
	state.round_number = 1
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.players[0]["inventory"] = {}
	state.players[1]["inventory"] = {}
	var sync := _sync_initial_checkpoint_to_current_state(engine)
	if not sync.ok:
		return sync
	return Result.success(engine)

static func _build_fridge_pending_cleanup_source_engine(seed_val: int) -> Result:
	var source_read := _build_marketing_source_engine(seed_val)
	if not source_read.ok:
		return source_read
	var engine: GameEngine = source_read.value
	var state := engine.get_state()
	var claim := StateUpdaterClass.claim_milestone(state, 1, "first_throw_away")
	if not claim.ok:
		return Result.failure("claim first_throw_away failed: %s" % claim.error)
	state.players[1]["inventory"] = {
		"burger": 12,
		"beer": 3,
	}
	var sync_before := _sync_initial_checkpoint_to_current_state(engine)
	if not sync_before.ok:
		return sync_before
	var advance := _advance_real_marketing_to_cleanup(engine)
	if not advance.ok:
		return advance
	if str(engine.get_state().phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("expected Cleanup pending source, got %s/%s" % [str(engine.get_state().phase), str(engine.get_state().sub_phase)])
	if engine.get_state().get_current_player_id() != 1:
		return Result.failure("expected fridge pending current player 1, got %d" % engine.get_state().get_current_player_id())
	var cleanup: Dictionary = Dictionary(engine.get_state().round_state.get("cleanup", {}))
	if not bool(cleanup.get("fridge_choice_pending", false)):
		return Result.failure("expected fridge_choice_pending cleanup source: %s" % str(cleanup))
	var sync_after := _sync_initial_checkpoint_to_current_state(engine)
	if not sync_after.ok:
		return sync_after
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

static func _advance_real_marketing_to_cleanup(engine: GameEngine) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("real engine/state is null")
	var state := engine.get_state()
	if str(state.phase) != DefsClass.PHASE_MARKETING:
		return Result.failure("real engine expected Marketing, got %s/%s" % [str(state.phase), str(state.sub_phase)])
	var advance := engine.phase_manager.advance_phase(state)
	if not advance.ok:
		return Result.failure("real direct Marketing advance failed: %s" % advance.error)
	if not (state.round_state is Dictionary) or not (Dictionary(state.round_state).get("cleanup", null) is Dictionary):
		return Result.failure("real engine missing cleanup report after direct advance")
	return Result.success()

static func _execute_cleanup_command_without_auto_skip(engine: GameEngine, command: Command) -> Result:
	if engine == null or engine.get_state() == null:
		return Result.failure("real cleanup engine/state is null")
	var state := engine.get_state()
	if str(state.phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("real engine expected Cleanup, got %s/%s" % [str(state.phase), str(state.sub_phase)])
	if engine.action_registry == null:
		return Result.failure("real engine action registry is null")
	var executor := engine.action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("real engine unknown action: %s" % str(command.action_id))
	if command.phase.is_empty():
		command.phase = state.phase
	if command.sub_phase.is_empty():
		command.sub_phase = state.sub_phase
	if command.timestamp < 0:
		command.timestamp = DefsClass.compute_timestamp(state)
	var gate := engine.action_registry.run_validators(state, command)
	if not gate.ok:
		return gate
	var compute := executor.compute_new_state(state, command)
	if not compute.ok:
		return compute
	engine.state = compute.value
	return Result.success(engine.state).with_warnings(compute.warnings)

static func _preview_state(preview: Dictionary) -> Result:
	var preview_state_val = preview.get("state", null)
	if not (preview_state_val is GameState):
		return Result.failure("CleanupPreview missing preview state")
	return Result.success(preview_state_val)

static func _assert_report_subset_equal(real_report: Dictionary, preview_report: Dictionary) -> Result:
	var keys := [
		"inventory_discarded",
		"fridge_choice_pending",
	]
	for key in keys:
		var real_val = real_report.get(key, null)
		var preview_val = preview_report.get(key, null)
		if str(real_val) != str(preview_val):
			return Result.failure("CleanupPreview mismatch at %s\nreal=%s\npreview=%s" % [key, str(real_val), str(preview_val)])
	return Result.success()

static func _assert_discarded(report: Dictionary, player_id: int, product_id: String, amount: int) -> Result:
	var list_val = report.get("inventory_discarded", [])
	if not (list_val is Array):
		return Result.failure("cleanup.inventory_discarded is not Array: %s" % str(report))
	for item_val in Array(list_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("player_id", -1)) != player_id:
			continue
		var discarded_val = item.get("discarded", {})
		if not (discarded_val is Dictionary):
			return Result.failure("cleanup.inventory_discarded[%d].discarded is not Dictionary: %s" % [player_id, str(item)])
		var discarded: Dictionary = discarded_val
		var actual := int(discarded.get(product_id, 0))
		if actual != amount:
			return Result.failure("CleanupPreview discarded mismatch player=%d product=%s: %d != %d report=%s" % [
				player_id,
				product_id,
				actual,
				amount,
				str(report),
			])
		return Result.success()
	return Result.failure("cleanup.inventory_discarded missing player %d: %s" % [player_id, str(report)])

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
