class_name MarketingPreviewGoldenTest
extends RefCounted

const MarketingPreviewClass = preload("res://core/ai/analysis/marketing_preview.gd")
const MarketingCampaignsTestClass = preload("res://core/tests/marketing_campaigns_test.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MilestoneEffectRegistryClass = preload("res://core/rules/milestone_effect_registry.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")

const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var basic := _test_preview_after_initiate_matches_real_settlement(seed_val)
	if not basic.ok:
		return basic
	return Result.success({"cases": 1})

static func _test_preview_after_initiate_matches_real_settlement(seed_val: int) -> Result:
	var source_read := _build_preview_source_engine(seed_val)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value
	var source_hash_before := str(source.get_state().compute_hash())

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var command := Command.create("initiate_marketing", 0, {
		"employee_type": "marketing_trainee",
		"board_number": 11,
		"product": "burger",
		"duration": 1,
		"position": [0, 2],
	})
	var preview_read := MarketingPreviewClass.preview_after_commands(source, [command], {"max_steps": 24})
	if not preview_read.ok:
		return preview_read
	if str(source.get_state().compute_hash()) != source_hash_before:
		return Result.failure("MarketingPreview should not mutate source engine")
	if MilestoneEffectRegistryClass.get_current() != source.ruleset_v2.milestone_effect_registry:
		return Result.failure("MarketingPreview should restore source milestone effect registry")
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = preview.get("report", {})

	var real_exec := real.execute_command(command.duplicate_command())
	if not real_exec.ok:
		return Result.failure("real initiate_marketing failed: %s" % real_exec.error)
	var real_advance := _advance_real_to_marketing(real, 24)
	if not real_advance.ok:
		return real_advance
	var real_report_val = real.get_state().round_state.get("marketing", null)
	if not (real_report_val is Dictionary):
		return Result.failure("real engine missing marketing report")
	var real_report: Dictionary = real_report_val

	var report_equal := _assert_report_subset_equal(real_report, preview_report)
	if not report_equal.ok:
		return report_equal
	var preview_state_val = preview.get("state", null)
	if not (preview_state_val is GameState):
		return Result.failure("MarketingPreview missing preview state")
	var preview_state: GameState = preview_state_val
	if str(preview_state.compute_hash()) != str(real.get_state().compute_hash()):
		return Result.failure("MarketingPreview final state hash mismatch\nreal=%s\npreview=%s" % [
			str(real.get_state().compute_hash()),
			str(preview_state.compute_hash()),
		])

	var processed_ok := _assert_billboard_processed(preview_report)
	if not processed_ok.ok:
		return processed_ok
	var milestone_ok := _assert_marketing_milestone(preview_state, 0)
	if not milestone_ok.ok:
		return milestone_ok
	return Result.success()

static func _build_preview_source_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	MarketingCampaignsTestClass._force_turn_order(state, 2)
	var actor := state.get_current_player_id()
	if actor != 0:
		return Result.failure("expected actor 0, got %d" % actor)
	var map_result := MarketingCampaignsTestClass._build_test_map(actor)
	if not map_result.ok:
		return map_result
	state.map = map_result.value
	RoadGraphCacheClass.invalidate_road_graph(state)
	state.players[actor]["restaurants"] = ["rest_0"]
	state.players[actor]["cash"] = 100

	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("take marketing_trainee failed: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, actor, "marketing_trainee", false)
	if not add.ok:
		return Result.failure("add marketing_trainee failed: %s" % add.error)

	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_MARKETING
	state.current_player_index = 0
	state.round_state["sub_phase_passed"] = {
		0: false,
		1: false,
	}

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

static func _advance_real_to_marketing(engine: GameEngine, max_steps: int) -> Result:
	for _i in range(max_steps):
		var state := engine.get_state()
		if state != null and state.round_state is Dictionary and Dictionary(state.round_state).get("marketing", null) is Dictionary:
			return Result.success()
		if state == null:
			return Result.failure("real engine state is null")
		if str(state.phase) == DefsClass.PHASE_PAYDAY:
			var adv := engine.phase_manager.advance_phase(state)
			if not adv.ok:
				return Result.failure("real direct Payday advance failed: %s" % adv.error)
			continue
		var command_read := _build_real_fallback_command(state)
		if not command_read.ok:
			return command_read
		var command: Command = command_read.value
		var exec := engine.execute_command(command)
		if not exec.ok:
			return Result.failure("real fallback %s failed: %s" % [command.action_id, exec.error])
	return Result.failure("real engine max_steps reached before marketing report")

static func _build_real_fallback_command(state: GameState) -> Result:
	match str(state.phase):
		DefsClass.PHASE_WORKING:
			var actor := state.get_current_player_id()
			if actor < 0:
				return Result.failure("real Working current player is invalid")
			return Result.success(Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor, {}))
		DefsClass.PHASE_DINNERTIME:
			var pending_dinner := _pending_player_for_kind(state, DefsClass.PHASE_DINNERTIME, KIND_CONFIRM_DINNERTIME)
			if not pending_dinner.ok:
				return pending_dinner
			var pending_actor := int(pending_dinner.value)
			if pending_actor >= 0:
				return Result.success(Command.create(KIND_CONFIRM_DINNERTIME, pending_actor, {}))
			return Result.success(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
		DefsClass.PHASE_MARKETING:
			return Result.failure("real engine reached Marketing without report")
		_:
			return Result.failure("real engine cannot advance from phase before marketing report: %s/%s" % [str(state.phase), str(state.sub_phase)])

static func _pending_player_for_kind(state: GameState, phase_name: String, kind: String) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state is not Dictionary")
	var ppa_val = Dictionary(state.round_state).get("pending_phase_actions", null)
	if ppa_val == null:
		return Result.success(-1)
	if not (ppa_val is Dictionary):
		return Result.failure("round_state.pending_phase_actions is not Dictionary")
	var list_val = Dictionary(ppa_val).get(phase_name, null)
	if list_val == null:
		return Result.success(-1)
	if not (list_val is Array):
		return Result.failure("round_state.pending_phase_actions[%s] is not Array" % phase_name)
	var list: Array = list_val
	for i in range(list.size()):
		var item_val = list[i]
		if not (item_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions[%s][%d] is not Dictionary" % [phase_name, i])
		var item: Dictionary = item_val
		if str(item.get("kind", "")) != kind:
			continue
		return Result.success(int(item.get("player_id", -1)))
	return Result.success(-1)

static func _assert_report_subset_equal(real_report: Dictionary, preview_report: Dictionary) -> Result:
	var keys := [
		"rounds",
		"processed",
		"expired",
		"timeline_events",
	]
	for key in keys:
		var real_val = real_report.get(key, null)
		var preview_val = preview_report.get(key, null)
		if str(real_val) != str(preview_val):
			return Result.failure("MarketingPreview mismatch at %s\nreal=%s\npreview=%s" % [key, str(real_val), str(preview_val)])
	return Result.success()

static func _assert_billboard_processed(report: Dictionary) -> Result:
	var processed_val = report.get("processed", [])
	if not (processed_val is Array):
		return Result.failure("marketing report.processed is not Array")
	var processed: Array = processed_val
	if processed.size() != 1 or not (processed[0] is Dictionary):
		return Result.failure("expected one processed marketing instance, got: %s" % str(processed))
	var item: Dictionary = processed[0]
	if int(item.get("board_number", 0)) != 11:
		return Result.failure("expected board #11, got: %s" % str(item))
	if str(item.get("type", "")) != "billboard":
		return Result.failure("expected billboard type, got: %s" % str(item))
	if int(item.get("demands_added", 0)) != 1:
		return Result.failure("expected one demand added, got: %s" % str(item))
	var affected: Array = item.get("affected_houses", [])
	if affected.size() != 1 or str(affected[0]) != "house_left":
		return Result.failure("expected house_left affected by billboard, got: %s" % str(affected))
	if not bool(item.get("expired", false)):
		return Result.failure("duration=1 billboard should expire, got: %s" % str(item))
	return Result.success()

static func _assert_marketing_milestone(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("state is null")
	var milestones: Array = Dictionary(state.players[player_id]).get("milestones", [])
	if not milestones.has("first_burger_marketed"):
		return Result.failure("Marketing preview should trigger first_burger_marketed, got: %s" % str(milestones))
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
