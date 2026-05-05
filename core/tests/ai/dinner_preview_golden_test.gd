class_name DinnerPreviewGoldenTest
extends RefCounted

const DinnerPreviewClass = preload("res://core/ai/analysis/dinner_preview.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var basic := _test_preview_matches_real_settlement(seed_val, false)
	if not basic.ok:
		return basic
	var garden := _test_preview_matches_real_settlement(seed_val, true)
	if not garden.ok:
		return garden
	return Result.success({"cases": 2})

static func _test_preview_matches_real_settlement(seed_val: int, with_garden: bool) -> Result:
	var source_read := _build_preview_source_engine(seed_val, with_garden)
	if not source_read.ok:
		return source_read
	var source: GameEngine = source_read.value

	var real_read := _clone_from_archive(source)
	if not real_read.ok:
		return real_read
	var real: GameEngine = real_read.value

	var preview_read := DinnerPreviewClass.preview_after_commands(source, [], {"max_steps": 8})
	if not preview_read.ok:
		return preview_read
	var preview: Dictionary = preview_read.value
	var preview_report: Dictionary = preview.get("report", {})

	var real_advance := _advance_real_to_dinnertime(real, 8)
	if not real_advance.ok:
		return real_advance
	var real_report_val = real.get_state().round_state.get("dinnertime", null)
	if not (real_report_val is Dictionary):
		return Result.failure("real engine missing dinnertime report")
	var real_report: Dictionary = real_report_val

	var reports_equal := _assert_report_subset_equal(real_report, preview_report)
	if not reports_equal.ok:
		return reports_equal
	var inventory_equal := _assert_player_inventories_equal(real.get_state(), preview.get("state", null))
	if not inventory_equal.ok:
		return inventory_equal
	return Result.success()

static func _build_preview_source_engine(seed_val: int, with_garden: bool) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var state := engine.get_state()
	DinnertimeSettlementTestClass._force_turn_order(state)
	DinnertimeSettlementTestClass._apply_test_map(state)
	DinnertimeSettlementTestClass._set_house_demands(state, "house_left", [{"product": "burger"}])
	DinnertimeSettlementTestClass._set_house_demands(state, "house_right", [{"product": "pizza"}])
	if with_garden:
		DinnertimeSettlementTestClass._set_house_garden(state, "house_left", true)
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["pizza"] = 1
	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["pizza"] = 1
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_PLACE_RESTAURANTS
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

static func _advance_real_to_dinnertime(engine: GameEngine, max_steps: int) -> Result:
	for _i in range(max_steps):
		var state := engine.get_state()
		if state != null and state.round_state is Dictionary and Dictionary(state.round_state).get("dinnertime", null) is Dictionary:
			return Result.success()
		if state == null:
			return Result.failure("real engine state is null")
		if str(state.phase) != DefsClass.PHASE_WORKING:
			return Result.failure("real engine cannot advance from phase without dinnertime report: %s/%s" % [str(state.phase), str(state.sub_phase)])
		var actor := state.get_current_player_id()
		var command := Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor, {})
		var exec := engine.execute_command(command)
		if not exec.ok:
			return Result.failure("real skip_sub_phase failed: %s" % exec.error)
	return Result.failure("real engine max_steps reached before dinnertime report")

static func _assert_report_subset_equal(real_report: Dictionary, preview_report: Dictionary) -> Result:
	var keys := [
		"sales",
		"skipped",
		"income_sales",
		"income_sale_house_bonus",
		"income_tips",
		"income_cfo_bonus",
		"total_income",
		"bankruptcy_events",
	]
	for key in keys:
		var real_val = real_report.get(key, null)
		var preview_val = preview_report.get(key, null)
		if str(real_val) != str(preview_val):
			return Result.failure("DinnerPreview mismatch at %s\nreal=%s\npreview=%s" % [key, str(real_val), str(preview_val)])
	return Result.success()

static func _assert_player_inventories_equal(real_state: GameState, preview_state) -> Result:
	if real_state == null or not (preview_state is GameState):
		return Result.failure("inventory compare missing state")
	var sim_state: GameState = preview_state
	for pid in range(real_state.players.size()):
		var real_inv = Dictionary(real_state.players[pid]).get("inventory", {})
		var preview_inv = Dictionary(sim_state.players[pid]).get("inventory", {})
		if str(real_inv) != str(preview_inv):
			return Result.failure("inventory mismatch for player %d\nreal=%s\npreview=%s" % [pid, str(real_inv), str(preview_inv)])
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
