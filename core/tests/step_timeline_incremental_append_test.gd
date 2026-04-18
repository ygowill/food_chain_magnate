class_name StepTimelineIncrementalAppendTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("init failed: %s" % init.error)

	var state := engine.get_state()
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_number = 2
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""

	if not (state.round_state is Dictionary):
		state.round_state = {}
	state.round_state["restructuring"] = {
		"submitted": {0: false, 1: false},
		"finalized": false,
	}
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_RESTRUCTURING: [0, 1]
	}

	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("engine.checkpoints[0] missing or type error")
	var cp: Dictionary = engine.checkpoints[0]
	cp["state_dict"] = state.to_dict().duplicate(true)
	cp["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp

	var submit0 := engine.execute_command(Command.create("submit_restructuring", 0))
	if not submit0.ok:
		return Result.failure("submit_restructuring p0 failed: %s" % submit0.error)
	var submit1 := engine.execute_command(Command.create("submit_restructuring", 1))
	if not submit1.ok:
		return Result.failure("submit_restructuring p1 failed: %s" % submit1.error)

	var state_after := engine.get_state()
	if state_after.phase != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("expected phase OrderOfBusiness, got: %s" % str(state_after.phase))

	var pick0_actor := state_after.get_current_player_id()
	var pick0 := engine.execute_command(Command.create("choose_turn_order", pick0_actor, {"position": 0}))
	if not pick0.ok:
		return Result.failure("choose_turn_order #1 failed: %s" % pick0.error)

	var base_r: Result = StepTimelineBuildClass.build_full(engine)
	if not base_r.ok:
		return Result.failure("build_full(base) failed: %s" % base_r.error)
	if not (base_r.value is Dictionary):
		return Result.failure("build_full(base).value type error (expected Dictionary)")
	var base_timeline: Dictionary = Dictionary(base_r.value).duplicate(true)
	var base_timeline_before_append: Dictionary = base_timeline.duplicate(true)
	var base_processed_count := StepTimelineHelpersClass.read_processed_command_count(base_timeline)
	if base_processed_count != int(engine.command_history.size()):
		return Result.failure(
			"base timeline processed_command_count mismatch: %d vs %d"
				% [base_processed_count, int(engine.command_history.size())]
		)

	state_after = engine.get_state()
	var pick1_actor := state_after.get_current_player_id()
	var pick1 := engine.execute_command(Command.create("choose_turn_order", pick1_actor, {"position": 1}))
	if not pick1.ok:
		return Result.failure("choose_turn_order #2 failed: %s" % pick1.error)

	var append_r: Result = StepTimelineBuildClass.append_from_existing(engine, base_timeline)
	if not append_r.ok:
		return Result.failure("append_from_existing failed: %s" % append_r.error)
	if not (append_r.value is Dictionary):
		return Result.failure("append_from_existing.value type error (expected Dictionary)")
	if base_timeline != base_timeline_before_append:
		return Result.failure("append_from_existing must not mutate the baseline timeline")
	var append_info: Dictionary = Dictionary(append_r.value)
	if not bool(append_info.get("append_applied", false)):
		return Result.failure("append_from_existing should append for tail growth")

	var appended_steps_val = append_info.get("appended_steps", null)
	if not (appended_steps_val is Array) or (appended_steps_val as Array).is_empty():
		return Result.failure("append_from_existing should produce appended_steps")
	var appended_events_val = append_info.get("appended_events", null)
	if not (appended_events_val is Array) or (appended_events_val as Array).is_empty():
		return Result.failure("append_from_existing should produce appended_events")

	var append_timeline: Dictionary = Dictionary(append_info.get("timeline", {})).duplicate(true)
	var append_processed_count := StepTimelineHelpersClass.read_processed_command_count(append_timeline)
	if append_processed_count != int(engine.command_history.size()):
		return Result.failure(
			"append timeline processed_command_count mismatch: %d vs %d"
				% [append_processed_count, int(engine.command_history.size())]
		)

	var full_r: Result = StepTimelineBuildClass.build_full(engine)
	if not full_r.ok:
		return Result.failure("build_full(final) failed: %s" % full_r.error)
	if not (full_r.value is Dictionary):
		return Result.failure("build_full(final).value type error (expected Dictionary)")
	var full_timeline: Dictionary = Dictionary(full_r.value).duplicate(true)

	if append_timeline != full_timeline:
		return Result.failure("incremental append timeline does not match full rebuild")

	var steps_val = append_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	var events_val = append_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var appended_steps: Array = appended_steps_val if (appended_steps_val is Array) else []
	var appended_events: Array = appended_events_val if (appended_events_val is Array) else []

	return Result.success({
		"commands": int(engine.command_history.size()),
		"steps": int(steps.size()),
		"events": int(events.size()),
		"appended_steps": int(appended_steps.size()),
		"appended_events": int(appended_events.size()),
	})
